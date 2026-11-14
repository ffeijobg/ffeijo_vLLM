# terraform/platform/rollouts.tf
variable "argo_rollouts_chart_version" { type = string }   # pin: helm search repo argo/argo-rollouts --versions

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = var.argo_rollouts_chart_version
  values           = [yamlencode({ dashboard = { enabled = true } })]
}
