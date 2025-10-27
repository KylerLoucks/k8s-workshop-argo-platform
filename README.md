# k8s-workshop-argo-platform

## Prerequisites

Install via Homebrew (macOS):
```bash
brew install k3d kubectl helm
```

Verify versions:
```bash
k3d version
kubectl version --client
helm version
```

## Setup k3d (first time)
```bash
# Create dev/prod clusters
k3d cluster create dev --wait
k3d cluster create prod --wait

# List contexts
kubectl config get-contexts | grep k3d-
```

## Quick start: install web-ui with Helm
```bash
# Install into dev cluster, namespace web
helm upgrade --install web-ui charts/web-ui \
  --kube-context k3d-dev \
  --namespace web \
  --create-namespace

# Access locally
kubectl --context k3d-dev -n web port-forward svc/web-ui 8081:80 &
curl -I http://localhost:8081/
```

### (Optional) Enable ingress
```bash
# Recreate dev cluster with LB ports mapped to host 80/443
k3d cluster delete dev || true
k3d cluster create dev -p "80:80@loadbalancer" -p "443:443@loadbalancer" --wait

# Install with ingress enabled (adjust host as needed)
helm upgrade --install web-ui charts/web-ui \
  --kube-context k3d-dev \
  --namespace web \
  --create-namespace \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=web-ui.local
# If required in your setup, also set: --set ingress.className=traefik
```

Note on drift/adoption
- You can install with `helm` first and set up Argo CD later. If the Argo CD `Application` uses the same release name and namespace, Argo will adopt the existing release. If they differ, Argo will create a separate release; no drift or fighting will occur, but you may then have two instances. To keep one instance, align the release name/namespace or uninstall the manual Helm release after Argo is in place.

## Recommended: manage via Argo CD + ApplicationSet

Add Argo Helm repo:
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

Install Argo CD on dev:
```bash
# Namespace
kubectl --context k3d-dev create namespace argocd --dry-run=client -o yaml | kubectl --context k3d-dev apply -f -

# Argo CD (installs core CRDs)
helm upgrade --install argo-cd argo/argo-cd \
  --namespace argocd \
  --kube-context k3d-dev \
  --set server.service.type=ClusterIP

# Wait for pods
kubectl --context k3d-dev -n argocd get pods
```

Apply the ApplicationSet (generates one Application per chart):
```bash
kubectl --context k3d-dev -n argocd apply -f argocd/bootstrap/dev/applicationset.yaml
kubectl --context k3d-dev -n argocd get applications
```

Open Argo CD UI (optional):
```bash
# Port-forward the server service
kubectl --context k3d-dev -n argocd port-forward svc/argo-cd-argocd-server 8080:80
# URL: http://localhost:8080

# Get initial admin password (macOS)
kubectl --context k3d-dev -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -D; echo
# Linux alternative: base64 --decode
```

Repeat for prod (optional):
```bash
kubectl --context k3d-prod create namespace argocd --dry-run=client -o yaml | kubectl --context k3d-prod apply -f -
helm upgrade --install argo-cd argo/argo-cd -n argocd --kube-context k3d-prod --set server.service.type=ClusterIP
helm upgrade --install argo-appset argo/argocd-applicationset -n argocd --kube-context k3d-prod
kubectl --context k3d-prod -n argocd get pods
```

## How env overlays and the ApplicationSet work

### Chart layout and overlays
- Base chart per app lives under `charts/<app>` (e.g., `charts/web-ui`).
- Environment overlays live under `charts/<app>/envs/<env>/values.yaml` (e.g., `charts/web-ui/envs/dev-us/values.yaml`).
- Helm merges overlays on top of the base `values.yaml` in order (base first, overlay later). This is where per-env replicas, resources, and ingress hosts are set.

### ApplicationSet – one Application per chart
- The `ApplicationSet` at `argocd/bootstrap/dev/applicationset.yaml` uses a Git generator with `directories: path: charts/*`.
- For each directory under `charts/` (that is a deployable chart), the generator produces an Argo CD `Application` pointing at that chart path.
- Each generated `Application` includes:
  - `source.path: charts/{{path.basename}}` (e.g., `charts/web-ui`)
  - `helm.valueFiles: [values.yaml, envs/dev-us/values.yaml]` so the env overlay is applied
  - `destination.server: https://kubernetes.default.svc` and `destination.namespace: {{path.basename}}`
- In effect, this is an "App-of-Apps" pattern realized through the `ApplicationSet` controller: it programmatically creates one `Application` per chart directory so you don’t maintain and update a static app-of-apps file whenever more charts are added.

### Switching environments (e.g., prod-us)
- To deploy a different overlay, change the `helm.valueFiles` in the `ApplicationSet` template:
  - From `envs/dev-us/values.yaml` to `envs/prod-us/values.yaml`, or
  - Create a separate `ApplicationSet` (e.g., `argocd/bootstrap/prod/applicationset.yaml`) that targets the prod overlay.

### Promotions (version.yaml override)
- We use a late-applied `version.yaml` per env to override only the image tag; it should be the last file under `helm.valueFiles` in the ApplicationSet so it wins merges.
- Example:
```yaml
path: charts/{{path.basename}}            # chart source (charts/web-ui or charts/api)
helm:
    valueFiles: # NOTE: Later files override earlier files
    - values.yaml              # base chart values
    - envs/dev-us/values.yaml  # env defaults
    - envs/dev-us/version.yaml # <-- tag/digest
```

- Promotion flow:
  - When ready to promote, copy the tag from lower env to higher env by copying the version file (or just its `image.tag`) from `dev-us` to `prod-us` and commit.
  - Argo CD will detect the change (via webhook or poll) and sync, deploying the new version to the target environment.

### Naming note
- Argo uses the `Application` name as the Helm release name (e.g., `dev-web-ui`).
- The chart helpers are set up to avoid duplicate suffixes (e.g., `dev-web-ui-web-ui`). If you prefer a fixed name, set `fullnameOverride` in values or set `spec.source.helm.releaseName` in the `ApplicationSet`.
