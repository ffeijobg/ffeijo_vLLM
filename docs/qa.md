# Practice questions (lab values; answer aloud, under 90 seconds each)

## 1. A GPU pod stays Pending. What do you check?
- `kubectl describe pod`: the scheduler event says what is missing ("Insufficient nvidia.com/gpu" or "untolerated taint").
- Node allocatable `nvidia.com/gpu` and the node's taints. My GPU node is tainted, so a GPU pod needs a toleration and a node selector.
- The device plugin pod and its logs; the `nvidia` RuntimeClass.
- Lab detail: with time-slicing the node advertises 2 slots on 1 physical GPU, so scheduling can succeed while memory is still shared and unisolated.

## 2. Why Ansible and Terraform both?
- Ansible for the mutable host (driver check, container toolkit, NFS mount, fault injection); Terraform for the platform (plan and diff, state, dependency graph); ArgoCD for workloads from Git.
- Rule: no object has two owners, otherwise ArgoCD shows permanent drift.
- Lab detail: Terraform needs a kubeconfig at plan time, so it runs in two stages, and I used `-target` to change alert rules without touching sync policy mid-test.

## 3. How do you share a GPU between workloads?
- Time-slicing: scheduling slots, no memory or fault isolation (I enabled it: 2 slots on one GPU).
- MPS: processes run on the GPU at once, better utilization, still weak isolation.
- MIG: hardware partitions with isolated memory; only on supported data-center GPUs, not on my Ada card.
- Lab detail: with no isolation I budgeted memory by hand, 0.40 per vLLM pod.

## 4. Pod Ready but users see errors. Why?
- `/health` proves the engine process is up. It did not catch a release with the wrong model name; my real-request gate got a 404.
- Ready is the control plane's view: with the kubelet stopped, the container ran, but the pod's Ready condition went False after 53 s and traffic stopped.
- It also does not prove latency (load test) or that weights can be reloaded (NFS drill).

## 5. What would you alert on?
- Burn rate on availability with two windows (1 h and 5 min) so a short blip does not page.
- A stale-prober alert, because a ratio with no data fires nothing (my first version missed a dead prober until I added `absent()`).
- Queue depth for early warning: in the load test it rose before first-token latency broke its target (an alert on it is not implemented).
- A "pod pending too long" alert: the NFS outage had zero restarts and no events.

## 6. Model restart is slow. How do you improve it?
- My cold start is about 70 s, dominated by loading weights; with NFS down it was five minutes.
- Options: weights on node-local disk, a warm spare replica, a long startup probe so it is not killed while loading, image preloaded on the node.
- I have read that NVIDIA Snapshot restores checkpointed replicas in seconds; I have not used it.

## 7. How do you roll back a bad release?
- Blue-green with a pre-promotion analysis: a failed analysis aborts automatically and the old version never stopped serving.
- Durable rollback is `git revert`; the Rollout reused the stable ReplicaSet, no new pod.
- `undo` in the cluster fights ArgoCD self-heal.
- Caveat: a PostSync hook can freeze auto-heal if the release is unhealthy; terminate the operation and add a retry policy.

## 8. Your cluster has a single GPU. What are the risks?
- A restart is 64 s of downtime; losing the node meant 2 m 43 s, and the pod would be evicted after 300 s with nowhere to reschedule.
- No side-by-side canary at full memory, which is why both versions share the card at 0.40 each, with no isolation.
- Fix in production: more than one GPU node, a spare, node health detection and replacement.

## 9. How did you find out your alert did not work?
- I tested it by stopping the prober: no alert fired, because the metric vanished and the expression returned no result. I added `or absent(...)` and re-ran the test: pending after 40 s.

## 10. Why kind, and what does it not tell you?
- Real scheduling and kubelet behavior on one box, cheap to rebuild.
- It does not give separate machines, real network partitions, hardware faults, or in-place upgrades; all nodes share one kernel and one GPU.
