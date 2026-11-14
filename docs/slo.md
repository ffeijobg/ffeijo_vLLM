# SLO: vLLM lab service

Lab values on one 4 GB GPU, single replica, kind on one host. Not a production commitment.
Last updated: 2026-11-14

## 1. Service

vLLM v0.33.0 serving Qwen/Qwen2.5-0.5B as `lab-model`, one replica, behind the `vllm` Service
in namespace `inference`. Measured from outside by `llm-prober` (a real chat completion every
15 s) and from inside by vLLM's own `/metrics`.

## 2. SLIs, targets and current values

| SLI | Definition (query summary) | Lab target | Measured (idle, 2026-11-14) |
| --- | --- | --- | --- |
| Availability | ok probes / all probes, 5 m | 99.5% over 28 days | 100% |
| p95 time to first token | `vllm:time_to_first_token_seconds` histogram, 5 m | under 1 s | 0.058 s |
| p95 inter-token latency | `vllm:inter_token_latency_seconds` histogram, 5 m | under 100 ms | 0.024 s |
| Queue depth | avg `vllm:num_requests_waiting`, 5 m | under 5 | 0 |
| GPU memory used | DCGM FB_USED / (FB_USED + FB_FREE) | under 95% | 78% |

Load-test knee (concurrent users where p95 first breaks the target): TODO after step 6.8.

## 3. Error budget

99.5% over 28 days allows 0.5% failure: 40,320 min x 0.005 = about 201 minutes.

## 4. Alerts

| Alert | Fires when | Measured detection (outage began 17:39:54 UTC) |
| --- | --- | --- |
| LLMProberStale | no successful probe for 2 min, held 1 min | pending after 2 m 16 s, firing about 3 m 16 s |
| LLMErrorBudgetFastBurn | 1 h and 5 m error ratio both above 7.2% (14.4 x 0.005), held 2 min | pending after 4 m 46 s, firing about 6 m 46 s |

Notes:
- Firing times are pending time plus the rule's `for` window (calculated, not separately observed).
- The burn-rate alert clears slowly because the 1 h ratio must fall back under 7.2%:
  cleared TODO minutes after recovery.
- The stale alert is the only guard if the prober itself dies. A ratio with no data fires
  nothing. Experiment B: TODO result.
- Recovery: vLLM back to 1/1 in 70 s after scale-up (cold start, image already on node).

## 5. Policy

- Budget more than half spent: freeze risky releases; every change must pass the gate.
- Budget exhausted: reliability work only until it recovers.
- Page on the burn-rate alert; the stale alert warns that monitoring itself is blind.

## 6. Known limits

- One replica: a restart is an outage of about 70 s. A gate can detect a bad release
  but cannot shield users from it.
- Probe availability cannot see failures the prober's prompt does not exercise.
- Targets are chosen for a lab, not derived from user need.
