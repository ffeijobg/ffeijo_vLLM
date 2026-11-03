# terraform/cluster/main.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}

locals {
  rendered = templatefile("${path.module}/../../cluster/kind-config.yaml.tpl", {
    node_image  = "kindest/node:${var.kubernetes_version}"
    cpu_workers = var.cpu_worker_count
    models_dir  = var.models_dir
  })
  kubeconfig = pathexpand(var.kubeconfig_path)
}

resource "local_file" "kind_template" {
  content  = local.rendered
  filename = "${path.module}/.generated/kind-config.yaml.tpl"
}

resource "terraform_data" "cluster" {
  input            = { name = var.cluster_name }
  triggers_replace = [sha256(local.rendered)]

  provisioner "local-exec" {
    command = <<-EOT
      nvkind cluster create --name=${var.cluster_name} --config-template=${local_file.kind_template.filename}
      kind get kubeconfig --name ${var.cluster_name} > ${local.kubeconfig}
      chmod 600 ${local.kubeconfig}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kind delete cluster --name ${self.input.name}"
  }
}

output "kubeconfig_path" { value = local.kubeconfig }
