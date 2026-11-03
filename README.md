# ffeijo_vLLM

A single-machine GPU Kubernetes lab that serves an LLM with **vLLM**, built so that every layer is reproducible from code: **Ansible owns the host, Terraform owns the cluster platform, ArgoCD owns the workload.**

It runs a multi-node [kind](https://kind.sigs.k8s.io/) cluster on one Docker host with an NVIDIA GPU, serves a small model (`Qwen/Qwen2.5-0.5B`) with vLLM through ArgoCD, and measures it with a Python prober, Prometheus, an error-budget alert and a Grafana dashboard. It was built and tested on a 4 GB RTX A400, so everything here also works on larger cards.

The step-by-step build, with commands, expected output and the problems met along the way, is in [`Plan.md`](Plan.md). This README is the short version.

## Architecture

```text
Docker host (Debian, one NVIDIA GPU)                          <- Ansible
 |- Docker + NVIDIA Container Toolkit (nvidia default runtime, CDI)
 |- /srv/models   NFS-mounted model weights, passed read-only to the GPU node
 '- kind cluster "gpu-lab"                                     <- Terraform stage 1 (nvkind)
     |- control-plane
     |- worker  (GPU)   workload=inference, taint nvidia.com/gpu  -> vLLM, device plugin, DCGM exporter
     |- worker2 (CPU)   workload=apps                              -> three-tier demo app, prober
     '- worker3 (CPU)   workload=apps
   platform (Terraform stage 2): kube-prometheus-stack, ArgoCD, NVIDIA GPU Operator, alert rules
   workloads (ArgoCD, from Git):  vLLM, prober, ServiceMonitors, Grafana dashboard
```

| Layer | Tool | Owns |
| --- | --- | --- |
| Host | Ansible | Kernel settings, container toolkit and runtime config, kind/kubectl/helm/nvkind, NFS mount, model download |
| Cluster | Terraform stage 1 | The kind cluster and its node layout (through `nvkind`, which gives the GPU node its NVIDIA runtime) |
| Platform | Terraform stage 2 | Prometheus stack, ArgoCD, GPU Operator, alert rules, the ArgoCD Applications |
| Workloads | ArgoCD (from this repo) | vLLM, the prober, ServiceMonitors, the dashboard |

No object has two owners. The three-tier demo app is deliberately applied by hand, outside ArgoCD, so self-heal does not undo faults injected into it.

## Repository layout

| Path | What it holds |
| --- | --- |
| `ansible.cfg`, `ansible/` | Inventory, `group_vars`, playbooks (`01-host.yml`, `02-models.yml`, fault playbooks in `chaos/`) and roles |
| `cluster/` | `kind-config.yaml.tpl`, the node layout template rendered by Terraform |
| `terraform/cluster/` | Stage 1: creates the kind cluster |
| `terraform/platform/` | Stage 2: Helm releases, ArgoCD Applications, alert rules; chart versions in `terraform.tfvars` |
| `gitops/vllm/` | What ArgoCD deploys for vLLM: Deployment, Service, ServiceMonitor, dashboard ConfigMap |
| `gitops/prober/` | What ArgoCD deploys for the prober: Deployment, Service, ServiceMonitor |
| `prober/` | The Python prober (probe, Prometheus metrics, exit code for gating), its `requirements.txt` and `Dockerfile` |
| `apps/` | The three-tier demo app (see below) |
| `scripts/` | `bootstrap.sh` (stages in order) and `make-dashboard.py` (generates the Grafana dashboard ConfigMap) |
| `drills/` | A small optional Python exercise (retry decorator with a check script) |
| `Plan.md` | The full runbook: steps, checks, tested versions, known problems, how to undo and rerun |

## Reuse of the three-tier scaling project

Two parts come from my earlier project, [ffeijo_3tier_scaling_stack](https://github.com/ffeijobg/ffeijo_3tier_scaling_stack):

- **The demo workload (`apps/`).** Its `manifests/` folder (nginx frontend, FastAPI backend with its source and Dockerfile, PostgreSQL behind PgBouncer, HPAs and PDBs) is copied here as the application that runs on the two CPU workers. It is the target for node and storage fault drills, and the `workload=apps` / `workload=inference` split keeps it off the GPU node. Its `networking/` manifests are not applied, because kind's default CNI does not enforce NetworkPolicy.
- **Ansible roles.** `common`, `docker` and `kind` are reused as they are (kernel parameters and inotify limits, Docker, and kind/kubectl/helm installs). The `docker` role is **opt-in** here (`never` tag), so a host that already has a working Docker is not touched.

New in this project: the `nvidia` and `tools` roles, the GPU-aware cluster (`nvkind` instead of a plain kind provider), the Terraform platform stage, the GPU Operator, vLLM, the prober, the alert rules and the dashboard. Everything that is not a copy of the three-tier project lives under the other folders above.

## What works today

Run end to end on the reference machine, with the checks and outputs recorded in `Plan.md`:

- Host layer: container toolkit and runtime settings, tools, NFS-backed model storage.
- Cluster: four kind nodes, the GPU visible inside the GPU node and schedulable through the device plugin (smoke test passes).
- Platform: Prometheus and Grafana, ArgoCD, GPU Operator (driver and toolkit disabled, operands only on the GPU node), DCGM GPU metrics in Prometheus.
- vLLM `v0.33.0` serving `Qwen/Qwen2.5-0.5B` through ArgoCD; cold start about 71 s; about 0.11 s end-to-end and 20 to 30 ms to the first token for a short answer.
- A prober that sends real completions and exports `llm_probe_*` metrics, scraped alongside vLLM's own `/metrics`.
- Five SLIs checked against real metric names, a burn-rate alert with a stale-prober guard, and a Grafana dashboard stored as a ConfigMap.

Not included yet: a gated rollout with Argo Rollouts, inference failure drills, and the closing interview material. They are outlined in `Plan.md` and left out until they have been run.

## Design decisions worth knowing

- **Two Terraform stages.** The Kubernetes and Helm providers need a kubeconfig at plan time, which only exists after the cluster does. The platform stage also applies the Helm charts first (`-target`) so CRDs exist before objects that use them are planned.
- **`nvkind` for the GPU node.** A GPU node needs its containerd configured for the NVIDIA runtime; `nvkind` does that and is wrapped in a `terraform_data` resource.
- **Sized for a 4 GB GPU.** One vLLM replica, a 0.5B model, `Recreate` instead of GPU sharing, and a memory budget taken from the measured free memory (about 3.7 GiB).
- **Measure from outside.** vLLM exports no failed-request counter, so availability and the error budget come from the prober.
- **GitOps boundaries.** ArgoCD applications use `prune` and `selfHeal`, so one-off test objects are kept out of the directories ArgoCD watches.

## Using it

1. Read `Plan.md`, "About this document" and Appendix A (order of work, rerun guide, tested versions).
2. Put your own values in `ansible/group_vars/all.yml` and `terraform/platform/terraform.tfvars` (host address, NFS export, tool and chart versions, the Git URL ArgoCD should watch).
3. Follow the steps in order; each has a **Verify** check, so you can stop or resume at any step.

`scripts/bootstrap.sh` strings the stages together, but the steps in `Plan.md` are the tested path.

## Tested environment and limits

- One Debian 12 server, 8 CPUs, 31 GiB RAM, one NVIDIA RTX A400 (4 GB), driver 580.126.18, Docker from the distribution, kind 0.33.0 (Kubernetes 1.34).
- kind runs every node as a container on one host: one kernel, one disk, one GPU. That is enough to learn and test the platform, but it does not model real node failure, network partitions or in-place upgrades.
- This is a lab, not a production design: no authentication in front of vLLM, no high availability, local Terraform state.
