# Lab numbers

Lab values: one 4 GB NVIDIA RTX A400, one vLLM replica, kind on one host.
Measured 2026-11-14. Times are UTC unless a row says otherwise.
The host clock is not NTP-synced (see Open items), so use durations, not absolute times, when comparing runs.

## Service baseline (idle)

| Item | Value |
| --- | --- |
| vLLM version and model | v0.33.0, Qwen2.5-0.5B served as `lab-model` |
| Settings | `--max-model-len 4096`, `--gpu-memory-utilization 0.80` |
| Cold start (pod Running to 1/1) | 70 s (image already on the node, weights on a host mount) |
| Probe mean latency | about 115 to 125 ms |
| p95 time to first token | 0.058 s |
| p95 inter-token latency | 0.024 s |
| Availability | 1.0 |
| Queue depth | 0 |
| GPU memory in use | 2948 MiB of 4094 MiB |
| GPU temperature (idle) | 49 C |

## Alert detection

### Experiment A: vLLM stopped, prober alive

| Event | Time | After scale-down |
| --- | --- | --- |
| vLLM scaled to 0 | 17:39:54 | 0 |
| `LLMProberStale` pending | 17:42:10 | 2 m 16 s |
| `LLMProberStale` firing | about 17:43:10 | about 3 m 16 s (pending plus 1 m, calculated) |
| `LLMErrorBudgetFastBurn` pending | 17:44:40 | 4 m 46 s |
| `LLMErrorBudgetFastBurn` firing | about 17:46:40 | about 6 m 46 s (pending plus 2 m, calculated) |
| vLLM scaled back to 1 | 17:59:37 | 19 m 43 s |
| Pod 1/1 after scale-up | 70 s later | cold start |

### Experiment B: prober scaled to 0, with the `absent()` fix

| Event | Time | After scale-down |
| --- | --- | --- |
| Prober scaled to 0 | 18:40:30 | 0 |
| `LLMProberStale` pending | 18:41:10 | 40 s |
| `LLMProberStale` firing | observed at 18:42:54 | under 2 m 24 s |
| `LLMErrorBudgetFastBurn` | never appeared (checked to 18:50:02) | silent for more than 9 minutes |

Before the fix, the stale rule did not fire at all when the prober was gone: a missing metric returns no result.

## GPU and cluster facts

- Time-slicing is on: allocatable `nvidia.com/gpu` is 2, but there is still one physical GPU. Memory is shared, not isolated.
- DCGM exposes `DCGM_FI_DEV_FB_USED` and `DCGM_FI_DEV_GPU_TEMP`. It does not expose `POWER_USAGE` or `XID_ERRORS`.
- `sudo dmesg | grep -i xid` returned nothing (no GPU fault messages).
- Self-heal check: a deleted `ServiceMonitor` was re-created by ArgoCD within 20 s.

## To measure

- [ ] Burn-rate alert clear time after recovery (expected about 5 minutes: it needs both windows above 7.2%)
- [ ] Stale alert clear time after the prober returned
- [ ] Bad-release gate: push to failed probe, push to gate failure, revert to healthy
- [ ] Load-test knee: concurrent users and tokens per second
- [ ] Warm restart to Ready (NFS cache warm)

## Open items

- [ ] Host clock: `timedatectl` reports `System clock synchronized: no` and no NTP service. Install and enable time sync after the next lab block.
- [ ] Grafana admin password: rotate it (it was printed in a terminal session).
