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
