# Pod Ready is not the same as model serving correctly

## 1. What `/health` proves, and what it does not
- It proves the engine process is up and answering its health route.
- It did not prove the right model was served: a release with the wrong served model name was Ready, and only the real-request probe caught it (404, aborted 4 m 38 s after the commit).
- It does not prove latency is acceptable (load-test knee: TODO, step 6.8).
- It does not prove the weights can be reloaded: with NFS stopped, a restarted pod sat in `ContainerCreating` for about 4 minutes and the outage lasted 5 m 05 s.
- Ready is the control plane's view, not the process's: with the kubelet stopped, the container kept running, but the pod's Ready condition went False after 53 s, the endpoint was removed, and users saw 2 m 43 s of failures while `kubectl get pods` still showed `1/1 Running`.

## 2. What the gate and the prober add
- They send a real request through the Service and judge the answer (non-empty completion for the right model name) and the time (5 s budget).
- The pre-promotion analysis runs before traffic moves, so a wrong release never reached users; the continuous prober measures what users feel after.
- Detection numbers: stale alert about 2 to 4 minutes, burn-rate alert about 5 to 7 minutes, bad release gate 63 s after the green pod appeared.

## 3. Why readiness does not do a real completion
- It spends GPU time on every probe, on a shared 4 GB card where the budget is tight.
- Under load a busy but healthy server can be slow to answer, so readiness would remove it from the Service and push more load onto the rest.
- The usual design: a cheap readiness check, plus an external prober and a pre-promotion gate for the deeper check.

## 4. What I would add in production
- A canary prompt with a known-good answer and a quality check, not only "non-empty".
- A "pod pending too long" alert (the NFS block had zero restarts and no event).
- Weights on node-local disk, a second replica or warm spare, and per-model dashboards.
- Node health detection and replacement (at fleet scale, NVSentinel flags the node and NVKE replaces it; I restored it by hand).

## One-line version
"Ready means the control plane thinks the pod can take traffic. It does not mean the model answers correctly, fast, or reloads after a restart. I test that with a real request before and after traffic moves."
