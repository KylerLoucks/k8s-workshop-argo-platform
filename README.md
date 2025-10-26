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
terraform version
```

## Setup k3d (first time)
```bash

# Or create dev/prod clusters
k3d cluster create dev --wait
k3d cluster create prod --wait

# List contexts
kubectl config get-contexts | grep k3d-
```

## Argo CD ApplicationSet (Helm)

Apply the ApplicationSet:

```bash
kubectl apply -n argocd -f argocd/applicationsets/environments-applicationset.yaml
```

Label cluster secrets so they map to environments:

```bash
kubectl -n argocd label secret <cluster-secret-name> environment=dev --overwrite
kubectl -n argocd label secret <cluster-secret-name> environment=prod --overwrite
```

The ApplicationSet deploys the umbrella Helm chart in `apps/` and selects per-environment values files under `apps/values/<env>.yaml`. There is no kustomize overlay; only Helm is used.

## Run locally with k3d

### Prerequisites
- k3d, kubectl, helm

### Create a local cluster
```bash
k3d cluster create workshop --wait
kubectl cluster-info
```

### Deploy sample apps (nginx images)
Install individually:
```bash
helm upgrade --install web-ui charts/web-ui
```

### Access the apps (port-forward)
```bash
# In separate terminals or backgrounded
kubectl port-forward svc/my-api 8080:80 &

# Test
curl -I http://localhost:8080/
```

### (Optional) Enable ingress
If you want ingress, enable it at install time and expose ports on the k3d loadbalancer:
```bash
# recreate cluster with LB ports mapped to host
k3d cluster delete dev || true
k3d cluster create dev -p "80:80@loadbalancer" -p "443:443@loadbalancer" --wait

helm upgrade --install web-ui charts/web-ui \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=web-ui.local
```

### Cleanup
```bash
helm uninstall web-ui || true
k3d cluster delete dev || true
```

### Two clusters: dev and prod (k3d)

Create both clusters:
```bash
k3d cluster create dev --wait
k3d cluster create prod --wait
kubectl config get-contexts | grep k3d-
```

Deploy `web-ui` to both clusters (separate namespace `web`):
```bash
# dev
helm upgrade --install web-ui charts/web-ui \
  --kube-context k3d-dev \
  --namespace web \
  --create-namespace

# prod
helm upgrade --install web-ui charts/web-ui \
  --kube-context k3d-prod \
  --namespace web \
  --create-namespace
```

Access each app via port-forward:
```bash
# dev on localhost:8081
kubectl --context k3d-dev -n web port-forward svc/web-ui 8081:80 &

# prod on localhost:8082
kubectl --context k3d-prod -n web port-forward svc/web-ui 8082:80 &

# smoke test
curl -I http://localhost:8081/
curl -I http://localhost:8082/
```

Clean up:
```bash
helm --kube-context k3d-dev -n web uninstall web-ui || true
helm --kube-context k3d-prod -n web uninstall web-ui || true
k3d cluster delete dev || true
k3d cluster delete prod || true
```

## Install Argo CD + ApplicationSet on k3d (Helm)

Install Argo Helm repo:
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

Install on dev cluster (repeat for prod by swapping context/paths):
```bash
# Namespace
kubectl --context k3d-dev create namespace argocd --dry-run=client -o yaml | kubectl --context k3d-dev apply -f -

# Argo CD (installs CRDs)
helm upgrade --install argo-cd argo/argo-cd \
  --namespace argocd \
  --kube-context k3d-dev \
  --set server.service.type=ClusterIP

# Wait for pods
kubectl --context k3d-dev -n argocd get pods
```

Apply your ApplicationSet once CRDs are present:
```bash
kubectl --context k3d-dev -n argocd apply -f argocd/bootstrap/dev/applicationset.yaml
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

Install on prod (optional):
```bash
kubectl --context k3d-prod create namespace argocd --dry-run=client -o yaml | kubectl --context k3d-prod apply -f -
helm upgrade --install argo-cd argo/argo-cd -n argocd --kube-context k3d-prod --set server.service.type=ClusterIP
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

### Naming note
- Argo uses the `Application` name as the Helm release name (e.g., `dev-web-ui`).
- The chart helpers are set up to avoid duplicate suffixes (e.g., `dev-web-ui-web-ui`). If you prefer a fixed name, set `fullnameOverride` in values or set `spec.source.helm.releaseName` in the `ApplicationSet`.
