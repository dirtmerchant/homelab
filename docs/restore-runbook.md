# Restore Runbook

Scenarios ordered from lightest to heaviest. Always start with the lightest applicable procedure.

## 1. Single PVC Data Restore

Use when a workload's data is corrupted or accidentally deleted but the cluster is healthy.

### Option A: Restore from Longhorn snapshot

1. Open the Longhorn UI (port-forward or ingress)
2. Find the volume attached to the affected PVC
3. Scale down the workload: `kubectl scale deployment/<name> -n <ns> --replicas=0`
4. In Longhorn UI, select the volume → Snapshots → Revert to desired snapshot
5. Scale up: `kubectl scale deployment/<name> -n <ns> --replicas=1`
6. Verify the workload is running with the restored data

### Option B: Restore from NAS backup

1. Identify the PVC's local-path directory:
   ```bash
   kubectl get pv -o jsonpath='{range .items[*]}{.spec.claimRef.name}{"\t"}{.spec.local.path}{"\t"}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}{end}'
   ```
2. Scale down the workload: `kubectl scale deployment/<name> -n <ns> --replicas=0`
3. SSH to the node where the PV resides and rsync from NAS:
   ```bash
   # Example for Home Assistant on nuc3:
   ssh nuc3
   sudo rsync -a bert@192.168.1.10:/volume1/NetBackup/k3s/homeassistant/ /var/lib/rancher/k3s/storage/<pvc-dir>/
   ```
4. Scale up: `kubectl scale deployment/<name> -n <ns> --replicas=1`
5. Verify the workload is running with the restored data

### Option C: Restore from B2 offsite backup

See [Section 6: Offsite Restore from B2](#6-offsite-restore-from-b2).

## 2. Single Node Recovery

Use when a NUC needs OS reinstall (disk failure, corruption) but other nodes are healthy.

### 2a. Server node (nuc1 — control plane)

1. Install Ubuntu Server 24.04 on the replacement disk
2. Configure static IP 192.168.1.20, hostname `nuc1`
3. Add SSH public key from 1Password ("Homelab SSH Key") to `~/.ssh/authorized_keys`
4. Configure passwordless sudo
5. Disable Bluetooth and WiFi kernel modules (see CLAUDE.md hardening notes)
6. Install k3s as server:
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.34.3+k3s1" sh -s - server \
       --cluster-init
   ```
7. Join existing agents: On nuc2 and nuc3, update `/etc/rancher/k3s/config.yaml` to point to the new server token if changed
8. Restore etcd from snapshot if needed:
   ```bash
   sudo k3s server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-file>
   ```
9. Restore PVC data for nuc1-pinned volumes (Prometheus):
   ```bash
   sudo rsync -a bert@192.168.1.10:/volume1/NetBackup/k3s/prometheus/ /var/lib/rancher/k3s/storage/<prometheus-pvc-dir>/
   ```
10. Redeploy backup script:
    ```bash
    cat scripts/backup/nuc1-backup.sh | ssh nuc1 "sudo tee /usr/local/bin/nuc-backup.sh > /dev/null && sudo chmod +x /usr/local/bin/nuc-backup.sh"
    ```
11. Recreate root crontab entry: `0 4 * * * /usr/local/bin/nuc-backup.sh`
12. Create textfile collector directory:
    ```bash
    ssh nuc1 "sudo mkdir -p /var/lib/node-exporter/textfile_collector"
    ```
13. Generate root SSH key for NAS backups and add to NAS `authorized_keys`
14. Configure k3s registries.yaml for NAS Docker registry mirror

### 2b. Agent node (nuc2 or nuc3)

1. Install Ubuntu Server 24.04, configure static IP and hostname
2. Add SSH public key, configure passwordless sudo
3. Disable Bluetooth and WiFi kernel modules
4. Get the k3s join token from nuc1: `sudo cat /var/lib/rancher/k3s/server/node-token`
5. Install k3s as agent:
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.34.3+k3s1" \
       K3S_URL=https://192.168.1.20:6443 K3S_TOKEN=<token> sh -s - agent
   ```
6. Restore PVC data for this node's volumes (see PV Node Affinity Map in CLAUDE.local.md)
7. For nuc3 only — redeploy backup script:
    ```bash
    cat scripts/backup/nuc3-backup.sh | ssh nuc3 "sudo tee /usr/local/bin/nuc-backup.sh > /dev/null && sudo chmod +x /usr/local/bin/nuc-backup.sh"
    ```
8. Create textfile collector directory and root crontab entry (nuc3 only)
9. Generate root SSH key for NAS backups and add to NAS `authorized_keys`
10. Configure k3s registries.yaml for NAS Docker registry mirror

## 3. ArgoCD Re-Bootstrap

Use when ArgoCD is broken but the cluster itself is running.

1. Create the ESO bootstrap secret (if not present):
   ```bash
   kubectl create namespace external-secrets
   kubectl create secret generic onepassword-service-account \
       -n external-secrets \
       --from-literal=token='<1password-service-account-token>'
   ```
   Retrieve the token from 1Password → Homelab vault → "1Password Service Account".

2. Create the ArgoCD repo secret (for initial bootstrap only):
   ```bash
   kubectl create namespace argocd
   kubectl create secret generic homelab-repo -n argocd \
       --from-literal=type=git \
       --from-literal=url=https://github.com/dirtmerchant/homelab.git \
       --from-literal=username=dirtmerchant \
       --from-literal=password='<github-pat>'
   kubectl label secret homelab-repo -n argocd argocd.argoproj.io/secret-type=repository
   ```
   Retrieve the PAT from 1Password → Homelab vault → "argocd-repo" → password field.

3. Install ArgoCD (Helm):
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install argocd argo/argo-cd -n argocd --create-namespace
   ```

4. Apply the root application:
   ```bash
   kubectl apply -f k8s/argocd/apps/root.yaml
   ```

5. ArgoCD will auto-sync all applications from `k8s/argocd/apps/`. Wait for sync waves to complete in order (-3 through 2).

6. Once ESO is running, it takes over management of the `homelab-repo` secret and all other ESO-managed secrets.

## 4. Full Cluster Restore

Use after catastrophic failure of all 3 NUCs. Requires NAS backup data.

1. **Rebuild all 3 NUCs** — follow Section 2 for each node, starting with nuc1 (server)
2. **Wait for nuc1 to be ready**: `kubectl get nodes` should show nuc1 Ready
3. **Join agents**: Install k3s agent on nuc2 and nuc3 (Section 2b)
4. **Verify all nodes**: `kubectl get nodes` — all 3 should be Ready
5. **Bootstrap ArgoCD** — follow Section 3
6. **Wait for all apps to sync** — watch ArgoCD UI or `kubectl get applications -n argocd`
7. **Restore PVC data** for all workloads (see Section 1, Option B):
   - nuc1: Prometheus data
   - nuc3: Home Assistant config, Pi-hole config + dnsmasq
8. **Restart workloads** that use PVCs:
   ```bash
   kubectl rollout restart deployment -n monitoring
   kubectl rollout restart deployment -n homeassistant
   kubectl rollout restart deployment -n pihole
   ```
9. **Redeploy backup scripts** to nuc1 and nuc3 (see Maintenance section in backup-plan.md)
10. **Create textfile collector directories** on all 3 NUCs:
    ```bash
    for nuc in nuc1 nuc2 nuc3; do
        ssh $nuc "sudo mkdir -p /var/lib/node-exporter/textfile_collector"
    done
    ```
11. **Verify** — run through the [Verification Checklist](#7-verification-checklist)

## 5. Secret Re-Creation

All secrets except the ESO bootstrap are managed by External Secrets Operator. If ESO is running, secrets will be auto-synced from 1Password.

### Manual bootstrap secret

```bash
kubectl create secret generic onepassword-service-account \
    -n external-secrets \
    --from-literal=token='<1password-service-account-token>'
```

### ESO-managed secrets

Once ESO is running with the bootstrap secret, these are created automatically:

| Secret | Namespace | 1Password Item | Fields |
|--------|-----------|----------------|--------|
| `pihole-secret` | pihole | `pihole` | `webpassword` |
| `tailscale-auth` | tailscale | `tailscale` | `TS_AUTHKEY` |
| `grafana-admin-secret` | monitoring | `grafana` | `admin-user`, `admin-password` |
| `traefik-dashboard-auth` | traefik | `traefik` | `users` (htpasswd) |
| `homelab-repo` | argocd | `argocd-repo` | `type`, `repo-url`, `username`, `password` |

If a secret is missing and ESO is running, check:

```bash
# Check ExternalSecret status
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <ns>

# Restart ESO if needed (clears SDK cache)
kubectl rollout restart deployment/external-secrets -n external-secrets
```

## 6. Offsite Restore from B2

Use when NAS and USB backups are both unavailable (theft, fire, ransomware).

1. Retrieve B2 credentials and restic passphrase from 1Password → Homelab vault
2. Create an env file with `B2_ACCOUNT_ID`, `B2_ACCOUNT_KEY`, `RESTIC_PASSWORD`, and `RESTIC_REPOSITORY=b2:homelab-offsite-backup`
3. List available snapshots:
   ```bash
   docker run --rm --env-file env restic/restic:0.17.3 snapshots
   ```
4. Restore to a local directory:
   ```bash
   # Full restore
   docker run --rm --env-file env \
       -v /path/to/restore:/restore \
       restic/restic:0.17.3 restore latest --target /restore

   # Restore only k3s backups
   docker run --rm --env-file env \
       -v /path/to/restore:/restore \
       restic/restic:0.17.3 restore latest --target /restore --include /data/k3s

   # Restore a specific snapshot
   docker run --rm --env-file env \
       -v /path/to/restore:/restore \
       restic/restic:0.17.3 restore <snapshot-id> --target /restore
   ```
5. Restored data will be under `/path/to/restore/data/` with subdirectories `k3s/`, `homes/`, `plex/`
6. Copy restored k3s backup data to the appropriate NUC nodes and follow the PVC restore procedures in Section 1

## 7. Verification Checklist

Run through this checklist after any restore procedure to confirm the cluster is healthy.

```bash
# Nodes
kubectl get nodes
# All 3 should be Ready

# System pods
kubectl get pods -n kube-system
# All should be Running/Completed

# All workloads
kubectl get pods -A
# Check for CrashLoopBackOff, ImagePullBackOff, Pending

# ArgoCD sync status
kubectl get applications -n argocd
# All should be Synced and Healthy

# DNS — test from workstation
nslookup homeassistant.homelab.bertbullough.com 192.168.1.200
nslookup homeassistant.homelab.bertbullough.com 192.168.1.10

# Ingress — test a service
curl -sk https://homeassistant.homelab.bertbullough.com

# TLS certificate
echo | openssl s_client -connect 192.168.1.202:443 -servername homeassistant.homelab.bertbullough.com 2>/dev/null | openssl x509 -noout -dates

# Monitoring
kubectl get servicemonitors -A
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# Open http://localhost:9090 and check targets

# Backup metrics (after first backup run)
kubectl exec -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 -- \
    promtool query instant http://localhost:9090 'nuc_backup_success'

# Longhorn
kubectl get volumes -n longhorn-system
# All should be Healthy/Attached

# External Secrets
kubectl get externalsecrets -A
# All should be SecretSynced
```
