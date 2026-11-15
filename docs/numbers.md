# Lab numbers

Lab values: one 4 GB NVIDIA RTX A400, one vLLM replica, kind on one host.
Measured 2026-11-14 and 2026-11-15. Times are UTC unless a row says otherwise.
The host clock is not NTP-synced (see Open items), so use durations, not absolute times, when comparing runs.

## Service baseline (idle)

| Item | Value |
| --- | --- |
| vLLM version and model | v0.33.0, Qwen2.5-0.5B served as `lab-model` |
| Settings at first baseline | `--max-model-len 4096`, `--gpu-memory-utilization 0.80`; later changed to 0.40 with `--max-model-len 2048` and `--max-num-seqs 16` so two pods fit, see the rollout section |
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
- [x] Load-test knee: queueing from about 20 users (details in the load test section; tokens per second TODO)
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

## Canary on a CPU stub (Argo Rollouts, 5 replicas, steps 20% > analysis > 50% > 30 s pause > 100%)

Times UTC; commit times converted from CST. Pod-count weighting: with 5 replicas the smallest step is 20%.

| Release | Commit | ReplicaSet created | Analysis created | Result |
| --- | --- | --- | --- | --- |
| Good (release label 2) | 04:24:45 | 04:27:31 (+2 m 46 s, Git poll) | 04:27:32 | Successful, 3 of 3 probes, promoted to 100% |
| Bad (wrong model name) | 04:30:54 | 04:33:36 (+2 m 42 s, Git poll) | 04:33:37 | Failed on the first probe (failureLimit 0), aborted |
| Retry of the bad revision | n/a | n/a | 04:36:53 | Failed again: retry cannot fix a bad spec |
| Revert | 04:40:14 | n/a | n/a | Rollout back to Healthy, five stable pods |

- The analysis starts about 1 s after the canary ReplicaSet is created, because the stub is Ready almost instantly (the real vLLM needs about 61 s to load).
- Failed analyses stop at the first failing probe, so no run shows probe 2 or 3.
- Both Services select the stable pod-template hash when no rollout is running (verified: `cd754d6f7` for 2 minutes).
- Verbs used and their order: TODO (from shell history).

## Host reboot recovery (2026-11-15, unplanned)

| Event | Time (UTC) | After boot |
| --- | --- | --- |
| Host boot | 16:23:24 | 0 |
| vLLM pod started | 16:25:37 | 2 m 13 s |
| vLLM pod Ready | 16:26:57 | 3 m 33 s |

- vLLM pod start to Ready: 80 s (weights probably read cold after the reboot; not verified).
- One pod from before the reboot ended in `UnexpectedAdmissionError`: the kubelet re-admitted it before the NVIDIA device plugin had registered the GPU. The ReplicaSet created a replacement that came up normally; the stale pod was deleted by hand.
- After recovery: all three ArgoCD apps Synced and Healthy, both Rollouts Healthy, no LLM alert firing, 20 of 20 probes ok over the next 5 minutes.

## Drill: kill the vLLM pod (poller every 2 s, in-cluster `curl -m 2`)

| Event | Time (UTC) | After last good response |
| --- | --- | --- |
| Last 200 | 16:50:40 | 0 |
| First 000 | 16:50:42 | +2 s |
| Last 000 | 16:51:42 | +62 s |
| First 200 again | 16:51:44 | +64 s |

- User-visible outage: 62 to 64 s (poll granularity 2 s). `kubectl delete` plus Ready watch measured about 70 s.
- Failure mode: connection refused or timeout (`000`), not an HTTP error, because the Service had no ready endpoints.
- No alert fired: the 1-hour error ratio stayed under the 7.2% fast-burn threshold, and `LLMProberStale` needs more than 120 s without a good probe.
- Cold start for comparison: about 70 s earlier in the day, 3 m 33 s after the host reboot.

[200~cat >> docs/numbers.md <<'EOF'

## Drill: NFS stopped, then the vLLM pod deleted (poller every 2 s)

| Event | Time (UTC) | After pod delete |
| --- | --- | --- |
| Last 200 | 17:03:20 | -1 s |
| First 000 | 17:03:22 | +1 s |
| Last 000 | 17:08:24 | 5 m 03 s |
| First 200 again | 17:08:26 | 5 m 05 s |

- User-visible outage: about 5 m 06 s, against 64 s when storage is healthy (drill: kill the pod).
- Pod stayed in `ContainerCreating` for 4 m 05 s with 0 restarts: no crash loop, no error, just a blocked mount. After NFS returned it loaded the weights in 58 s (Running 0/1 to 1/1).
- The host's hard NFS mount hung instead of failing: Ansible fact gathering timed out reading mount info for `/srv/models`.
- Cause of the block (kubelet log): volume setup for `models` stalled; 2 m 03 s after it started (17:03:21), the kubelet logged `unmounted volumes=[models] ... context deadline exceeded` (17:05:24). The hostPath type check on the hung NFS mount is the likely mechanism; the log does not name the call.
- Not tested in this run: whether a running pod keeps serving when NFS stops (the weights are in GPU memory, so it should).
- Detection gap: the kubelet logged the volume timeout, but no `FailedMount` event appeared on the pod, so `kubectl describe pod` showed nothing wrong. The evidence was only in the node's kubelet log.
## Drill: kubelet stopped on the GPU node (single GPU node)

| Event | Time (UTC) | Source |
| --- | --- | --- |
| Last kubelet heartbeat (kubelet stopped about here; the stop command was not timestamped) | 17:25:05 | node condition `LastHeartbeatTime` |
| Node Unknown, pod Ready=False, endpoint ready=false | 17:25:58 | node and pod conditions, `NodeNotReady` event |
| First 000 | 17:26:01 | poller |
| Restore command run | 17:28:32 | `date -u` |
| Node Ready=True | 17:28:34 | node condition |
| Brief 200, then 000 again | 17:28:38, 17:28:42 | poller |
| Pod Ready=True, stable 200 | 17:28:44 | pod condition, poller |

- Detection: the control plane marked the node Unknown and removed the pod from the Service 53 s after the last heartbeat.
- User-visible outage: 2 m 43 s (first 000 at 17:26:01 to stable 200 at 17:28:44). The pod's Ready condition was false for 2 m 46 s.
- Recovery after the restore command: 12 s to stable service, with no model reload, because the pod was never evicted or stopped.
- The container kept running the whole time. `kubectl get pods` showed `1/1 Running` throughout, because that column counts ready containers; the pod's Ready condition (which feeds endpoints) was False.
- `kubectl logs` failed with `connection refused` on the kubelet port: logs and exec depend on the kubelet.
- 9.47 probe errors in the 5 minutes before the restore.
- Eviction not reached: the node had the `unreachable:NoExecute` taint, the default toleration is 300 s, and I restored after 2 m 34 s. With one GPU node there is nowhere to reschedule.
- False recovery after the restore: a 200 at 17:28:38 and a 000 at 17:28:42 before the stable 200. Likely the restarted kubelet reset probe state and readiness dropped again until the probes passed (not verified; no probe-failure events were recorded).

## Load test, run 1 (k6, 1 > 2 > 8 > 16 VUs over 6 minutes, 64-token chat completions, through a port-forward)

- 2,542 requests, 0 failed. Request time: median 853 ms, p90 916 ms, p95 925 ms, max 956 ms (min 48.6 ms: some completions ended early).
- vLLM `waiting` was 0 in every 10 s sample; `running` peaked at 10 in the samples (limit `--max-num-seqs 16`).
- The server was not saturated at 16 VUs, so run 1 did not find the knee. Peak prometheus values: TODO (paste from the queries).

## Load test (k6, 64-token chat completions through a port-forward, `--max-num-seqs 16`)

| Run | Stages (VUs) | Requests | Failed | Request time p95 | Median / max | Avg throughput |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 > 2 > 8 > 16 over 6 min | 2,542 | 0 | 0.925 s | 0.85 s / 0.96 s | 7.0 req/s |
| 2 | 16 > 32 > 48 > 64 over 8 min | 8,126 | 0 | 3.14 s | 1.80 s / 3.5 s | 16.9 req/s |
| 3 | same stages as run 2, with empty-body logging | 8,112 | 0 | 3.12 s | 1.83 s / 3.54 s | 16.9 req/s |

- Run 1 did not saturate: `waiting` was 0 in every 10 s sample, `running` peaked at 10.
- Run 2: `running` hit the 16 cap and `waiting` first rose above 0 at about 21 VUs (start time inferred, plus or minus 2 VUs). Waiting grew about linearly to 46 at about 62 VUs and drained within 30 s of ramp-down.
- Saturation was compute and batch cap, not memory: KV cache peaked near 8%, GPU utilization about 100%, GPU memory flat.
- Queueing appeared as time-to-first-token (p95 plateau about 2.4 s on the dashboard against a 1 s target), not inter-token latency, which stayed flat.
- Probe availability stayed 100% throughout: probes count as ok within a 5 s budget, and the slowest request was 3.5 s. Latency broke the target while availability did not.
- Empty completions: 3 of 8,126 (run 2) and 2 of 8,112 (run 3). The logged body shows HTTP 200, empty content and finish_reason "stop": the model emitted its end-of-sequence token first. A model behavior, not a server error.
- k6 exited 99: the 2 s p95 threshold crossed by design.
- p95 first above 2 s at about TODO VUs (from the knee script). Tokens per second: TODO.
- Run 3 reproduced run 2 within about 1% (p95 3.12 s against 3.14 s, 16.87 against 16.91 req/s). Queueing again started at about 20 to 21 concurrent users (first `waiting` sample above 0 at about 1 m 40 s); the queue peaked at 43 waiting near 61 users.
- A queueing estimate (derived, not measured) explains the p95: about 43 waiting at about 19 requests per second is about 2.3 s of waiting, plus about 0.85 s of service, which matches 3.1 s. Time-to-first-token carries the delay; inter-token latency stays flat.
