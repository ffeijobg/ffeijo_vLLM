# terraform/platform/prometheus.tf
variable "kube_prometheus_stack_version" { type = string }   # pin: helm search repo prometheus-community/kube-prometheus-stack --versions

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_version
  timeout          = 900

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        retention                               = "3d"
        serviceMonitorSelectorNilUsesHelmValues = false   # pick up ServiceMonitors from every namespace
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false   # and PrometheusRules
      }
    }
    # kind binds these control-plane endpoints to localhost, so scraping them only creates noise
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }
  })]
}
