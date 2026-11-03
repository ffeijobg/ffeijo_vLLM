# terraform/platform/alerts.tf
resource "kubernetes_manifest" "llm_slo_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata   = { name = "llm-slo", namespace = "monitoring", labels = { release = "kube-prometheus-stack" } }
    spec = {
      groups = [{
        name = "llm-slo"
        rules = [
          { record = "llm:probe_error_ratio:rate5m"
            expr   = "sum(rate(llm_probe_requests_total{result=\"error\"}[5m])) / sum(rate(llm_probe_requests_total[5m]))" },
          { record = "llm:probe_error_ratio:rate1h"
            expr   = "sum(rate(llm_probe_requests_total{result=\"error\"}[1h])) / sum(rate(llm_probe_requests_total[1h]))" },
          { alert  = "LLMErrorBudgetFastBurn"
            expr   = "llm:probe_error_ratio:rate1h > (14.4 * 0.005) and llm:probe_error_ratio:rate5m > (14.4 * 0.005)"
            for    = "2m"
            labels = { severity = "page" }
            annotations = { summary = "Burning the 28-day error budget 14x too fast (lab SLO 99.5%)" } },
          { alert  = "LLMProberStale"
            expr   = "time() - llm_probe_last_success_timestamp_seconds > 120"
            for    = "1m"
            labels = { severity = "warn" }
            annotations = { summary = "No successful probe for 2 minutes" } }
        ]
      }]
    }
  }
}
