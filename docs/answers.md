# Spoken answers (lab values; say "lab project" every time)

## 1. Two-minute walkthrough (about 260 words)
I built a lab project on one machine: a four-node kind cluster with one 4 GB NVIDIA GPU. Ansible configures the host, Terraform installs the platform, and ArgoCD deploys the workload from Git. I serve a small model with vLLM and measure it from outside with a Python prober, plus vLLM and DCGM metrics.
I defined five SLIs with a lab target of 99.5 percent availability over 28 days, and two alerts. I tested them by breaking things. When I killed the prober, my stale alert never fired, because a missing metric returns no result; I fixed it with absent().
For releases I use blue-green with an Argo Rollouts analysis that sends a real request to the new pod before traffic moves. A release with the wrong model name passed the health check but failed the gate 63 seconds after the new pod appeared, with zero errors for users. Because the GPU is small, both versions had to fit, so I measured the memory budget: 0.40 each, peaking at 2.7 of 4 GB.
I also failed it on purpose. Killing the pod was 64 seconds of downtime. With the NFS server down it was five minutes, and Kubernetes showed no error, only a stuck ContainerCreating. Stopping the kubelet left the container running, but traffic stopped after 53 seconds. A load test showed the single replica saturates around 20 concurrent users: requests queue, time to first token triples, and availability still reads 100 percent.
This is a lab, not production, and I have not run inference in production, but it showed me where inference differs from an ordinary service.

## 2. Debugging story (NFS outage), six steps
- Symptom: after a pod restart the endpoint answered nothing for 5 minutes.
- Scope: only the new vLLM pod, in ContainerCreating, zero restarts, no events.
- Recent change: I had stopped the NFS server.
- Layer: storage. The kubelet log on the node showed the models volume timing out after about 2 minutes.
- Mitigate: restore the NFS server; nothing in Kubernetes could fix it.
- Root cause and prevention: one replica and weights on a single NFS host. Keep weights on node-local disk or copy them at start, add a spare replica, and alert on pods pending too long.

## 3. Rollout design for a model deployment
1. Why it differs: a model server takes about a minute to load and needs the whole GPU budget, so a bad release costs capacity and time.
2. Pattern: blue-green, so the new version loads beside the old one and is tested before traffic moves.
3. Gate: a real request, judged on the answer and the time, not just a health check.
4. Rollback: a failed analysis aborts automatically; the durable fix is git revert.
5. Limits: in the lab both versions share one GPU with no memory isolation; in production I would use a separate node pool.

## 4. SLIs and error budget
- Five SLIs: probe availability, p95 time to first token, p95 inter-token latency, queue depth, GPU memory.
- Lab target 99.5 percent over 28 days: 0.5 percent of 40,320 minutes is about 201 minutes.
- Burn rate: 14.4 times is a 7.2 percent error ratio; the alert needs both the 1-hour and 5-minute windows, so one short blip does not page.
- A second alert fires when the prober itself goes quiet, because a ratio with no data fires nothing.
- If more than half the budget is spent, freeze risky releases.

## 5. Honest gap
"I haven't run inference in production. Here is what I built in my lab and what I learned from breaking it."
