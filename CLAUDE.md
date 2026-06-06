# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Homelab infrastructure repository for a 3-node k3s Kubernetes cluster running on Intel NUC7i7BNH machines (32GB RAM, 256GB SSD each, Ubuntu Server 24.04). All cluster state is declarative YAML in `k8s/`, managed by ArgoCD GitOps.

## Cluster Nodes

- nuc1: 192.168.1.20 (k3s server — control-plane + etcd)
- nuc2: 192.168.1.21 (k3s agent — worker)
- nuc3: 192.168.1.22 (k3s agent — worker)

SSH access: `ssh bert@<ip>` (key-only, passwordless sudo)
Kubeconfig: `~/.kube/config` (local Mac)

## Validation Commands

Run these locally before pushing. CI runs them on PRs automatically.

```bash
# Lint all YAML (uses .yamllint.yaml config, max 200 char lines)
yamllint -c .yamllint.yaml k8s/

# Validate manifests against k8s schemas (excludes longhorn/, values.yaml, skips ArgoCD CRDs)
find k8s/ -name '*.yaml' -not -name 'values.yaml' -not -path 'k8s/longhorn/*' \
  | xargs kubeconform -strict -kubernetes-version 1.34.0 \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceVersion}}.json' \
    -skip ArgoCD,Application -summary
```

## Deployment Workflow

1. Push changes to `main` branch (or merge a PR)
2. ArgoCD auto-syncs all Applications from `k8s/` — no manual `kubectl apply` needed
3. Only `k8s/argocd/apps/root.yaml` was ever manually applied; it bootstraps everything else

## ArgoCD App-of-Apps Architecture

`k8s/argocd/apps/root.yaml` watches `k8s/argocd/apps/` and manages all child Application resources. Sync waves control deployment order:

| Wave | Applications |
|------|-------------|
| -3 | namespaces |
| -2 | metallb |
| -1 | traefik |
| 0 | cert-manager, monitoring, pihole, homeassistant, ollama, longhorn, tailscale |
| 1 | cert-manager-resources (depends on cert-manager CRDs existing) |
| 2 | argocd-resources, monitoring-ingress |

**Two app patterns exist in `k8s/argocd/apps/`:**

1. **Plain manifests** (pihole, homeassistant, traefik, metallb, tailscale): `source.path` points to a `k8s/<name>/` directory containing raw YAML.
2. **Multi-source Helm** (cert-manager, monitoring, ollama, argocd): Uses `sources[]` with a git `ref: values` source and a Helm chart source that references `$values/k8s/<name>/values.yaml`. Only the `values.yaml` file lives in this repo; the chart comes from an upstream Helm repo.

## Adding a New Service

1. Create `k8s/<name>/` with deployment manifests (or just `values.yaml` for Helm apps)
2. Add a namespace entry to `k8s/namespaces.yaml` with pod security labels
3. Create an ArgoCD Application in `k8s/argocd/apps/<name>.yaml` (sync wave 0 for most apps)
4. If the service needs an ingress hostname:
   - Add a Traefik IngressRoute with `tls: {}` (wildcard cert auto-applies)
   - Add a DNS entry in `k8s/pihole/custom-dns.yaml` pointing the hostname to 192.168.1.202
5. If the service needs a NetworkPolicy, add one in `k8s/<name>/networkpolicy.yaml`

## Key Conventions

- **Pod security**: Non-privileged workloads use `runAsNonRoot: true`, drop `ALL` capabilities, `RuntimeDefault` seccomp. See `k8s/namespaces.yaml` for per-namespace enforcement levels.
- **Storage**: All PVCs use `local-path` storage class (k3s default).
- **Ingress**: All services route through Traefik (192.168.1.202) with hostname-based routing. Wildcard TLS cert from self-signed CA via cert-manager auto-applies to any IngressRoute with `tls: {}`.
- **DNS**: Pi-hole (192.168.1.200) resolves `*.homelab.bertbullough.com` via dnsmasq records in `k8s/pihole/custom-dns.yaml`.
- **Monitoring labels**: ServiceMonitors require `release: monitoring` label to be picked up by Prometheus.
- **Network policies**: Most services have a `networkpolicy.yaml` restricting ingress to Traefik and monitoring namespaces.

## CI/CD

- **GitHub Actions** (`.github/workflows/validate.yaml`): Runs yamllint + kubeconform on PRs touching `k8s/`
- **ArgoCD**: Auto-syncs from `main` with `prune: true` and `selfHeal: true` on all Applications

## Key IPs

| IP | Service |
|---|---|
| 192.168.1.200 | Pi-hole DNS (LoadBalancer) |
| 192.168.1.202 | Traefik ingress (LoadBalancer) |
| 192.168.1.200–250 | MetalLB L2 pool |
