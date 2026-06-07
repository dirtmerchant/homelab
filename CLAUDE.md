# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Homelab infrastructure repository for a 3-node k3s Kubernetes cluster running on Intel NUC7i7BNH machines (32GB RAM, 256GB SSD each, Ubuntu Server 24.04). All cluster state is declarative YAML in `k8s/`, managed by ArgoCD GitOps.

## Cluster Nodes

- nuc1: 192.168.1.20 (k3s server — control-plane + etcd)
- nuc2: 192.168.1.21 (k3s agent — worker)
- nuc3: 192.168.1.22 (k3s agent — worker)

SSH access: `ssh nuc1`, `ssh nuc2`, `ssh nuc3` (aliases in `~/.ssh/config`, key-only, passwordless sudo)
Kubeconfig: `~/.kube/config` (local Mac)
Versions: k3s v1.34.3+k3s1, Ubuntu 24.04.4 LTS, kernel 6.8.0-124-generic (as of 2026-06-07)

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

**Sync policy exceptions:** The namespaces app uses `prune: false`. Helm-based apps (monitoring, cert-manager, ollama, longhorn) use `ServerSideApply`. Some wave-2 apps use `directory.include` to limit which files are synced.

## Adding a New Service

1. Create `k8s/<name>/` with deployment manifests (or just `values.yaml` for Helm apps)
2. Add namespace: either add to `k8s/namespaces.yaml` or create `k8s/<name>/namespace.yaml` (both patterns exist — central file has traefik/monitoring/cert-manager/ollama; other services define their own)
3. Include pod security labels on the namespace (`pod-security.kubernetes.io/{enforce,warn,audit}`)
4. Create an ArgoCD Application in `k8s/argocd/apps/<name>.yaml` (sync wave 0 for most apps)
5. If the service needs an ingress hostname:
   - Add a Traefik IngressRoute with `tls: {}` (wildcard cert auto-applies)
   - Reference the `security-headers@kubernetescrd` middleware from the traefik namespace
   - Add a DNS entry in `k8s/pihole/custom-dns.yaml` pointing the hostname to 192.168.1.202
6. If the service needs a NetworkPolicy, add one in `k8s/<name>/networkpolicy.yaml`

## Key Conventions

- **Pod security**: Non-privileged workloads use `runAsNonRoot: true`, drop `ALL` capabilities, `RuntimeDefault` seccomp. The monitoring namespace uses `privileged` enforce (required for node-exporter DaemonSet); all others use `baseline` enforce with `restricted` warn/audit.
- **Storage**: All PVCs use `local-path` storage class (k3s default). PVs have node affinity — pods using local-path PVCs can only schedule on the node where the PV was created. If a node is down, pods with PVCs on that node will stay Pending.
- **TLS chain**: cert-manager creates a self-signed CA (`selfsigned` ClusterIssuer → `homelab-ca` Certificate → `homelab-ca` ClusterIssuer) that issues a wildcard cert for `*.homelab.bertbullough.com`. The cert lives in the `traefik` namespace and is set as the default TLS cert via a TLSStore. Any IngressRoute with `tls: {}` gets it automatically.
- **Ingress**: All services route through Traefik (192.168.1.202) with hostname-based routing. A global `security-headers` middleware (HSTS, frame-deny, XSS protection) in the traefik namespace is referenced cross-namespace by IngressRoutes.
- **DNS**: Pi-hole (192.168.1.200) resolves `*.homelab.bertbullough.com` via dnsmasq records in `k8s/pihole/custom-dns.yaml`.
- **Monitoring labels**: ServiceMonitors require `release: monitoring` label to be picked up by Prometheus.
- **Network policies**: Most services have a `networkpolicy.yaml` restricting ingress to Traefik and monitoring namespaces.

## Manual Secrets

These secrets are not in Git and must be created manually on the cluster before the respective services will work:

- `pihole-secret` (namespace: `pihole`, key: `webpassword`)
- `tailscale-auth` (namespace: `tailscale`, key: `TS_AUTHKEY`)
- `grafana-admin-secret` (namespace: `monitoring`, keys: `admin-user`, `admin-password`)
- `traefik-dashboard-auth` (namespace: `traefik`)

## CI/CD

- **GitHub Actions** (`.github/workflows/validate.yaml`): Runs yamllint + kubeconform on PRs touching `k8s/`
- **ArgoCD**: Auto-syncs from `main` with `prune: true` and `selfHeal: true` on all Applications
- **Renovate**: Pins Docker image digests, automerges patch updates, pins Traefik to v2.11.x (`renovate.json`)

## Synology NAS (DS218+)

IP: 192.168.1.10, SSH access: `ssh nas` (key-only, passwordless sudo via `/etc/sudoers.d/bert`)

**Security hardening applied (2026-06-06):**

- SMB guest access disabled on all shares (`guest ok=no` in `/usr/syno/etc/share_right.map` and `/etc/samba/smb.share.conf`)
- Home directory permissions fixed (`/var/services/homes` 755, each user dir 700)
- Default `admin` account disabled (DSM UI)
- SSH hardened: `PermitRootLogin no`, `PasswordAuthentication no`, removed `Match User root/admin` blocks (backup at `/etc/ssh/sshd_config.bak`)
- EOL packages removed: Python2, PHP7.4 (also removed Hyper Backup and Glacier Backup as PHP7.4 dependencies)
- Unused packages removed: GlacierBackup, HybridShare, ScsiTarget
- SMB minimum protocol raised from NT1 (SMBv1) to SMB2 in `/etc/samba/smb.conf` (backup at `smb.conf.bak`)
- AIConsole stopped (Postgres, Redis, deidd services no longer running)
- Stale core dumps cleaned from `/volume1/`
- ContainerManager stopped (kept installed for future use)
- DSM firewall enabled with allow-list: SSH/DSM/SMB from 192.168.1.0/24, Plex (32400) from any, deny all. DROP rule added via `iptables -A INPUT_FIREWALL -j DROP` (DSM UI doesn't generate this)

**DSM caveats:**

- DSM updates may reset `/etc/sudoers.d/bert` and `/etc/ssh/sshd_config` — re-apply after major DSM updates
- SMB config: DSM generates `/etc/samba/smb.share.conf` from `/usr/syno/etc/share_right.map` — edit `share_right.map` for persistent changes, then also edit `smb.share.conf` and restart `pkg-synosamba-smbd.service`. DSM may also reset `min protocol` in `smb.conf` if SMB settings are changed in the UI
- Firewall: DSM's "Deny all" rule doesn't generate an iptables DROP — must add manually via `sudo iptables -A INPUT_FIREWALL -j DROP` after any DSM firewall changes. Don't re-apply firewall from DSM UI while DROP rule is active (it will detect a block and roll back)

**Remaining services:** Plex, Synology Drive (port 6690), Synology Photos, FileStation, SynoFinder, DhcpServer, ActiveInsight, QuickConnect

## TP-Link T1600G-28TS V3 Switch

IP: 192.168.1.2, management via HTTPS web UI or telnet only.

**SSH is permanently broken** — the switch only offers `diffie-hellman-group1-sha1` (KEX) and `ssh-dss` (host key), both removed from OpenSSH 10.2. Firmware 3.0.6 Build 20200805 is the final release; the product is EOL. No alternative firmware exists (OpenWrt doesn't support the chipset).

**Telnet access** (port 23): Login with user `admin`, password in 1Password. Send `enable` after login to enter privileged mode. macOS has no telnet binary; use a Python raw socket client with IAC negotiation handling (Python 3.13 removed `telnetlib`).

**Hardening applied (2026-06-06):** SSH disabled, SNMP disabled, HTTP disabled (HTTPS only). Hostname and location set. Config saved to startup-config.

**Remaining web UI tasks:** Remove weak HTTPS ciphers (RC4, DES), configure NTP, enable flash logging. CLI syntax for these features is unsupported on this firmware version.

## Operational Notes

**Rolling node reboots:** Drain → reboot → uncordon one node at a time. Longhorn instance-manager PDBs may block drains — force-delete the pod if needed. After rebooting the control plane (nuc1), cert-manager-cainjector and kube-state-metrics may CrashLoop briefly until the API server is fully ready; they self-resolve.

**Tailscale pod conflicts:** Tailscale uses `hostNetwork: true` and claims a host-level TUN device (`tailscale0`). If a rolling update gets stuck (old RS holds TUN, new RS can't claim it), scale old ReplicaSets to 0, then delete the stale pod. If the TUN device is still held by a zombie process, the pod must be deleted and rescheduled.

**PV node affinity map (as of 2026-06-07):**

| PVC | Namespace | Node |
|-----|-----------|------|
| pihole-config | pihole | nuc3 |
| pihole-dnsmasq | pihole | nuc3 |
| homeassistant-config | homeassistant | nuc3 |
| ollama | ollama | nuc2 |
| prometheus-db | monitoring | nuc1 |

**NUC reconnect plan:** See `docs/nuc-reconnect-plan.md` for the full checklist when bringing nodes back online after downtime.

## Key IPs

| IP | Service |
|---|---|
| 192.168.1.2 | TP-Link T1600G-28TS switch |
| 192.168.1.10 | Synology NAS (DSM) |
| 192.168.1.20 | nuc1 (k3s server) |
| 192.168.1.21 | nuc2 (k3s agent) |
| 192.168.1.22 | nuc3 (k3s agent) |
| 192.168.1.200 | Pi-hole DNS (LoadBalancer) |
| 192.168.1.202 | Traefik ingress (LoadBalancer) |
| 192.168.1.200–250 | MetalLB L2 pool |
