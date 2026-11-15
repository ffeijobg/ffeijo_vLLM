# Cheat sheet (lab values)

## Debug method
symptom > scope > recent change > layer > mitigate > root cause

## Commands
kubectl describe pod / get events --sort-by=.lastTimestamp / logs --previous
kubectl get endpointslices; pod conditions: -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
node kubelet (kind): docker exec <node> journalctl -u kubelet --since "HH:MM" | grep -iE 'volume|mount'
host: sudo dmesg -T | grep -iE 'oom|xid|nfs'; ss -tlnp; dig @<kube-dns IP>
GPU: nvidia-smi -L; docker exec gpu-lab-worker nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
rollouts: kubectl argo rollouts get rollout <n> -n <ns> -w; promote | abort | retry | undo
ArgoCD stuck sync: patch status.operationState.phase=Terminating, then annotate argocd.argoproj.io/refresh=hard

## Metric names
vllm:time_to_first_token_seconds  vllm:inter_token_latency_seconds  vllm:num_requests_running  vllm:num_requests_waiting
vllm:kv_cache_usage_perc  vllm:num_preemptions_total  DCGM_FI_DEV_FB_USED  DCGM_FI_DEV_FB_FREE  DCGM_FI_DEV_GPU_UTIL
llm_probe_requests_total{result}  llm_probe_duration_seconds  llm_probe_ttft_seconds  llm_probe_last_success_timestamp_seconds

## Numbers
cold start about 70 s | pod kill 64 s outage | NFS down then restart 5 m 05 s | kubelet stopped: Ready false after 53 s, outage 2 m 43 s
bad release: gate fails 63 s after green appears, 0 errors | alerts: stale 2 m 16 s (vLLM down), 40 s (prober gone); burn-rate pending 4 m 46 s
load: queueing from about 18 to 20 users, TTFT p95 above 1 s at about 36 users, about 19 req/s and 1,080 tokens/s at saturation
GPU: 0.40 budget about 1.3 GiB per pod, two pods peak 2678 of 4094 MiB | SLO 99.5% / 28 d = about 201 min, fast burn 14.4x = 7.2%

## One-liners
Ready is not serving correctly. Test the alert by breaking the thing it watches. Revert in Git, do not undo in the cluster.
Lab project, not production. I have not run inference in production; here is what I built.
