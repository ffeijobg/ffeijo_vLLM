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

      # new: tolerate the selector the Rollouts controller writes onto the Service
      ignoreDifferences = [
        { kind = "Service", jsonPointers = ["/spec/selector"] }
      ]

      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true", "RespectIgnoreDifferences=true"]   # new option added here
        retry       = { limit = 5, backoff = { duration = "5s", factor = 2, maxDuration = "3m" } }
      }

    }
  }
}

resource "kubernetes_manifest" "prober_app" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "llm-prober", namespace = "argocd" }
    spec = {
      project = "default"
      source = { repoURL = var.gitops_repo, targetRevision = "main", path = "gitops/prober" }
      destination = { server = "https://kubernetes.default.svc", namespace = "inference" }
      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}

resource "kubernetes_manifest" "rollouts_demo_app" {
  depends_on = [helm_release.argocd, helm_release.argo_rollouts]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "rollouts-demo", namespace = "argocd" }
    spec = {
      project     = "default"
      source      = { repoURL = var.gitops_repo, targetRevision = "main", path = "gitops/rollouts-demo" }
      destination = { server = "https://kubernetes.default.svc", namespace = "rollouts-demo" }
      ignoreDifferences = [
        { kind = "Service", jsonPointers = ["/spec/selector"] }
      ]
      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true", "RespectIgnoreDifferences=true"]
        retry       = { limit = 5, backoff = { duration = "5s", factor = 2, maxDuration = "3m" } }
      }
    }
  }
}
