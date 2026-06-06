# /diff-live

Shows differences between the repo manifests and what's running in the cluster.

## Usage

```
/diff-live [namespace]
```

If a namespace is given, diff only that service. Otherwise, diff all services.

## Instructions

### Determine which services to diff

Read the ArgoCD Application files in `k8s/argocd/apps/` to build a list of services. Classify each as:

- **Plain manifest**: Application uses singular `source` with a `path` field (e.g. pihole, homeassistant, traefik, metallb, tailscale)
- **Helm chart**: Application uses plural `sources` array (e.g. cert-manager, monitoring, ollama, argocd)

If the user provided a namespace argument (`$ARGUMENTS`), filter to just that service.

### For plain-manifest services

Run `kubectl diff` against the repo manifests:

```bash
kubectl diff -f k8s/<name>/ 2>&1 || true
```

**Important:** `kubectl diff` returns exit code 0 when no differences exist and exit code 1 when differences are found (this is normal, not an error). Exit code >1 indicates an actual error. The `|| true` prevents the shell from treating exit code 1 as a failure.

### For Helm chart services

Helm charts are managed by ArgoCD, so check their sync status instead:

```bash
kubectl get application <name> -n argocd -o jsonpath='{.status.sync.status}'
```

Report whether the application is `Synced` or `OutOfSync`.

### Presentation

For each service, report one of:
- **In sync**: No differences found
- **Differences found**: Show the diff output
- **Helm (synced/out-of-sync)**: Report ArgoCD sync status

If diffing all services, present a summary table first, then show detailed diffs only for services with differences.

## allowed-tools

Bash, Read, Glob
