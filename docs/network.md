# Home Network Documentation

## Network Overview

Single flat LAN on 192.168.1.0/24. Router at 192.168.1.1 provides NAT and DHCP. No VLANs currently configured. Dual Pi-hole instances provide DNS redundancy: NAS (192.168.1.10) as DNS 1, cluster (192.168.1.200) as DNS 2. Router DHCP hands out both.

## Devices

### Router/Gateway — 192.168.1.1

Default gateway and DHCP server. DHCP hands out DNS 1: 192.168.1.10 (NAS Pi-hole) and DNS 2: 192.168.1.200 (cluster Pi-hole). No ports forwarded to internal devices (NAS, cluster, etc. are LAN-only).

### Managed Switch — 192.168.1.2

TP-Link T1600G-28TS V3. Managed switch connecting the NUC cluster and NAS. Web UI at `http://192.168.1.2`. SSH access: `ssh switch`. Factory reset recovery documented in `docs/tplink-t1600g-recovery.md`.

### k3s Cluster — 192.168.1.20–22

Three Intel NUC7i7BNH nodes (32GB RAM, 256GB SSD each) running Ubuntu Server 24.04 and k3s.

| Node | IP | Role |
|------|------|------|
| nuc1 | 192.168.1.20 | k3s server (control-plane + etcd) |
| nuc2 | 192.168.1.21 | k3s agent (worker) |
| nuc3 | 192.168.1.22 | k3s agent (worker) |

SSH access: key-only, passwordless sudo. Kubeconfig at `~/.kube/config` on local Mac.

**Cluster services (managed by ArgoCD GitOps from `k8s/`):**

| Service | Access | Notes |
|---------|--------|-------|
| ArgoCD | argocd.homelab.bertbullough.com | GitOps controller, app-of-apps pattern |
| Traefik | 192.168.1.202 (LoadBalancer) | Ingress controller, wildcard TLS via cert-manager |
| Pi-hole | 192.168.1.200 (LoadBalancer) + pihole.homelab.bertbullough.com | Primary DNS server (HA pair with NAS replica) |
| Grafana | grafana.homelab.bertbullough.com | Monitoring dashboards (Prometheus + Alertmanager backend) |
| Home Assistant | hass.homelab.bertbullough.com | Home automation |
| Ollama | — | LLM inference |
| Longhorn | — | Distributed storage |
| Tailscale | — | VPN mesh (cluster pod, not on NAS) |
| cert-manager | — | TLS certificate management |
| MetalLB | 192.168.1.200–250 pool | L2 load balancer for cluster services |

### Synology NAS (DS218+) — 192.168.1.10

SSH access: `ssh nas` (key-only, passwordless sudo). DSM web UI at `https://192.168.1.10:5001`. DSM 7.2.2.

**Hardware:** Intel Celeron J3355 @ 2.00GHz, 6GB RAM, 2x HDD in RAID 1, 11T usable volume.

**External storage:** 15T USB drive (backup destination).

**Key services:** Plex, Synology Drive, Synology Photos, FileStation, ContainerManager (running), Pi-hole secondary (Docker, DNS on port 53, web UI on port 8080).

**Backups:** Nightly rsync mirror to external USB drive. Backs up video, homes, and Plex config.

## DNS

Dual Pi-hole setup for high availability:

| Instance | IP | Location | Web UI |
|----------|-----|----------|--------|
| Primary | 192.168.1.200 | k3s cluster (MetalLB) | pihole.homelab.bertbullough.com |
| Secondary | 192.168.1.10 | Synology NAS (Docker) | 192.168.1.10:8080 |

Router DHCP hands out NAS as DNS 1 and cluster as DNS 2. The NAS is preferred by clients because it has fewer failure modes (no k8s/MetalLB dependency). The cluster Pi-hole remains the config primary — changes are made there (GitOps via ArgoCD) and synced to the NAS via Nebula Sync every 30 minutes. Custom DNS records are maintained separately in both instances (not synced by Nebula Sync).

Internal hostnames resolve via dnsmasq custom records in `k8s/pihole/custom-dns.yaml` (cluster) and `nas/pihole/custom-dns/02-custom-dns.conf` (NAS). All hostnames route through Traefik (192.168.1.202) which handles TLS termination with a wildcard cert (self-signed CA via cert-manager).

See `docs/pihole-ha.md` for setup, maintenance, and troubleshooting.

## IP Address Map

| IP | Device/Service |
|------|----------------|
| 192.168.1.1 | Router/gateway |
| 192.168.1.2 | TP-Link T1600G-28TS managed switch |
| 192.168.1.20 | nuc1 (k3s control-plane) |
| 192.168.1.21 | nuc2 (k3s worker) |
| 192.168.1.22 | nuc3 (k3s worker) |
| 192.168.1.10 | Synology DS218+ NAS |
| 192.168.1.200 | Pi-hole DNS (MetalLB) |
| 192.168.1.202 | Traefik ingress (MetalLB) |
| 192.168.1.200–250 | MetalLB L2 address pool |

## Security Posture

**Network perimeter:** Router NAT, no port forwarding to internal devices. All services are LAN-only except Plex (port 32400 allowed from any in NAS firewall for Plex remote access).

**NAS (hardened 2026-06-06):**
- SSH: key-only, no root login, no password auth
- SMB: no guest access, minimum protocol SMB2
- Firewall: iptables allow-list (SSH/DSM/SMB from LAN, Plex from any, deny all)
- Default admin account disabled
- EOL software removed

**Cluster:**
- Pod security standards enforced per-namespace (baseline enforce, restricted warn/audit)
- NetworkPolicies on most services restricting ingress
- Traefik security headers middleware (HSTS, frame-deny, XSS protection)
- TLS on all ingress routes

**SSH:** All access key-only via 1Password SSH agent. No private keys on disk.
