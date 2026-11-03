# terraform/platform/gpu-operator.tf
variable "gpu_operator_version" { type = string }   # pin: helm search repo nvidia/gpu-operator --versions

resource "kubernetes_namespace" "gpu_operator" {
  metadata {
    name   = "gpu-operator"
    labels = { "pod-security.kubernetes.io/enforce" = "privileged" }
  }
}

# Every kind node runs on the same host, so Node Feature Discovery sees the NVIDIA PCI device on all of them and
# the Operator would start its GPU daemonsets on the CPU workers too, where they wait forever for a GPU.
# This documented label turns all operands off on those nodes.
variable "cpu_worker_nodes" {
  type    = list(string)
  default = ["gpu-lab-worker2", "gpu-lab-worker3"]   # match the node names from step 2.2
}

resource "kubernetes_labels" "cpu_workers_no_gpu_operands" {
  for_each    = toset(var.cpu_worker_nodes)
  api_version = "v1"
  kind        = "Node"
  metadata { name = each.key }
  labels      = { "nvidia.com/gpu.deploy.operands" = "false" }
  force       = true   # take over the label if you already set it by hand with kubectl
}

resource "helm_release" "gpu_operator" {
  depends_on = [kubernetes_labels.cpu_workers_no_gpu_operands]
  name       = "gpu-operator"
  namespace  = kubernetes_namespace.gpu_operator.metadata[0].name
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.gpu_operator_version
  wait       = true
  timeout    = 600

  values = [yamlencode({
    cdi          = { enabled = true }
    driver       = { enabled = false }   # the host owns the driver
    toolkit      = { enabled = false }   # Ansible and nvkind own the runtime
    operator     = { runtimeClass = "nvidia" }
    dcgmExporter = { serviceMonitor = { enabled = true } }
  })]
}
