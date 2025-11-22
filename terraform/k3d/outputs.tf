output "k3d_kube_contexts" {
  description = "Expected kubeconfig contexts"
  value = {
    management  = "k3d-management"
    prod = "k3d-prod"
  }
}

output "argocd_release" {
  description = "Helm release metadata for Argo CD"
  value       = module.argocd.argocd.name
}
