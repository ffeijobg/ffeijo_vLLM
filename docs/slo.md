# SLO: vLLM lab service

Lab values on one 4 GB GPU, one replica, kind on one host. Not a production commitment.
Last updated: 2026-11-14

## 1. Service

vLLM v0.33.0 serving Qwen/Qwen2.5-0.5B as `lab-model`, one replica, behind the `vllm` Service in namespace `inference`.
Measured from outside by `llm-prober` (a real chat completion every 15 s) and from inside by vLLM's `/metrics`.

## 2. SLIs, targets and current values

| SLI | Definition | Lab target | Measured (idle) |
| --- | --- | --- | --- |
| Availability | ok probes over all probes, 5 m | 99.5% over 28 days | 100% |
| p95 time to first token | `vllm:time_to_first_token_seconds` histogram, 5 m | under 1 s | 0.058 s |
| p95 inter-token latency | `vllm:inter_token_latency_seconds` histogram, 5 m | under 100 ms | 0.024 s |
| Queue depth | average `vllm:num_requests_waiting`, 5 m | under 5 | 0 |
| GPU memory used | DCGM FB_USED over FB_USED plus FB_FREE | under 95% | 78% |

Load-test knee (concurrent users where p95 first breaks the target): TODO.

## 3. Error budget

99.5% over 28 days allows 0.5% failure: 40,320 minutes x 0.005 is about 201 minutes.

## 4. Alerts and measured detection

| Alert | Fires when | Measured |
| --- | --- | --- |
| `LLMProberStale` | no successful probe for 2 min, or the metric is absent, held 1 min | prober alive but vLLM down: pending after 2 m 16 s. Prober gone: pending after 40 s |
| `LLMErrorBudgetFastBurn` | 1 h and 5 m error ratio both above 7.2% (14.4 x 0.005), held 2 min | vLLM down: pending after 4 m 46 s, firing about 6 m 46 s |

Notes:

- Firing times are pending time plus the rule's `for` window (calculated).
- The burn-rate alert needs both windows above the threshold, so it clears a few minutes after probes recover: measured 4 m 40 s after the pod was 1/1. The stale alert cleared within about 10 s.
- The stale rule needs the `absent()` branch. Without it, a missing prober produces no result and nothing fires. With the prober gone, the burn-rate alert stays silent (no data), which is why the stale alert exists.
- Recovery: after scale-up the vLLM pod reached 1/1 in 70 s.

## 5. Policy

- More than half the budget spent: freeze risky releases and require the gate on every change.
- Budget exhausted: reliability work only until it recovers.
- Page on the burn-rate alert. The stale alert means monitoring itself is blind.

## 6. Known limits

- One replica: a restart is an outage of about 70 s. A gate can detect a bad release but cannot shield users from it.
- At `--gpu-memory-utilization 0.80` one pod uses about 2.9 GiB and a second does not fit. At 0.40 a pod uses about 1.3 GiB and two fit together (peak 2678 MiB of 4094 MiB), which blue-green needs.
- Time-slicing gives two scheduling slots on one GPU but shares memory without isolation.
- A PostSync gate can stall auto-heal when a release is unhealthy. A retry policy and manual termination are the remedies.
- Probe availability only covers what the prober's prompt exercises.
- Targets are chosen for a lab, not derived from user need.
