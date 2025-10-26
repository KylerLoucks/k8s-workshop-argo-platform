# Terraform: k3d clusters (dev, prod)

Minimal Terraform setup that uses local-exec to create/delete k3d clusters.
Useful for demos; for local dev, a Makefile or shell script is often simpler.

## Requirements
- Terraform >= 1.3
- k3d installed and on PATH

## Usage
```bash
cd terraform/k3d
terraform init
terraform apply -auto-approve
```

You should see contexts:
```bash
kubectl config get-contexts | grep k3d-
```

Customize via variables:
```bash
# change names, expose LB ports 80/443 on host
terraform apply \
  -var='cluster_names=["dev","prod"]' \
  -var='expose_lb=true'
```

Destroy:
```bash
terraform destroy -auto-approve
```

## Notes
- Uses `null_resource` with `local-exec` to call k3d.
- Skips creation if kubeconfig exists for the cluster.
- For real infra, use managed Kubernetes (EKS/GKE/AKS) modules instead.
