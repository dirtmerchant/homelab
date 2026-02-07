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
- **kube-prometheus-stack** — Helm release `monitoring` in `monitoring` namespace
  - Grafana: http://192.168.1.200 (admin/admin)
  - Prometheus: 30d retention, 20Gi storage
- **Home Assistant** — `homeassistant` namespace
  - UI: http://192.168.1.201:8123
  - 10Gi PVC on local-path for `/config`
  - Grafana dashboard: provisioned via ConfigMap (`grafana-dashboard.yaml`)

## Repository Structure

- `k8s/metallb/` — MetalLB IP pool and L2 advertisement manifests
- `k8s/monitoring/` — Helm values for kube-prometheus-stack
- `k8s/homeassistant/` — Home Assistant deployment manifests
- `SETUP.md` — Full setup documentation and node configuration details
