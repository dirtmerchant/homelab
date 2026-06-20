# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Homelab infrastructure repository for a 3-node k3s Kubernetes cluster running on Intel NUC7i7BNH machines (32GB RAM, 256GB SSD each, Ubuntu Server 24.04). All cluster state is declarative YAML in `k8s/`, managed by ArgoCD GitOps.

## Cluster Nodes

3-node k3s cluster on Intel NUC7i7BNH machines: one server (control-plane + etcd), two agents. SSH aliases configured in `~/.ssh/config` (key-only, passwordless sudo). SSH keys are managed by 1Password — no private key material on disk. The 1Password SSH agent serves the "Homelab SSH Key" (Ed25519) from the Homelab vault via `~/.config/1Password/ssh/agent.toml`. See `CLAUDE.local.md` for IPs, MACs, and access details.

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
    -skip ArgoCD,Application,ExternalSecret,ClusterSecretStore -summary
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
| -1 | traefik, external-secrets |
| 0 | cert-manager, monitoring, pihole, homeassistant, ollama, longhorn, tailscale, external-secrets-resources |
| 1 | cert-manager-resources (depends on cert-manager CRDs existing) |
| 2 | argocd-resources, monitoring-ingress |

**Two app patterns exist in `k8s/argocd/apps/`:**

1. **Plain manifests** (pihole, homeassistant, traefik, metallb, tailscale): `source.path` points to a `k8s/<name>/` directory containing raw YAML.
2. **Multi-source Helm** (cert-manager, monitoring, ollama, argocd, external-secrets): Uses `sources[]` with a git `ref: values` source and a Helm chart source that references `$values/k8s/<name>/values.yaml`. Only the `values.yaml` file lives in this repo; the chart comes from an upstream Helm repo.

**Sync policy exceptions:** The namespaces app uses `prune: false`. Helm-based apps (monitoring, cert-manager, ollama, longhorn, external-secrets) use `ServerSideApply`. Some wave-2 apps use `directory.include` to limit which files are synced.

## Adding a New Service

1. Create `k8s/<name>/` with deployment manifests (or just `values.yaml` for Helm apps)
2. Add namespace: either add to `k8s/namespaces.yaml` or create `k8s/<name>/namespace.yaml` (both patterns exist — central file has traefik/monitoring/cert-manager/ollama; other services define their own)
3. Include pod security labels on the namespace (`pod-security.kubernetes.io/{enforce,warn,audit}`)
4. Create an ArgoCD Application in `k8s/argocd/apps/<name>.yaml` (sync wave 0 for most apps)
5. If the service needs an ingress hostname:
   - Add a Traefik IngressRoute with `tls: {}` (wildcard cert auto-applies)
   - Reference the `security-headers@kubernetescrd` middleware from the traefik namespace
   - Add a DNS entry in both `k8s/pihole/custom-dns.yaml` and `nas/pihole/custom-dns/02-custom-dns.conf` pointing the hostname to 192.168.1.202 (see `docs/pihole-ha.md`)
6. If the service needs a NetworkPolicy, add one in `k8s/<name>/networkpolicy.yaml`

## Key Conventions

- **Pod security**: Non-privileged workloads use `runAsNonRoot: true`, drop `ALL` capabilities, `RuntimeDefault` seccomp. The monitoring namespace uses `privileged` enforce (required for node-exporter DaemonSet); all others use `baseline` enforce with `restricted` warn/audit.
- **Storage**: All PVCs use `local-path` storage class (k3s default). PVs have node affinity — pods using local-path PVCs can only schedule on the node where the PV was created. If a node is down, pods with PVCs on that node will stay Pending.
- **TLS chain**: cert-manager creates a self-signed CA (`selfsigned` ClusterIssuer → `homelab-ca` Certificate → `homelab-ca` ClusterIssuer) that issues a wildcard cert for `*.homelab.bertbullough.com`. The cert lives in the `traefik` namespace and is set as the default TLS cert via a TLSStore. Any IngressRoute with `tls: {}` gets it automatically.
- **Ingress**: All services route through Traefik (192.168.1.202) with hostname-based routing. A global `security-headers` middleware (HSTS, frame-deny, XSS protection) in the traefik namespace is referenced cross-namespace by IngressRoutes.
- **DHCP**: The GFiber router handles all DHCP. Its cloud management portal (gfiber.com) does not support DHCP reservations or static IP assignment — the Devices page only shows read-only info (connection status, MAC, IP). There is no local admin UI (192.168.1.1 returns nothing). To assign static IPs: set them on-device where supported (Apple TV: Settings > Network > Configure IP > Manual; HomePod Minis don't expose network settings), move DHCP to Pi-hole (built-in DHCP server with reservations), or put the GFiber router in bridge mode behind a router you control.
- **DNS**: Dual Pi-hole for HA. Router DHCPv4 hands out NAS Pi-hole (192.168.1.10) as DNS 1 and cluster Pi-hole (192.168.1.200) as DNS 2. The NAS also serves DNS over IPv6 (`2605:a601:8007:e800::2`). The Google Fiber router pushes Google's IPv6 DNS (`2001:4860:4860::8888/8844`) via RDNSS in Router Advertisements — this can't be changed, so devices on DHCP may bypass Pi-hole for IPv6 DNS queries. The Mac has manual DNS set to use Pi-hole (IPv6 first, then IPv4 fallback). Config changes are made on the cluster (GitOps) and synced to the NAS via Nebula Sync every 30 min. Custom DNS records must be updated in both `k8s/pihole/custom-dns.yaml` and `nas/pihole/custom-dns/02-custom-dns.conf`. See `docs/pihole-ha.md`.
- **Monitoring labels**: ServiceMonitors require `release: monitoring` label to be picked up by Prometheus.
- **Network policies**: Most services have a `networkpolicy.yaml` restricting ingress to Traefik and monitoring namespaces.

## Secrets Management (External Secrets Operator + 1Password)

Secrets are managed by the External Secrets Operator (ESO) using the 1Password SDK provider. ESO syncs secrets from the "Homelab" vault in 1Password to Kubernetes automatically. Only one bootstrap secret is manual.

**Bootstrap secret** (only manual secret — create before first ArgoCD sync):

```bash
kubectl create namespace external-secrets
kubectl create secret generic onepassword-service-account \
  -n external-secrets --from-literal=token='<1password-service-account-token>'
```

The ArgoCD repo secret (`homelab-repo` in `argocd` namespace) must also be created manually for the initial bootstrap, but ESO takes over its management once running.

**ESO-managed secrets:**

| Secret | Namespace | 1Password Item | Fields |
|--------|-----------|----------------|--------|
| `pihole-secret` | pihole | `pihole` | `webpassword` |
| `tailscale-auth` | tailscale | `tailscale` | `TS_AUTHKEY` |
| `grafana-admin-secret` | monitoring | `grafana` | `admin-user`, `admin-password` |
| `traefik-dashboard-auth` | traefik | `traefik` | `users` (htpasswd format) |
| `homelab-repo` | argocd | `argocd-repo` | `type`, `repo-url`, `username`, `password` |

**1Password item setup:** Each item must exist in the "Homelab" vault with the exact title and field names listed above. ESO uses the SDK provider's `item/field` path syntax (e.g., `pihole/webpassword`). Note: the ArgoCD repo URL is stored as `repo-url` (not `url`) because 1Password treats fields named `url` as URL objects rather than text fields.

**Rotating the GitHub PAT:** Update the `password` field in the `argocd-repo` 1Password item, then restart the ESO controller to clear the SDK cache: `kubectl rollout restart deployment/external-secrets -n external-secrets`. ESO will sync the new PAT to the cluster within ~30s of the restart. Revoke the old PAT in GitHub after confirming ArgoCD still syncs.

**Rotating SSH keys:** Generate a new Ed25519 SSH key in the 1Password desktop app (Homelab vault), enable it for the SSH agent, and update `~/.config/1Password/ssh/agent.toml` to reference the new item. Deploy the new public key to all hosts (`nuc1-3`, `nas`) via `op item get "<name>" --vault Homelab --fields "public key"`, then remove the old key from each host's `~/.ssh/authorized_keys`.

**Architecture:** ClusterSecretStore `onepassword` connects to 1Password API via service account token. ExternalSecrets for pihole and tailscale live alongside their services; grafana, traefik, and argocd-repo ExternalSecrets live in `k8s/external-secrets/resources/` (they target namespaces different from the deploying app).

## CI/CD

- **GitHub Actions** (`.github/workflows/validate.yaml`): Runs yamllint + kubeconform on PRs touching `k8s/`
- **ArgoCD**: Auto-syncs from `main` with `prune: true` and `selfHeal: true` on all Applications
- **Renovate**: Pins Docker image digests, automerges patch updates, pins Traefik to v2.11.x, tracks NAS docker-compose images (`renovate.json`)

## Synology NAS (DS218+)

SSH access via `ssh nas` (port 2222). Security-hardened (2026-06-06): SSH key-only, non-standard port, SMBv1 disabled, admin account disabled, DSM firewall enabled. See `CLAUDE.local.md` for full hardening details, DSM caveats, and IP/access info.

## TP-Link T1600G-28TS V3 Switch

28-port managed switch (EOL, firmware 3.0.6). SSH is permanently broken (removed ciphers); management via HTTPS web UI or telnet only (Python raw socket client required — macOS has no telnet, Python 3.13 removed `telnetlib`). Hardened (2026-06-06): SSH/SNMP/HTTP disabled. See `CLAUDE.local.md` for IP, telnet access, CLI caveats, and full port map with device inventory.

## Operational Notes

**Rolling node reboots:** Drain → reboot → uncordon one node at a time. Longhorn instance-manager PDBs may block drains — force-delete the pod if needed. After rebooting the control plane (nuc1), cert-manager-cainjector and kube-state-metrics may CrashLoop briefly until the API server is fully ready; they self-resolve.

**Tailscale pod conflicts:** Tailscale uses `hostNetwork: true` and claims a host-level TUN device (`tailscale0`). If a rolling update gets stuck (old RS holds TUN, new RS can't claim it), scale old ReplicaSets to 0, then delete the stale pod. If the TUN device is still held by a zombie process, the pod must be deleted and rescheduled.

**PV node affinity:** PVCs are pinned to specific nodes via local-path. See `CLAUDE.local.md` for the current PV-to-node map.

**NUC reconnect plan:** See `docs/nuc-reconnect-plan.md` for the full checklist when bringing nodes back online after downtime.

**Pi-hole HA:** Two Pi-hole instances for DNS redundancy. Router DHCPv4 hands out NAS (192.168.1.10) as DNS 1 and cluster (192.168.1.200) as DNS 2. The NAS also serves DNS over IPv6 (`2605:a601:8007:e800::2`). The NAS is preferred by clients (fewer failure modes); the cluster remains the config primary (GitOps-managed, Nebula Sync pushes to NAS every 30 min). Custom DNS records are not synced automatically — update both `k8s/pihole/custom-dns.yaml` and `nas/pihole/custom-dns/02-custom-dns.conf` when adding services. NAS compose files live in `nas/pihole/`. See `docs/pihole-ha.md`.

**Key IPs and network topology:** See `CLAUDE.local.md`.
