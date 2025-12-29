# Alternative Argo CD Automation Approaches

## Branch Based Approach (Isolate Helm manifest changes)

I would always advise to use the [trunk-based development](https://trunkbaseddevelopment.com/) approach and not use environments-per-branch. The purpose of these docs is just to show how you can do it the branch-based way if it is insisted this approach should be taken.

1. `Build` job runs (builds docker images based on files changed)

> [!NOTE] 
> `Build` workflow triggers on PRs open into main branch and pushes to main:
> ```yml
> on:
>   push:
>     branches: ["main"]
>   pull_request:
>     branches: ["main"]
>     types: [opened, synchronize, reopened]
>   workflow_dispatch:
> ```
>

2. Trigger composite action (see below), passing in image tag from `Build` workflow

```yml
name: GitOps Promote

on:
  workflow_run:
    workflows: ["Build"]
    types: [completed]
    branches: ["main"]
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

jobs:
  resolve-tag:
    name: Resolve image tag
    runs-on: BigRunner
    if: github.event_name == 'workflow_dispatch' || github.event.workflow_run.conclusion == 'success'
    outputs:
      image_tag: ${{ steps.resolve.outputs.image_tag }}
    steps:
      # Always checkout main so workflow_dispatch isn't ambiguous.
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: main

      - id: resolve
        shell: bash
        run: |
          set -euo pipefail
          
          # If the workflow is triggered by a workflow_run, use the head_sha of the workflow run.
          # Otherwise, use the head_sha of main.
          if [[ "${{ github.event_name }}" == "workflow_run" ]]; then
            head_sha="${{ github.event.workflow_run.head_sha }}"
          else
            git fetch origin main
            git checkout main
            git reset --hard origin/main
            head_sha="$(git rev-parse HEAD)"
          fi
          image_tag="${head_sha:0:7}"
          echo "image_tag=$image_tag" >> "$GITHUB_OUTPUT"

  bump-development:
    name: Bump development-version.yaml
    runs-on: ubuntu-latest
    needs: [resolve-tag]
    environment: development
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: main

      - name: Bump development version
        uses: ./.github/actions/gitops-bump-tags
        with:
          environment: development
          image-tag: ${{ needs.resolve-tag.outputs.image_tag }}
          commit-message: "chore(deploy): bump development-version.yaml to ${{ needs.resolve-tag.outputs.image_tag }}"
          helm-chart-path: helm

  bump-production:
    name: Bump production-version.yaml (approval gate)
    runs-on: ubuntu-latest
    needs: [resolve-tag, bump-development]
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: main

      - name: Bump production version
        uses: ./.github/actions/gitops-bump-tags
        with:
          environment: production
          image-tag: ${{ needs.resolve-tag.outputs.image_tag }}
          commit-message: "chore(deploy): bump production-version.yaml to ${{ needs.resolve-tag.outputs.image_tag }}"
          helm-chart-path: helm
```


### Composite Action (Bumps <env>-version.yaml version values files)
```yml
name: GitOps bump image tags
description: "Update <chart-path>/*/values.d/<env>-version.yaml image tags and commit"

inputs:
  environment:
    description: "Environment to bump (sandbox|development|uat|production)"
    required: true

  # This is normally the short SHA of the commit that built/pushed the image (e.g. Deploy workflow uses git rev-parse --short HEAD).
  # If omitted, we fall back to the current checked-out commit (after the optional rebase step below).
  image-tag:
    description: "Image tag to set (usually short SHA). If omitted, defaults to current origin/main HEAD."
    required: false
    default: ""

  commit-message:
    description: "Commit message for the bump"
    required: true

  # Hygiene: keeps the bump commit based on latest main, avoiding drift if the runner has an older checkout.
  # Note: this assumes the caller checked out the repo (typically ref: main, fetch-depth: 0).
  align-checkout:
    description: "If true, align checkout to base commit before bump"
    required: false
    default: "true"

  # Root folder containing per-service Helm charts, e.g. helm/<service>/Chart.yaml
  helm-chart-path:
    description: "Root path where Helm charts live"
    required: false
    default: "helm"

  # Safety rail: when the caller explicitly supplies image-tag, ensure that tag corresponds to a commit that exists on origin/main.
  # This prevents accidentally promoting a SHA from a PR branch or some other non-main ref.
  require-tag-on-main:
    description: "If true, verify image-tag commit exists on origin/main (prevents deploying PR-head SHA)"
    required: false
    default: "false"

runs:
  using: composite
  steps:
    - name: Align checkout to deploy base
      if: ${{ inputs.align-checkout == 'true' }}
      shell: bash
      env:
        IMAGE_TAG_INPUT: ${{ inputs.image-tag }}
      run: |
        set -euo pipefail
        git fetch origin main

        if [[ -n "${IMAGE_TAG_INPUT:-}" ]]; then
          if ! BASE_SHA="$(git rev-parse --verify "${IMAGE_TAG_INPUT}^{commit}" 2>/dev/null)"; then
            echo "ERROR: image-tag '${IMAGE_TAG_INPUT}' is not a valid commit; cannot align checkout." >&2
            exit 1
          fi
          echo "Detaching to image-tag commit ${BASE_SHA} to match build artifacts."
          git checkout --detach "$BASE_SHA"
        else
          echo "Detaching to latest origin/main."
          git checkout --detach origin/main
        fi

    - name: Install yq
      uses: mikefarah/yq@v4

    - name: Update All Services ${{ inputs.environment }}-version.yaml
      shell: bash
      env:
        ENVIRONMENT: ${{ inputs.environment }}
        IMAGE_TAG_INPUT: ${{ inputs.image-tag }}
        HELM_CHART_PATH: ${{ inputs.helm-chart-path }}
        REQUIRE_TAG_ON_MAIN: ${{ inputs.require-tag-on-main }}
      run: |
        set -euo pipefail

        # Validate chart root exists
        if [[ -z "${HELM_CHART_PATH:-}" ]]; then
          echo "HELM_CHART_PATH is required" >&2
          exit 1
        fi
        if [[ ! -d "$HELM_CHART_PATH" ]]; then
          echo "HELM_CHART_PATH does not exist: $HELM_CHART_PATH" >&2
          exit 1
        fi

        # Decide which tag to write:
        # - Prefer the explicitly provided tag (normal CI/CD path).
        # - Otherwise default to the current HEAD short SHA (after optional rebase), which should reflect origin/main.
        if [[ -n "${IMAGE_TAG_INPUT:-}" ]]; then
          IMAGE_TAG="$IMAGE_TAG_INPUT"
        else
          IMAGE_TAG="$(git rev-parse --short=7 HEAD)"
        fi
        export IMAGE_TAG
        echo "Using IMAGE_TAG=$IMAGE_TAG"

        # Optional guardrail:
        # If the caller explicitly provided IMAGE_TAG_INPUT, ensure that commit is reachable from origin/main.
        # This prevents "image-only" promotions where a SHA exists but never landed on main.
        if [[ -n "${IMAGE_TAG_INPUT:-}" && "${REQUIRE_TAG_ON_MAIN:-true}" == "true" ]]; then
          git fetch origin main >/dev/null 2>&1 || true
          if ! FULL_SHA="$(git rev-parse "${IMAGE_TAG_INPUT}^{commit}" 2>/dev/null)"; then
            echo "ERROR: image-tag ${IMAGE_TAG_INPUT} is not a valid git reference; refusing to bump." >&2
            exit 1
          fi
          if ! git merge-base --is-ancestor "$FULL_SHA" origin/main; then
            echo "ERROR: image-tag $FULL_SHA is not contained in origin/main; refusing to bump." >&2
            exit 1
          fi
        fi

        # Discover apps by finding Chart.yaml files under <helm-chart-path>/*/Chart.yaml
        # This keeps the action generic: it will bump tags for every chart found under the root.
        mapfile -t APPS < <(
          for chart in "$HELM_CHART_PATH"/*/Chart.yaml; do
            [[ -f "$chart" ]] && basename "$(dirname "$chart")"
          done | sort -u
        )

        if [[ ${#APPS[@]} -eq 0 ]]; then
          echo "No Helm charts found under ${HELM_CHART_PATH%/}/*/Chart.yaml" >&2
          exit 1
        fi

        updated=0
        for app in "${APPS[@]}"; do
          version_file="${HELM_CHART_PATH%/}/${app}/values.d/${ENVIRONMENT}-version.yaml"
          [[ -f "$version_file" ]] || { echo "Missing version file for app '$app': $version_file" >&2; exit 1; }

          changed=0

          # Version files are not uniform:
          # - some use: image.tag
          # - others use: service.image.tag
          if [[ "$(yq e '.service.image.tag' "$version_file")" != "null" ]]; then
            current_image_tag="$(yq e '.service.image.tag' "$version_file")"
            if [[ "$current_image_tag" != "$IMAGE_TAG" ]]; then
              yq -i '.service.image.tag = strenv(IMAGE_TAG)' "$version_file"
              changed=1
            fi
          elif [[ "$(yq e '.image.tag' "$version_file")" != "null" ]]; then
            current_image_tag="$(yq e '.image.tag' "$version_file")"
            if [[ "$current_image_tag" != "$IMAGE_TAG" ]]; then
              yq -i '.image.tag = strenv(IMAGE_TAG)' "$version_file"
              changed=1
            fi
          else
            echo "No supported image tag key found in $version_file (expected image.tag or service.image.tag)" >&2
            exit 1
          fi

          # Update migrations image tag
          export MIGRATION_TAG="${app}-${IMAGE_TAG}"
          if [[ "$(yq e '.service.migrations.image.tag' "$version_file")" != "null" ]]; then
            current_migration_tag="$(yq e '.service.migrations.image.tag' "$version_file")"
            if [[ "$current_migration_tag" != "$MIGRATION_TAG" ]]; then
              yq -i '.service.migrations.image.tag = strenv(MIGRATION_TAG)' "$version_file"
              changed=1
            fi
          elif [[ "$(yq e '.migrations.image.tag' "$version_file")" != "null" ]]; then
            current_migration_tag="$(yq e '.migrations.image.tag' "$version_file")"
            if [[ "$current_migration_tag" != "$MIGRATION_TAG" ]]; then
              yq -i '.migrations.image.tag = strenv(MIGRATION_TAG)' "$version_file"
              changed=1
            fi
          fi

          if [[ $changed -eq 1 ]]; then
            updated=$((updated + 1))
          fi
        done

        if [[ $updated -eq 0 ]]; then
          echo "No updates performed."
          exit 0
        fi

    - name: Switch to target branch (required after detach)
      shell: bash
      env:
        ENVIRONMENT: ${{ inputs.environment }}
      run: |
        set -euo pipefail
        git switch -C "env/${ENVIRONMENT}"

    - name: Commit bumps
      uses: stefanzweifel/git-auto-commit-action@v7
      with:
        commit_message: ${{ inputs.commit-message }}
        branch: env/${{ inputs.environment }} # push to e.g. env/development branch

```


## Argo CD Applications and ApplicationSet Considerations

### Argo CD installed on each environment
For the non-management cluster approach (Argo CD Installed on each environment's EKS cluster), use app-of-apps pointing at the environment `apps` folder per cluster:

```bash
argocd
└── envs
    ├── production
    │   └── apps
    └── development
        └── apps
            ├── service1.yaml
            ├── service2.yaml
            ├── service3.yaml
            └── service4.yaml
```

### Application CRD Example
```yml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: service1
  namespace: argocd
  # Keep this finalizer ONLY if when deleting this Application from Argo CD, you want to cascade delete all k8s resources such as deployments, services, etc.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  sources:
    - repoURL: https://github.com/kylerloucks/k8s-workshop-argo-platform.git
      targetRevision: env/development # <-- Branch `env/development`
      path: charts/service1     # <-- Path to the chart directory
      helm:
        valueFiles:
          - $values/values/service1/dev-us/values.yaml
          - $values/values/service1/dev-us/version.yaml
    - repoURL: https://github.com/kylerloucks/k8s-workshop-argo-platform.git
      targetRevision: env/development # <-- Branch `env/development`
      ref: values
```

### Argo CD installed on management cluster
For the management cluster approach (Argo CD lives in a dedicated cluster) use app-of-apps to management `appsets` folder:

```bash
argocd
└── management
    └── appsets
        ├── service1.yaml
        ├── service2.yaml
        ├── service3.yaml
        └── service4.yaml
```

### ApplicationSet CRD example:
```yml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: service1
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true
  generators:
    - merge:
        mergeKeys: [server]
        generators:
          - clusters:
              selector:
                matchExpressions:
                  - key: cluster-name
                    operator: NotIn
                    values: [in-cluster]
                  - key: enable_argocd
                    operator: In
                    values: ['true']
          - list:
              elements:
                - environment: dev
                  targetRevision: env/development
                - environment: prod
                  targetRevision: env/production
  template:
    metadata:
      name: service1
    spec:
      project: default
      sources:
        - repoURL: https://github.com/kylerloucks/k8s-workshop-argo-platform.git
          targetRevision: '{{targetRevision}}'
          path: charts/service1
          helm:
            releaseName: service1
            valueFiles:
              - $values/values/dev-us/service1/values.yaml
              - $values/values/dev-us/service1/version.yaml
        - repoURL: https://github.com/kylerloucks/k8s-workshop-argo-platform.git
          targetRevision: '{{targetRevision}}'
          ref: values
```

