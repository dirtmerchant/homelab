# Pi-hole HA Setup

## Architecture

Two Pi-hole instances provide DNS redundancy:

| Instance | Location | IP | Web UI | Role |
|----------|----------|-----|--------|------|
| NAS | Synology NAS (Docker) | 192.168.1.10 | 192.168.1.10:8080 | DNS server 1 (preferred by clients) |
| Cluster | k3s cluster (MetalLB) | 192.168.1.200 | pihole.homelab.bertbullough.com | DNS server 2 (fallback), config primary |

Router DHCP hands out NAS (192.168.1.10) as DNS server 1 and cluster (192.168.1.200) as DNS server 2. The NAS is preferred by clients because it has fewer failure modes (no k8s/MetalLB/PVC dependency). The cluster Pi-hole remains the Nebula Sync config primary — configuration changes are made there (GitOps via ArgoCD) and synced to the NAS every 30 minutes.

Nebula Sync runs as a sidecar container on the NAS and pulls configuration from the cluster Pi-hole via Pi-hole v6's Teleporter API. Custom DNS records are mounted read-only and maintained manually in both locations.

## File Locations

**Cluster (GitOps via ArgoCD):**
- Manifests: `k8s/pihole/`
- Custom DNS: `k8s/pihole/custom-dns.yaml` (ConfigMap)

**NAS (Docker Compose):**
- Compose file: `nas/pihole/docker-compose.yml` (repo) -> `/volume1/docker/pihole/docker-compose.yml` (NAS)
- Custom DNS: `nas/pihole/custom-dns/02-custom-dns.conf` (repo) -> `/volume1/docker/pihole/custom-dns/02-custom-dns.conf` (NAS)
- Secrets: `/volume1/docker/pihole/.env` (NAS only, gitignored)
- Pi-hole data: `/volume1/docker/pihole/etc-pihole/`, `/volume1/docker/pihole/etc-dnsmasq.d/`

## Common Operations

### Adding a DNS record

Update both files — they are not automatically synced (Teleporter doesn't sync dnsmasq.d files):

1. Add the record to `k8s/pihole/custom-dns.yaml` (ConfigMap data section)
2. Add the same record to `nas/pihole/custom-dns/02-custom-dns.conf`
3. Push to `main` (ArgoCD syncs the cluster Pi-hole automatically)
4. Copy the updated file to the NAS and restart the container:
   ```bash
   scp nas/pihole/custom-dns/02-custom-dns.conf nas:/volume1/docker/pihole/custom-dns/
   ssh nas "export PATH=/usr/local/bin:\$PATH && cd /volume1/docker/pihole && docker compose restart pihole"
   ```

### Updating Pi-hole version

Both instances should run the same version for Nebula Sync compatibility:

1. Update the image tag in `k8s/pihole/deployment.yaml`
2. Update the image tag in `nas/pihole/docker-compose.yml`
3. Push to `main` (ArgoCD handles the cluster)
4. Update the NAS:
   ```bash
   scp nas/pihole/docker-compose.yml nas:/volume1/docker/pihole/
   ssh nas "export PATH=/usr/local/bin:\$PATH && cd /volume1/docker/pihole && docker compose pull && docker compose up -d"
   ```

Renovate tracks both images and will create PRs for updates.

### Rotating the Pi-hole password

1. Update the `webpassword` field in the 1Password `pihole` item
2. Restart ESO to sync to the cluster: `kubectl rollout restart deployment/external-secrets -n external-secrets`
3. Restart the cluster Pi-hole: `kubectl rollout restart deployment/pihole -n pihole`
4. Update `/volume1/docker/pihole/.env` on the NAS with the new password
5. Restart NAS containers:
   ```bash
   ssh nas "export PATH=/usr/local/bin:\$PATH && cd /volume1/docker/pihole && docker compose up -d"
   ```

### Checking Nebula Sync status

```bash
ssh nas "export PATH=/usr/local/bin:\$PATH && docker logs nebula-sync --tail 20"
```

### Restarting NAS Pi-hole

```bash
ssh nas "export PATH=/usr/local/bin:\$PATH && cd /volume1/docker/pihole && docker compose restart"
```

### Full redeploy on NAS

```bash
ssh nas "export PATH=/usr/local/bin:\$PATH && cd /volume1/docker/pihole && docker compose down && docker compose pull && docker compose up -d"
```

## Troubleshooting

### NAS Pi-hole not resolving

1. Check container is running: `ssh nas "export PATH=/usr/local/bin:\$PATH && docker ps"`
2. Check Pi-hole logs: `ssh nas "export PATH=/usr/local/bin:\$PATH && docker logs pihole --tail 50"`
3. Test DNS directly: `dig @192.168.1.10 google.com`
4. Check port 53 is listening: `ssh nas "sudo netstat -tlnp | grep ':53 '"`

### Nebula Sync not syncing

1. Check sync logs: `ssh nas "export PATH=/usr/local/bin:\$PATH && docker logs nebula-sync --tail 20"`
2. Verify primary is reachable from NAS: `ssh nas "curl -sk https://pihole.homelab.bertbullough.com/admin/"`
3. Verify passwords match between primary and replica
4. The `CLIENT_SKIP_TLS_VERIFICATION=true` setting is required because the cluster uses a self-signed CA

### Port 53 conflict on NAS

If DhcpServer or another service binds port 53:
```bash
ssh nas "sudo netstat -tlnp | grep ':53 '"
# If DhcpServer is the culprit (router handles DHCP, NAS DhcpServer is unused):
ssh nas "sudo /usr/syno/bin/synopkg stop DhcpServer"
```

### DSM firewall blocking DNS

The NAS firewall must allow port 53 (TCP+UDP) and port 8080 (TCP) from 192.168.1.0/24. After any DSM firewall changes, re-add the iptables DROP rule:
```bash
ssh nas "sudo iptables -A INPUT_FIREWALL -j DROP"
```

## Initial Setup

For reference, here are the steps used for the initial deployment:

1. Start ContainerManager: `ssh nas "sudo /usr/syno/bin/synopkg start ContainerManager"`
2. Create directories:
   ```bash
   ssh nas "mkdir -p /volume1/docker/pihole/{etc-pihole,etc-dnsmasq.d,custom-dns}"
   ```
3. Copy files:
   ```bash
   scp nas/pihole/docker-compose.yml nas:/volume1/docker/pihole/
   scp nas/pihole/custom-dns/02-custom-dns.conf nas:/volume1/docker/pihole/custom-dns/
   ```
4. Create `.env` on the NAS with the real password:
   ```bash
   ssh nas "cat > /volume1/docker/pihole/.env << 'EOF'
   PIHOLE_PASSWORD=<password from 1Password pihole/webpassword>
   EOF"
   ```
5. Start containers:
   ```bash
   ssh nas "export PATH=/usr/local/bin:\$PATH && cd /volume1/docker/pihole && docker compose up -d"
   ```
6. Add DSM firewall rules for ports 53 (TCP+UDP) and 8080 (TCP) from 192.168.1.0/24
7. Re-add iptables DROP: `ssh nas "sudo iptables -A INPUT_FIREWALL -j DROP"`
8. Set router DHCP DNS server 1 to 192.168.1.10 (NAS), DNS server 2 to 192.168.1.200 (cluster)
