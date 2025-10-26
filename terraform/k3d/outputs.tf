output "kube_contexts" {
  description = "kubeconfig contexts for created clusters"
  value       = [for n in var.cluster_names : "k3d-${n}"]
}
