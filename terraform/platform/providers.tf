# terraform/platform/providers.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.27" }
  }
}

variable "kubeconfig_path" { default = "~/.kube/gpu-lab-config" }

provider "kubernetes" { config_path = pathexpand(var.kubeconfig_path) }
provider "helm" {
  kubernetes { config_path = pathexpand(var.kubeconfig_path) }
}
