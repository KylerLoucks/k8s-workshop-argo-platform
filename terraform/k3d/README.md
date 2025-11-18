# Terraform stack: k3d + Argo CD

This stack assumes you already created the `k3d-dev` and `k3d-prod` clusters yourself
(`k3d cluster create ...`). Terraform simply installs Argo CD into the dev cluster, creates the
service-account token in prod, and registers prod with Argo CD.

## What it does
- Assumes `k3d-dev` and `k3d-prod` contexts already exist in `~/.kube/config`.
- Installs the official Argo CD Helm chart (v9.1.1) into `k3d-dev`, namespace `argocd`.
- Creates a service account + token in the prod cluster so Argo CD can talk to it.
- Registers the prod cluster (`https://host.k3d.internal:6551`) with Argo CD.

## Requirements
- Terraform >= 1.2
- k3d, kubectl, and Helm installed locally (see project README for brew commands)
- Access to `~/.kube/config` with the `k3d-dev` context (created automatically after apply)
- Set `TF_VAR_argocd_admin_password` (or provide `argocd_admin_password` via another method)
  so Terraform can log in to Argo CD after the Helm release is up. The initial password comes
  from `kubectl --context k3d-dev -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -D`.

## Usage
1. **Create / refresh the clusters manually**
   ```bash
   # dev cluster (no special flags needed)
   k3d cluster create dev --wait

   # prod cluster with API exposed on host + SAN for host.k3d.internal
   k3d cluster create prod \
     --api-port 127.0.0.1:6551 \
     --k3s-arg "--tls-san=host.k3d.internal@server:0" \
     --wait
   ```
   Verify contexts:
   ```bash
   kubectl config get-contexts | grep k3d-
   ```

   Test API connectivity from inside the dev cluster (what Argo CD will do):
   ```bash
   # DNS lookup
   kubectl --context k3d-dev run -n argocd dns-debug \
     --rm -it --image=busybox --restart=Never -- \
     nslookup host.k3d.internal

   # HTTPS probe (expect 400/401 which proves the API is reachable)
   kubectl --context k3d-dev run -n argocd dns-debug \
     --rm -it --image=busybox --restart=Never -- \
     wget -qO- host.k3d.internal:6551/version || true
   ```

   Optional host-side check (uses the loopback binding you exposed):
   ```bash
   curl -k https://127.0.0.1:6551/version   # expect HTTP 401
   ```

2. **Run Terraform**
```bash
cd terraform/k3d
terraform init
terraform apply -auto-approve
```

After apply, you will get an error saying you can't connect to ArgoCD.
```bash
│ Error: failed to create new session client
│ 
│   with module.argocd.argocd_application.app_of_apps["management"],
│   on ../modules/argocd/main.tf line 97, in resource "argocd_application" "app_of_apps":
│   97: resource "argocd_application" "app_of_apps" {
│ 
│ dial tcp [::1]:8080: connect: connection refused
```

You need to port forward the UI and run terraform apply again. You can port-forward the UI the usual way:
```bash
kubectl --context k3d-dev -n argocd port-forward svc/argo-cd-argocd-server 8080:80
```

## Outputs
- `k3d_kube_contexts`: the dev/prod contexts Terraform expects.
- `argocd_release`: Helm release metadata (version, namespace, etc.)
