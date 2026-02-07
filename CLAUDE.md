# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Homelab infrastructure repository for a 3-node k3s Kubernetes cluster running on Intel NUC7i7BNH machines (32GB RAM, 256GB SSD each, Ubuntu Server 24.04).

## Cluster Nodes

- nuc1: 192.168.1.20 (k3s server — control-plane + etcd)
- nuc2: 192.168.1.21 (k3s agent — worker)
- nuc3: 192.168.1.22 (k3s agent — worker)

SSH access: `ssh bert@<ip>` (key-only, passwordless sudo)

## k3s

- Version: v1.34.3+k3s1
- Installed with `--cluster-init --disable traefik --disable servicelb`
- Kubeconfig: `~/.kube/config` (local Mac)

## Cluster Add-ons

- **MetalLB** v0.14.9 — L2 mode, IP pool 192.168.1.200–250
- **Traefik** v2.11 — Ingress controller in `traefik` namespace
  - LoadBalancer IP: 192.168.1.202
  - All HTTP services route through Traefik by hostname
  - Dashboard: http://192.168.1.202:8080 or `traefik.homelab.bertbullough.com`
- **kube-prometheus-stack** — Helm release `monitoring` in `monitoring` namespace
  - Grafana: `grafana.homelab.bertbullough.com` via Traefik (admin/admin)
  - Prometheus: 30d retention, 20Gi storage
- **Home Assistant** — `homeassistant` namespace
  - UI: `hass.homelab.bertbullough.com` via Traefik (port 80)
  - 10Gi PVC on local-path for `/config`
  - Grafana dashboard: provisioned via ConfigMap (`grafana-dashboard.yaml`)
- **Pi-hole** v6 — `pihole` namespace
  - DNS: LoadBalancer IP 192.168.1.200 (port 53 TCP/UDP)
  - Web admin: `pihole.homelab.bertbullough.com` via Traefik (admin/admin)
  - PVCs on local-path: 1Gi for `/etc/pihole`, 500Mi for `/etc/dnsmasq.d`
  - Custom DNS: `custom-dns.yaml` ConfigMap with dnsmasq `address=` entries for `*.homelab.bertbullough.com` hostnames

## Ingress Routing

All HTTP traffic routes through Traefik at 192.168.1.202 using hostname-based routing.
Hostnames are resolved automatically by Pi-hole DNS (192.168.1.200) via custom dnsmasq records.
Set your device or router DNS to 192.168.1.200 to resolve these hostnames:

| Hostname | Service |
|---|---|
| `traefik.homelab.bertbullough.com` | Traefik dashboard |
| `grafana.homelab.bertbullough.com` | Grafana |
| `hass.homelab.bertbullough.com` | Home Assistant |
| `pihole.homelab.bertbullough.com` | Pi-hole admin |

## Repository Structure

- `k8s/metallb/` — MetalLB IP pool and L2 advertisement manifests
- `k8s/traefik/` — Traefik ingress controller deployment and IngressRoutes
- `k8s/monitoring/` — Helm values for kube-prometheus-stack, Grafana IngressRoute
- `k8s/homeassistant/` — Home Assistant deployment manifests, IngressRoute
- `k8s/pihole/` — Pi-hole DNS ad-blocker deployment, DNS LoadBalancer, IngressRoute
- `SETUP.md` — Full setup documentation and node configuration details
