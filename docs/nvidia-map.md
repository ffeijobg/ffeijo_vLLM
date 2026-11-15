# NVIDIA technology map

| Technology | One sentence | My status |
| --- | --- | --- |
| Driver and CUDA | Kernel driver and compute runtime that make the GPU usable | Hands-on (host) |
| Container Toolkit, CDI | Lets container runtimes expose GPUs to containers | Hands-on (Ansible) |
| GPU Operator, device plugin | Automates the Kubernetes GPU stack and advertises `nvidia.com/gpu` | Hands-on (driver and toolkit disabled; time-slicing on) |
| DCGM and its exporter | GPU telemetry as Prometheus metrics | Hands-on (FB_USED and GPU_TEMP exposed; no XID or power metrics in my exporter) |
| Time-slicing, MPS, MIG | Three ways to share a GPU, with different isolation | Time-slicing hands-on; MPS and MIG conceptual (no MIG on Ada) |
| vLLM | Open-source LLM inference server with an OpenAI-compatible API | Hands-on |
| NVKind | NVIDIA's tool for GPU-aware kind clusters (gives a node a whole GPU) | Hands-on |
| NCCL | Library for fast GPU-to-GPU communication; used for multi-GPU training and sharded inference | Conceptual (single GPU here) |
| NVIDIA Dynamo | NVIDIA's framework for distributed, multi-node LLM inference serving | Conceptual |
| Base Command Manager | Cluster provisioning and management for GPU fleets | Conceptual |
| NVKE | Open-source preview system for creating and operating Kubernetes clusters on bare-metal GPU fleets (kubeadm, Cluster API, NICo); not for production in this preview | Conceptual |
| NVKR, AICR | NVKR builds pinned, signed node images; AICR supplies validated GPU runtime components | Conceptual |
| NVSentinel | Detects GPU faults on a node and asks NVKE to remediate | Conceptual |
| NVIDIA Snapshot | Restores checkpointed inference replicas in seconds without a model reload | Conceptual |

Rule: do not claim hands-on for anything marked conceptual. "I read about it, and here is how it relates to what I built" is stronger than a bluff.
