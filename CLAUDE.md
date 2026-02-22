# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Homelab infrastructure repository for a 3-node k3s Kubernetes cluster running on Intel NUC7i7BNH machines (32GB RAM, 256GB SSD each, Ubuntu Server 24.04).

## Cluster Nodes

- nuc1: 192.168.1.20 (k3s server — control-plane + etcd)
- nuc2: 192.168.1.21 (k3s agent — worker)
- nuc3: 192.168.1.22 (k3s agent — worker)

SSH access: `ssh bert@<ip>` (key-only, passwordless sudo)
DNS: Pi-hole (192.168.1.200) primary, Google (8.8.8.8) fallback

## k3s

- Version: v1.34.3+k3s1
- Installed with `--cluster-init --disable traefik --disable servicelb`
- Kubeconfig: `~/.kube/config` (local Mac)

## Cluster Add-ons

- **MetalLB** v0.14.9 — L2 mode, IP pool 192.168.1.200–250
- **Traefik** v2.11 — Ingress controller in `traefik` namespace
  - LoadBalancer IP: 192.168.1.202
  - All services route through Traefik by hostname with TLS (HTTP redirects to HTTPS)
  - Dashboard: `traefik.homelab.bertbullough.com`
- **kube-prometheus-stack** — Helm release `monitoring` in `monitoring` namespace
  - Grafana: `grafana.homelab.bertbullough.com` via Traefik (admin/admin)
  - Prometheus: 30d retention, 20Gi storage
- **Home Assistant** — `homeassistant` namespace
  - UI: `hass.homelab.bertbullough.com` via Traefik (port 80)
  - 10Gi PVC on local-path for `/config`
  - Grafana dashboard: provisioned via ConfigMap (`grafana-dashboard.yaml`)
- **ArgoCD** — GitOps controller in `argocd` namespace
  - UI: `argocd.homelab.bertbullough.com` via Traefik
  - Helm release `argocd` (argo/argo-cd), non-HA, `server.insecure: true`
  - App-of-apps pattern: `k8s/argocd/apps/root.yaml` manages all child Applications
  - Auto-syncs all `k8s/` components from `main` branch
- **cert-manager** — `cert-manager` namespace
  - Helm chart from jetstack, managed by ArgoCD
  - Self-signed CA issuing wildcard cert for `*.homelab.bertbullough.com`
  - CA chain: self-signed ClusterIssuer → CA Certificate → CA ClusterIssuer → wildcard cert
  - TLSStore `default` in `traefik` namespace auto-applies cert to all `tls: {}` IngressRoutes
  - To trust the CA, export: `kubectl get secret homelab-ca-key-pair -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d`
  - Prometheus ServiceMonitor enabled (requires `release: monitoring` label)
  - Grafana dashboard: provisioned via ConfigMap (`grafana-dashboard.yaml`)
- **OpenClaw** — AI assistant in `openclaw` namespace
  - UI: `openclaw.homelab.bertbullough.com` via Traefik (port 18789)
  - Helm chart from `serhanekicii.github.io/openclaw-helm`, managed by ArgoCD
  - 5Gi PVC on local-path for `/home/node/.openclaw`
  - Hardened: NetworkPolicy (ingress from Traefik only, egress to public internet only), `automountServiceAccountToken: false`, web tools disabled
  - Requires `openclaw-env-secret` secret with `ANTHROPIC_API_KEY`
- **Pi-hole** v6 — `pihole` namespace
  - DNS: LoadBalancer IP 192.168.1.200 (port 53 TCP/UDP)
  - Web admin: `pihole.homelab.bertbullough.com` via Traefik (admin/admin)
  - PVCs on local-path: 1Gi for `/etc/pihole`, 500Mi for `/etc/dnsmasq.d`
  - Custom DNS: `custom-dns.yaml` ConfigMap with dnsmasq `address=` entries for `*.homelab.bertbullough.com` hostnames

## Ingress Routing

All HTTPS traffic routes through Traefik at 192.168.1.202 using hostname-based routing. HTTP requests are automatically redirected to HTTPS.
Wildcard TLS certificate (`*.homelab.bertbullough.com`) issued by a self-signed CA via cert-manager.
Hostnames are resolved automatically by Pi-hole DNS (192.168.1.200) via custom dnsmasq records.
Set your device or router DNS to 192.168.1.200 to resolve these hostnames:

| Hostname | Service |
|---|---|
| `traefik.homelab.bertbullough.com` | Traefik dashboard |
| `grafana.homelab.bertbullough.com` | Grafana |
| `hass.homelab.bertbullough.com` | Home Assistant |
| `pihole.homelab.bertbullough.com` | Pi-hole admin |
| `argocd.homelab.bertbullough.com` | ArgoCD UI |
| `openclaw.homelab.bertbullough.com` | OpenClaw AI assistant |

## Repository Structure

- `k8s/metallb/` — MetalLB IP pool and L2 advertisement manifests
- `k8s/traefik/` — Traefik ingress controller deployment and IngressRoutes
- `k8s/cert-manager/` — cert-manager Helm values + resources (CA chain, wildcard Certificate, TLSStore)
- `k8s/monitoring/` — Helm values for kube-prometheus-stack, Grafana IngressRoute
- `k8s/homeassistant/` — Home Assistant deployment manifests, IngressRoute
- `k8s/openclaw/` — OpenClaw AI assistant Helm values, IngressRoute
- `k8s/pihole/` — Pi-hole DNS ad-blocker deployment, DNS LoadBalancer, IngressRoute
- `k8s/argocd/` — ArgoCD GitOps controller (Helm values, IngressRoute, app-of-apps definitions)
- `.github/workflows/` — GitHub Actions CI (YAML lint + kubeconform validation)
- `SETUP.md` — Full setup documentation and node configuration details

## CI/CD

- **GitHub Actions** — PR validation workflow (`.github/workflows/validate.yaml`)
  - yamllint: lints all YAML in `k8s/` (excludes `k8s/longhorn/`)
  - kubeconform: validates manifests against k8s 1.34.0 schemas + CRD catalog
- **ArgoCD** — GitOps auto-sync from `main` branch
  - Only `k8s/argocd/apps/root.yaml` is manually applied; everything else is managed
  - Sync waves: namespaces (-3) → MetalLB (-2) → Traefik (-1) → apps (0) → cert-manager-resources (1) → monitoring-ingress (2)
  - Monitoring uses multi-source (Helm chart + git values)
