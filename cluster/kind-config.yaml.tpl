# cluster/kind-config.yaml.tpl
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: ${node_image}
{{- range $gpu := until numGPUs }}
- role: worker
  image: ${node_image}
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "workload=inference"
      taints:
      - key: nvidia.com/gpu
        value: present
        effect: NoSchedule
  extraMounts:
  - hostPath: /dev/null                                   # request GPU 0 for this node container
    containerPath: /var/run/nvidia-container-devices/{{ $gpu }}
  - hostPath: ${models_dir}                               # model weights, read-only
    containerPath: /models
    readOnly: true
{{- end }}
%{ for i in range(cpu_workers) ~}
- role: worker
  image: ${node_image}
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "workload=apps"
%{ endfor ~}
