# terraform/cluster/variables.tf
variable "cluster_name"       { default = "gpu-lab" }
variable "kubernetes_version" { default = "v1.34.0" }   # must match an image your kind release publishes
variable "cpu_worker_count"   { default = 2 }
variable "models_dir"         { default = "/srv/models" }
variable "kubeconfig_path"    { default = "~/.kube/gpu-lab-config" }
