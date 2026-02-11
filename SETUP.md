# NUC Cluster Setup

3 Intel NUC7i7BNH units running Ubuntu Server 24.04 (32GB RAM, 256GB SSD each).

## Network

All nodes on wired ethernet (eno1) with static IPs. WiFi disabled.

| Node | IP | Role |
|------|----|------|
| nuc1 | 192.168.1.20 | k3s server (control-plane + etcd) |
| nuc2 | 192.168.1.21 | k3s agent (worker) |
| nuc3 | 192.168.1.22 | k3s agent (worker) |

- Gateway: 192.168.1.1
- DNS: 192.168.1.200 (Pi-hole), 8.8.8.8 (fallback)
- Config: `/etc/netplan/50-cloud-init.yaml`

## SSH

Key-only authentication as user "bert" (GitHub keys imported).

Hardening applied via `/etc/ssh/sshd_config.d/99-hardening.conf`:
- PermitRootLogin no
- PasswordAuthentication no
- X11Forwarding no
- MaxAuthTries 3
- LoginGraceTime 30

## System Hardening

- Automatic security updates enabled (unattended-upgrades)
- UFW firewall active: SSH, k3s API (6443), VXLAN (8472/udp), kubelet (10250), etcd (2379-2380), HTTP/HTTPS (80/443)
- Disabled services: ModemManager, wpa_supplicant, multipathd, udisks2
- Swap disabled, LVM root volumes extended to full disk (~230GB)

## k3s Cluster

- Version: v1.34.3+k3s1
- Installed with `--cluster-init --disable traefik --disable servicelb`
- Join token stored on nuc1 at `/var/lib/rancher/k3s/server/node-token`

## MetalLB

- Version: v0.14.9 (L2 mode)
- IP pool: 192.168.1.200–192.168.1.250

## Monitoring

- kube-prometheus-stack (Helm release `monitoring` in `monitoring` namespace)
- Grafana: https://grafana.homelab.bertbullough.com (admin / admin)
- Prometheus: 30d retention, 20Gi storage
- Node exporters on all 3 nodes

## Access

- User: bert (passwordless sudo via `/etc/sudoers.d/bert`)
- Passwords for bert and root stored in vault
- Local kubectl configured at `~/.kube/config`
