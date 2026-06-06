# Cluster Setup

3 Intel NUC7i7BNH units running Ubuntu Server 24.04 (32GB RAM, 256GB SSD each).

## Network

All nodes on wired ethernet with static IPs. WiFi disabled.

| Node | Role |
|------|------|
| nuc1 | k3s server (control-plane + etcd) |
| nuc2 | k3s agent (worker) |
| nuc3 | k3s agent (worker) |

Static IP configuration via Netplan. Each node gets a fixed address on the LAN subnet.

## SSH

Key-only authentication (GitHub keys imported). Password auth disabled.

Hardening applied via `/etc/ssh/sshd_config.d/99-hardening.conf`:
- PermitRootLogin no
- PasswordAuthentication no
- X11Forwarding no
- MaxAuthTries 3
- LoginGraceTime 30

## System Hardening

- Automatic security updates enabled (unattended-upgrades)
- UFW firewall active: allows SSH, k3s API (6443), VXLAN (8472/udp), kubelet (10250), etcd (2379-2380), HTTP/HTTPS (80/443)
- Disabled unnecessary services: ModemManager, wpa_supplicant, multipathd, udisks2
- Swap disabled, LVM root volumes extended to full disk (~230GB)

## k3s Cluster

- Installed with `--cluster-init --disable traefik --disable servicelb`
- Built-in Traefik and ServiceLB disabled in favor of our own Traefik deployment and MetalLB
- Agent nodes join using the server's node token

## MetalLB

- L2 mode with a reserved IP pool on the LAN subnet
- See `k8s/metallb/` for pool and L2 advertisement configuration

## Monitoring

- kube-prometheus-stack deployed via Helm (ArgoCD-managed)
- Grafana exposed via Traefik IngressRoute
- Prometheus: 30d retention, 20Gi storage
- Node exporters on all nodes

## Access

- SSH key-only, passwordless sudo
- Local kubectl configured at `~/.kube/config`
- All service UIs accessible via Traefik hostnames (see `k8s/pihole/custom-dns.yaml` for DNS entries)
