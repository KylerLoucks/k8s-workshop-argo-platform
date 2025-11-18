output "k3d_kube_contexts" {
  description = "Expected kubeconfig contexts"
  value = {
    dev  = "k3d-dev"
    prod = "k3d-prod"
  }
}

output "argocd_release" {
  description = "Helm release metadata for Argo CD"
  value       = module.argocd.argocd.name
}
