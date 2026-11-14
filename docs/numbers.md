# Lab numbers

Lab values: one 4 GB NVIDIA RTX A400, one vLLM replica, kind on one host.
Measured 2026-11-14. Times are UTC unless a row says otherwise.
The host clock is not NTP-synced (see Open items), so use durations, not absolute times, when comparing runs.

## Service baseline (idle)

| Item | Value |
| --- | --- |
| vLLM version and model | v0.33.0, Qwen2.5-0.5B served as `lab-model` |
| Settings at first baseline | `--max-model-len 4096`, `--gpu-memory-utilization 0.80`; later changed to 0.40 (with `--max-num-seqs 16`) so two pods fit, see the rollout section |
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

- [x] Burn-rate alert clear time: 4 m 40 s after the pod was 1/1 (experiment A)
- [x] Stale alert clear time: within about 10 s of the pod being 1/1 (first successful probe)
- [x] Blue-green gate timings: recorded in the rollout section above (the PostSync hook bad-release test was not run separately)
- [ ] Load-test knee: concurrent users and tokens per second
- [ ] Warm restart to Ready (NFS cache warm)

## Open items

- [ ] Host clock: `timedatectl` reports `System clock synchronized: no` and no NTP service. Install and enable time sync after the next lab block.
- [ ] Grafana admin password: rotate it (it was printed in a terminal session).

## Blue-green rollout on the real vLLM (budget 0.40 per pod, so two pods fit)

Capacity: one pod at `--gpu-memory-utilization 0.40` uses about 1340 MiB; both pods up peaked at 2678 MiB of 4094 MiB.
At 0.80 the green pod could not start: "Free memory on device (0.71/3.68 GiB) is less than desired GPU memory utilization (0.8, 2.94 GiB)".

| Release | Commit (UTC) | Green ReplicaSet created | Result |
| --- | --- | --- | --- |
| Good: add `release: 2` label | 20:17:46 (607fea5) | 20:20:50 (+3 m 04 s, Git poll) | Analysis started 61 s later (model load), three probes about 30 s apart, promoted; blue scaled down after the 60 s delay |
| Bad: wrong served model name | 20:28:14 (88dfcbc) | 20:31:49 (+3 m 35 s) | Pod Ready, analysis started 20:32:50, probe got 404, Rollout aborted 20:32:52. Commit to abort 4 m 38 s; ReplicaSet to abort 63 s |
| Bad: `--max-model-len 1000000` | 20:42:03 (d16c2f6) | 20:43:25 (+1 m 22 s) | Config validation error (derived limit 32768), pod crash-looped, never Ready, no analysis. Reverted at 20:45:31 before the 300 s deadline |

- Probe errors, 45 min from 20:10:57 UTC: 8, all between 20:10:57 and 20:15:27 (the planned delete and recreate). Zero errors during the good release, the wrong-model-name release, its revert, and the oversized-context release (about 20:20 to 20:50).
- Reverts reuse the stable ReplicaSet and create no new pod.
- Git poll delay was 3 minutes on two releases and 1 m 22 s on the third.
- Reverting a bad release restored the exact pod template: `git diff 607fea5 HEAD -- gitops/vllm/rollout.yaml` was empty, the stable ReplicaSet was reused (no new pod), and the PostSync gate re-ran and passed.
- Planned delete and recreate of the Rollout (memory-budget change): probe errors from 20:10:57 to 20:15:27 (about 4.5 minutes), because blue restarted twice before becoming ready. Cause of the restarts not verified.

## Alert history observed (UTC, 30 s resolution)

| Period | Cause | LLMProberStale firing | LLMErrorBudgetFastBurn firing |
| --- | --- | --- | --- |
| 17:39 to 18:01 | Experiment A: vLLM stopped | ended 18:00:57 | ended 18:05:27 (4 m 40 s after the pod was 1/1) |
| 18:40 to 18:51 | Experiment B: prober stopped | 18:42:27 to 18:50:57 | did not fire |
| 19:07 to 19:29 | vLLM down after a manifest move (missing Service, invalid image, VLLM_PORT crash loop) | 19:07:27 to 19:25:27 | 19:09:27 to 19:29:27 |
| 20:10 to 20:19 | Planned recreate for the memory budget | did not fire | 20:12:57 to 20:19:27 |

Query range starts cut off the first window; the earlier start times for experiment A are in the detection table above.
