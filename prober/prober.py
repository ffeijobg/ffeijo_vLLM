# prober/prober.py
import argparse, json, os, random, sys, time
import requests
from prometheus_client import Counter, Gauge, Histogram, start_http_server

ENDPOINT = os.getenv("ENDPOINT", "http://vllm.inference.svc:8000")
MODEL = os.getenv("MODEL", "lab-model")
LATENCY_BUDGET_S = float(os.getenv("LATENCY_BUDGET_S", "5"))

REQS = Counter("llm_probe_requests_total", "Probe attempts", ["result"])
DURATION = Histogram("llm_probe_duration_seconds", "Total request time",
                     buckets=(0.25, 0.5, 1, 2, 4, 8, 16))
TTFT = Gauge("llm_probe_ttft_seconds", "Time to first generated token")
LAST_OK = Gauge("llm_probe_last_success_timestamp_seconds", "Unix time of last good probe")


def probe_once(timeout=30):
    body = {"model": MODEL, "max_tokens": 8, "stream": True,
            "messages": [{"role": "user", "content": "Reply with the single word: ok"}]}
    start, first, parts = time.monotonic(), None, []
    with requests.post(f"{ENDPOINT}/v1/chat/completions", json=body,
                       timeout=timeout, stream=True) as r:
        r.raise_for_status()
        for line in r.iter_lines():
            if not line.startswith(b"data: "):
                continue
            payload = line[6:]
            if payload == b"[DONE]":
                break
            delta = json.loads(payload)["choices"][0]["delta"].get("content")
            if delta:
                if first is None:
                    first = time.monotonic() - start
                parts.append(delta)
    if not "".join(parts).strip():
        raise ValueError("empty completion")      # a 200 with no text is still a failure
    return time.monotonic() - start, first


def probe_with_retry(retries, base_delay=0.5):
    for attempt in range(retries + 1):
        try:
            result = probe_once()
            REQS.labels("ok").inc()
            return result
        except (requests.RequestException, ValueError, KeyError, json.JSONDecodeError):
            REQS.labels("error").inc()           # count every attempt, so retries do not hide errors
            if attempt == retries:
                raise
            time.sleep(base_delay * 2 ** attempt + random.uniform(0, 0.25))   # backoff + jitter


def run_one(retries):
    try:
        total, first = probe_with_retry(retries)
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return False
    DURATION.observe(total)
    if first is not None:
        TTFT.set(first)
    LAST_OK.set_to_current_time()
    print(f"OK total={total:.2f}s ttft={first if first is None else round(first, 2)}s")
    return total <= LATENCY_BUDGET_S              # too slow counts as failing the gate


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", type=int, help="loop forever and expose metrics on this port")
    ap.add_argument("--interval", type=float, default=15)
    ap.add_argument("--retries", type=int, default=3)
    args = ap.parse_args()
    if args.serve:
        start_http_server(args.serve)
        while True:
            run_one(retries=0)                    # a continuous prober should not hide errors with retries
            time.sleep(args.interval)
    sys.exit(0 if run_one(args.retries) else 1)
