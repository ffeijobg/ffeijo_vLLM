#!/usr/bin/env python3
"""Write gitops/vllm/dashboard-configmap.yaml: a Grafana dashboard as a ConfigMap that the
kube-prometheus-stack Grafana sidecar loads (label grafana_dashboard=1). Run from the repo root."""
import json, pathlib

def t(expr, legend, ref):
    return {"expr": expr, "legendFormat": legend, "refId": ref}

def panel(pid, title, kind, x, y, w, h, targets, unit=None, extra=None):
    p = {"id": pid, "title": title, "type": kind, "gridPos": {"x": x, "y": y, "w": w, "h": h},
         "targets": targets, "fieldConfig": {"defaults": {"unit": unit} if unit else {}, "overrides": []}}
    p.update(extra or {})
    return p

PANELS = [
    panel(1, "Probe availability (5m)", "stat", 0, 0, 6, 5,
          [t('sum(rate(llm_probe_requests_total{result="ok"}[5m])) / sum(rate(llm_probe_requests_total[5m]))', "availability", "A")],
          "percentunit", {"options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "value"}}),
    panel(2, "p95 time to first token and inter-token latency", "timeseries", 6, 0, 18, 8,
          [t('histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))', "p95 TTFT", "A"),
           t('histogram_quantile(0.95, sum by (le) (rate(vllm:inter_token_latency_seconds_bucket[5m])))', "p95 inter-token", "B")], "s"),
    panel(3, "Queue depth, running requests, KV cache %", "timeseries", 0, 8, 12, 8,
          [t('sum(vllm:num_requests_waiting)', "waiting", "A"), t('sum(vllm:num_requests_running)', "running", "B"),
           t('100 * max(vllm:kv_cache_usage_perc)', "KV cache %", "C")]),
    panel(4, "GPU memory used and GPU utilisation (%)", "timeseries", 12, 8, 12, 8,
          [t('100 * max(DCGM_FI_DEV_FB_USED) / (max(DCGM_FI_DEV_FB_USED) + max(DCGM_FI_DEV_FB_FREE))', "memory used %", "A"),
           t('max(DCGM_FI_DEV_GPU_UTIL)', "GPU util %", "B")], "percent"),
    panel(5, "Probe latency (mean) and probe time to first token", "timeseries", 0, 16, 24, 8,
          [t('sum(rate(llm_probe_duration_seconds_sum[5m])) / sum(rate(llm_probe_duration_seconds_count[5m]))', "probe mean duration", "A"),
           t('max(llm_probe_ttft_seconds)', "probe TTFT (last)", "B")], "s"),
]
DASH = {"uid": "llm-lab", "title": "LLM lab: vLLM, GPU and prober", "tags": ["llm", "lab"], "timezone": "browser",
        "schemaVersion": 39, "version": 1, "refresh": "30s", "time": {"from": "now-1h", "to": "now"}, "panels": PANELS}

body = "\n".join("    " + line for line in json.dumps(DASH, indent=2).splitlines())
yaml = ("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: llm-dashboard\n  namespace: monitoring\n"
        "  labels:\n    grafana_dashboard: \"1\"\ndata:\n  llm-lab.json: |\n" + body + "\n")
out = pathlib.Path("gitops/vllm/dashboard-configmap.yaml")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(yaml)
print("wrote", out, len(yaml), "bytes,", len(PANELS), "panels")
