# Incidents hit while building the lab

Each entry: what I saw, what caused it, how I found it, the fix, and what prevents a repeat.
Times are local (CST, UTC-6) unless marked UTC.

## 1. Stale alert never fired when the prober was gone

- **Symptom:** with the prober scaled to 0, no `LLMProberStale` alert appeared.
- **Cause:** the rule was `time() - llm_probe_last_success_timestamp_seconds > 120`. When the pod disappears, Prometheus marks its series stale and the expression has no input, so it returns no result and cannot fire.
- **How I found it:** I tested the alert on purpose. The earlier experiment (vLLM down, prober alive) had worked, which hid the gap.
- **Fix:** `or absent(llm_probe_last_success_timestamp_seconds)`, applied through Terraform (`-target` on the rules resource so the ArgoCD sync policy was not touched mid-test).
- **Result:** detection with the prober gone fell to 40 s (pending), and `LLMErrorBudgetFastBurn` stayed silent, as designed.
- **Prevention:** test every alert by breaking the thing it watches, including the monitor itself.

## 2. `VLLM_PORT` crash loop

- **Symptom:** the vLLM pod restarted after about 70 s of loading (exit code 1) and never became Ready. `describe` showed `Environment: <none>`.
- **Cause:** Kubernetes injects environment variables for every Service in the namespace. A Service named `vllm` produces `VLLM_PORT=tcp://...`, which vLLM reads as its own port setting. The startup log listed `VLLM_SERVICE_HOST`, `VLLM_PORT_8000_TCP` and similar as unknown variables.
- **How I found it:** the container log's warnings, not the pod description (service-link variables are not part of the pod spec).
- **Fix:** `enableServiceLinks: false` in the pod template.
- **Why it came back:** the setting lived in the old Deployment and was not carried over when it was replaced by a Rollout.
- **Prevention:** keep safeguards in a shared template, and diff old and new pod specs when migrating a workload.

## 3. Deployment and Service pruned by a manifest move

- **Time:** about 13:04. First start of the new pod: 13:04:04.
- **Symptom:** the Rollout reported `activeService: Invalid value: "vllm": service "vllm" not found`, and vLLM stopped serving.
- **Cause:** the `vllm` Service was defined inside `deployment.yaml`. A commit that replaced that file with a Rollout let `prune: true` delete the Deployment and its Service.
- **Fix:** a standalone `gitops/vllm/service.yaml`, keeping the `app: vllm` label and the `http` port name the ServiceMonitor selects on.
- **Related mistake:** the first Rollout still had `image: vllm/vllm-openai:<pinned-tag>` (a placeholder), giving `InvalidImageName`.
- **Prevention:** dry-run manifests before pushing (`kubectl apply --dry-run=server`), search for `<` placeholders, and give each Service its own file.
- **Outage:** roughly 20 minutes, from the prune to a healthy pod (first successful sync at 13:25:49).

## 4. ArgoCD would not apply the fix

- **Symptom:** the corrected manifest was in Git but the app stayed out of sync and the cluster kept the broken pod.
- **Cause:** the app has a `PostSync` gate hook, which runs only after every resource is Healthy. The release was unhealthy, so the sync operation never finished, and ArgoCD does not start a second sync while one is running. Automated sync also does not retry a failed sync of the same commit without a `retry` policy.
- **Fix:** terminate the stuck operation, push the fixed commit, and give the Applications `syncPolicy.retry` (limit 5, 5 s to 3 min backoff).
- **Verification:** deleting the `vllm` ServiceMonitor, which ArgoCD re-created within 20 s.
- **Trade-off to remember:** a PostSync gate gives an automatic check, but if a release breaks pod health the operation hangs instead of failing.

## 5. Error-ratio query had no data

- **Symptom:** the error-ratio rule returned nothing until the first failed probe.
- **Cause:** a Prometheus counter's label combination appears only after its first increment, so no `result="error"` series existed.
- **Fix:** create both label values at start (`REQS.labels("ok")` and `REQS.labels("error")`) in the prober, release as image `0.1.1`.
- **Prevention:** pre-create label values for counters that feed ratios.

## 6. Git push rejected, then rebase blocked

- **Symptom:** `main -> main (fetch first)`, then `divergent branches`, then `cannot pull with rebase: You have unstaged changes`.
- **Cause:** a README commit existed on GitHub that I did not have locally, and I had uncommitted files.
- **Also found:** a compiled `__pycache__` file was tracked, and my commits carried a placeholder author identity.
- **Fix:** set the git identity, amend the unpushed commit, stash the work in progress, untrack the cache file, `git pull --rebase && git push`.
- **Prevention:** commit finished work promptly, keep generated files in `.gitignore`, and chain `pull --rebase && push`.

## 7. Green pod could not start next to blue at 0.80

- **Symptom:** the new pod exited at startup: `Free memory on device cuda:0 (0.71/3.68 GiB) on startup is less than desired GPU memory utilization (0.8, 2.94 GiB)`.
- **Cause:** vLLM reserves its whole budget up front and refuses to start unless that much is free. Blue held about 2.9 GiB, so green saw 0.71 GiB.
- **Impact:** none for users. Blue kept serving and the Rollout stayed on the old revision.
- **Fix:** both versions use `--gpu-memory-utilization 0.40` (with `--max-model-len` reduced and `--max-num-seqs 16`). One pod then uses about 1.3 GiB and both together peaked at 2678 MiB of 4094 MiB.
- **Cost of the fix:** the running Rollout had to be deleted and recreated (about 2 minutes of planned outage), because blue could not be shrunk in place while green was starting.

## 8. Wrong model name stopped by the gate

- **Symptom:** green pod Ready, but the pre-promotion probe got `404` from `vllm-preview`.
- **Why `/health` missed it:** `/health` proves the engine is up, not that the right model name is served.
- **Result:** the first probe failed (`failureLimit: 0`), the Rollout aborted, and blue served throughout. Commit to abort was 4 m 38 s (3 m 35 s of that was the Git poll); ReplicaSet creation to abort was 63 s.
- **Recovery:** `git revert`. The Rollout reused the stable ReplicaSet and created no new pod.

## 9. Oversized context never became Ready

- **Symptom:** green crash-looped within seconds, 3 restarts in 102 s.
- **Cause:** `ValidationError: max_model_len (1000000) is greater than the derived max_model_len (max_position_embeddings=32768)`. It fails config validation before any GPU memory is allocated. vLLM offers `VLLM_ALLOW_LONG_MAX_MODEL_LEN` to override it, with a warning about NaN or out-of-bounds errors.
- **Result:** no AnalysisRun was created (the analysis starts only after Ready), blue stayed `1/1`, and I reverted before the 300 s progress deadline, so the deadline abort was not exercised.

## 10. Port-forward bound to a dead pod

- **Symptom:** `lost connection to pod ... failed to find sandbox`, and `curl localhost:8000` returned nothing even though blue was healthy.
- **Cause:** `kubectl port-forward svc/vllm` resolves one pod when it starts. When that pod is replaced, the forward dies.
- **Prevention:** judge availability from the prober's Prometheus series instead of a forward, and restart the forward after any rollout.

## 11. Probe errors during the rollout tests: explained

- **Measured:** 8 failed probes over 45 minutes and one burn-rate alert firing (20:12:57 to 20:19:27 UTC).
- **Cause:** all eight errors fell between 20:10:57 and 20:15:27, which is the planned delete and recreate of the Rollout for the memory-budget change. There were zero errors during the three release tests.
- **Mistake I made:** I first assumed the measurement window started after the planned outage. Checking when the errors happened, instead of trusting a total, showed they belonged to the planned outage.
- **Not verified:** why blue restarted twice during that recreate (the old pod's logs were gone). Likely GPU memory still being released by the terminating pod.

## 12. Pod refused after a host reboot (UnexpectedAdmissionError)

- **Symptom:** after the host restarted, the old vLLM pod showed `UnexpectedAdmissionError`; a replacement pod came up normally.
- **Cause (likely):** the kubelet re-admitted the pod before the NVIDIA device plugin had registered the GPU. Not verified from logs.
- **Fix:** the ReplicaSet created a replacement once the plugin was ready; I deleted the stale pod. Recovery to Ready was 3 m 33 s after boot.

## 13. Storage outage hid inside ContainerCreating

- **Symptom:** with the NFS server stopped, a restarted vLLM pod sat in `ContainerCreating` for about 4 minutes with 0 restarts and no FailedMount event; the endpoint was down for about 5 minutes.
- **Evidence:** the node's kubelet log showed `unmounted volumes=[models] ... context deadline exceeded` 2 m 03 s after volume setup began.
- **Lesson:** a hung dependency is quiet. A "pod pending too long" alert would catch it; restart-count alerts would not.
- **Prevention:** keep model weights on node-local disk or copy them at pod start, and keep a spare replica.

## Evidence commands for the interview stories (verified 2026-11-15)

- **VLLM_PORT:** a throwaway pod in `inference` gets 16 `VLLM_*` variables from the `vllm` and `vllm-preview` Services, including `VLLM_PORT=tcp://10.96.120.194:8000`. With `enableServiceLinks: false` it gets none (check the empty output; the exit code is the last command in the pipe, so it proves nothing). The Rollout template sets `enableServiceLinks: false`.
  - History (`git log -S enableServiceLinks -- gitops/vllm`): `f79221a` original fix, `991a034` lost in the move to blue-green, `d37f046` restored.
  - Whether vLLM parses `VLLM_PORT` as its own setting is inferred from the crash log, not shown directly.
- **NVML / cgroups:** the host `/etc/nvidia-container-runtime/config.toml` has `#no-cgroups = false` (commented, default false). Docker uses the systemd cgroup driver on cgroup v2. `nvidia-smi -L` works inside `gpu-lab-worker`. Where `no-cgroups=true` was set, and the exact error text, are in my own notes (not re-verified here).
- **GPU Operator operands:** every kind node shows `feature.node.kubernetes.io/pci-10de.present=true`, because the nodes are containers on one host. Terraform (`kubernetes_labels.cpu_workers_no_gpu_operands`) sets `nvidia.com/gpu.deploy.operands=false` on the two CPU workers, so operand pods run only on `gpu-lab-worker`. The control plane keeps the default deploy labels (true) but runs no operand pods; its taint is the likely reason (not verified).
