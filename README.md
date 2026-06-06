# Homelab K3s Cluster

GitOps-managed 3-node [k3s](https://k3s.io/) Kubernetes cluster running on Intel NUC7i7BNH machines. All cluster state is declarative YAML in `k8s/`, auto-synced by ArgoCD.

## Architecture

```
                   ┌─────────────┐
                   │   GitHub    │
                   │  (this repo)│
                   └──────┬──────┘
                          │ auto-sync
                   ┌──────▼──────┐
                   │   ArgoCD    │
                   │  (GitOps)   │
                   └──────┬──────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
     ┌────▼────┐    ┌─────▼────┐    ┌─────▼────┐
     │  nuc1   │    │   nuc2   │    │   nuc3   │
     │ server  │    │  agent   │    │  agent   │
     └─────────┘    └──────────┘    └──────────┘
```

- **3 nodes**: 32GB RAM, 256GB SSD each, Ubuntu Server 24.04
- **Networking**: MetalLB (L2) + Traefik ingress + Pi-hole DNS
- **TLS**: Wildcard cert from self-signed CA via cert-manager
- **Storage**: local-path (k3s default) + Longhorn

## Services

| Service | Type | Description |
|---------|------|-------------|
| [ArgoCD](https://argo-cd.readthedocs.io/) | Helm | GitOps continuous delivery |
| [cert-manager](https://cert-manager.io/) | Helm | TLS certificate management |
| [Home Assistant](https://www.home-assistant.io/) | Manifests | Home automation |
| [Longhorn](https://longhorn.io/) | Manifests | Distributed block storage |
| [MetalLB](https://metallb.universe.tf/) | Manifests | Bare-metal load balancer |
| [Monitoring](https://github.com/prometheus-community/helm-charts) | Helm | Prometheus + Grafana stack |
| [Ollama](https://ollama.com/) | Helm | Local LLM inference |
| [Pi-hole](https://pi-hole.net/) | Manifests | DNS ad-blocking + local DNS |
| [Tailscale](https://tailscale.com/) | Manifests | Subnet router for remote access |
| [Traefik](https://traefik.io/) | Manifests | Ingress controller + TLS termination |

## Repository Structure

```
k8s/
├── argocd/           # ArgoCD Helm values + app-of-apps definitions
├── cert-manager/     # cert-manager Helm values + CA chain resources
├── homeassistant/    # Home Assistant deployment manifests
├── longhorn/         # Longhorn storage manifests
├── metallb/          # MetalLB IP pool and L2 advertisement
├── monitoring/       # kube-prometheus-stack Helm values
├── ollama/           # Ollama Helm values
├── pihole/           # Pi-hole deployment + custom DNS records
├── tailscale/        # Tailscale subnet router deployment
├── traefik/          # Traefik ingress controller deployment
└── namespaces.yaml   # All namespace definitions with PSS labels
```

## GitOps Workflow

1. Make changes to YAML in `k8s/`
2. Push to `main` (or open a PR for CI validation)
3. ArgoCD auto-syncs all Applications with pruning and self-healing

Only `k8s/argocd/apps/root.yaml` was ever manually applied -- it bootstraps everything else via the [app-of-apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/).

## CI

GitHub Actions runs on PRs touching `k8s/`:
- **yamllint** -- lint all YAML
- **kubeconform** -- validate manifests against Kubernetes 1.34.0 schemas + CRD catalog

## Setup

See [SETUP.md](SETUP.md) for node installation and cluster bootstrap instructions.
