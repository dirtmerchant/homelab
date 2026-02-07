# NUC Cluster Initial Setup

3 Intel NUC7i7BNH units running Ubuntu Server 24.04.

## Network

All nodes on wired ethernet (eno1) with static IPs. WiFi disabled.

| Node | IP | Role |
|------|----|------|
| nuc1 | 192.168.1.20 | k3s master |
| nuc2 | 192.168.1.21 | worker |
| nuc3 | 192.168.1.22 | worker |

- Gateway: 192.168.1.1
- DNS: 8.8.8.8, 8.8.4.4
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
- UFW firewall active: SSH (port 22) allowed, all other incoming denied
- Disabled services: ModemManager, wpa_supplicant, multipathd, udisks2

## Access

- User: bert (passwordless sudo via `/etc/sudoers.d/bert`)
- Passwords for bert and root stored in vault
