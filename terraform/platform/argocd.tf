# terraform/platform/argocd.tf
variable "argocd_chart_version" { type = string }
variable "gitops_repo"         { type = string }   # a Git URL the cluster can reach

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
}

resource "kubernetes_manifest" "vllm_app" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "vllm", namespace = "argocd" }
    spec = {
      project = "default"
      source = { repoURL = var.gitops_repo, targetRevision = "main", path = "gitops/vllm" }
      destination = { server = "https://kubernetes.default.svc", namespace = "inference" }
      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}
