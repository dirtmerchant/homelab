# Backup Plan

## Current State (as of 2026-06-13)

### Tier 1: NAS to USB (automated)

**Script:** `/usr/local/bin/backup.sh` on NAS, runs daily at 03:00 via cron.

Syncs video, homes, Plex metadata, and k3s cluster backups from NAS internal storage to external USB drive:

| Source | Destination | Notes |
|--------|-------------|-------|
| `/volume1/video/` | `/volumeUSB1/usbshare/backups/video/` | Plex media library |
| `/volume1/homes/` | `/volumeUSB1/usbshare/backups/homes/` | User home dirs (Drive, Photos, .ssh) |
| `/volume1/PlexMediaServer/` | `/volumeUSB1/usbshare/backups/plex/` | Plex config (excludes Cache, Crash Reports) |
| `/volume1/NetBackup/k3s/` | `/volumeUSB1/usbshare/backups/k3s/` | k3s cluster backups (etcd, HA, Pi-hole, Prometheus) |

Log: `/var/log/backup.log`. USB drive is NTFS — rsync works but cannot preserve Unix permissions or symlinks.

### Tier 2: k3s Cluster to NAS (automated)

**Scripts:** `/usr/local/bin/nuc-backup.sh` on nuc1 and nuc3, run daily at 04:00 via root crontab. Source scripts version-controlled in `scripts/backup/`.

**nuc1** backs up:

| Data | Source Path | NAS Destination |
|------|-------------|-----------------|
| etcd snapshots | `/var/lib/rancher/k3s/server/db/snapshots/` | `/volume1/NetBackup/k3s/etcd/` |
| Prometheus data | `/var/lib/rancher/k3s/storage/*_monitoring_prometheus-*` | `/volume1/NetBackup/k3s/prometheus/` |

**nuc3** backs up:

| Data | Source Path | NAS Destination |
|------|-------------|-----------------|
| Home Assistant config | `/var/lib/rancher/k3s/storage/*_homeassistant_homeassistant-config` | `/volume1/NetBackup/k3s/homeassistant/` |
| Pi-hole config | `/var/lib/rancher/k3s/storage/*_pihole_pihole-config` | `/volume1/NetBackup/k3s/pihole/config/` |
| Pi-hole dnsmasq | `/var/lib/rancher/k3s/storage/*_pihole_pihole-dnsmasq` | `/volume1/NetBackup/k3s/pihole/dnsmasq/` |

PVC paths use glob patterns (not hardcoded UUIDs) so they survive PVC recreation. Ollama PVC (nuc2) is excluded — models are re-downloadable.

**SSH setup:** Root SSH keys on nuc1/nuc3 authenticate as `bert@192.168.1.10` (NAS). Keys added to `/var/services/homes/bert/.ssh/authorized_keys`. Scripts use `--rsync-path=/usr/bin/rsync` because Synology's non-interactive SSH sessions have a restricted PATH.

**Backup metrics:** Both scripts write Prometheus metrics to `/var/lib/node-exporter/textfile_collector/nuc_backup.prom` using an atomic write pattern (write to temp file, then `mv`). Metrics include `nuc_backup_success` (1/0) and `nuc_backup_last_success_timestamp_seconds`. An ERR trap writes failure metrics if the script exits with an error. These metrics are scraped by node-exporter's textfile collector and used by PrometheusRule alerts (BackupStale, BackupFailed, BackupMetricMissing).

**Schedule:** NUCs push at 04:00, NAS cascades to USB at 03:00. On the first day, NAS→USB won't include k3s data (NUCs haven't pushed yet). After day one, the cascade picks up the previous day's k3s backups.

**Logs:** `/var/log/nuc-backup.log` on nuc1 and nuc3.

### Tier 3: Offsite to Backblaze B2 (automated)

**Script:** `/usr/local/bin/restic-b2-backup.sh` on NAS, runs daily at 05:00 via root crontab. Source script version-controlled in `scripts/backup/`.

Backs up critical NAS data to Backblaze B2 using restic in Docker for encrypted, deduplicated, incremental backups.

**What's backed up:**

| Source | Mount in container | Notes |
|--------|-------------------|-------|
| `/volume1/NetBackup/k3s/` | `/data/k3s` | k3s cluster backups (etcd, HA, Pi-hole, Prometheus) |
| `/volume1/homes/` | `/data/homes` | User home dirs (Drive, Photos, .ssh) |
| `/volume1/PlexMediaServer/` | `/data/plex` | Plex config (excludes Cache, Crash Reports) |

**Excludes:** `*.tmp`, `Cache`, `Crash Reports`

**Retention policy:** 7 daily, 4 weekly, 6 monthly snapshots. Applied automatically after each backup run.

**Integrity check:** Weekly on Sundays — restic verifies repository integrity and data checksums.

**Cost estimate:** ~$1.54/mo based on ~257 GB initial upload ($0.006/GB/month storage). Incremental daily uploads are minimal. Download (restore) is $0.01/GB.

**Setup requirements:**

1. Create a Backblaze B2 bucket `homelab-offsite-backup` (private, SSE-B2 encryption)
2. Create an application key scoped to that bucket
3. Store credentials in 1Password Homelab vault:
   - `B2_ACCOUNT_ID` — Backblaze key ID
   - `B2_ACCOUNT_KEY` — Backblaze application key
   - `RESTIC_PASSWORD` — restic encryption passphrase (generate a strong random passphrase)
4. Create env file on NAS:
   ```bash
   sudo mkdir -p /volume1/docker/restic
   # Write env file with B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_PASSWORD,
   # and RESTIC_REPOSITORY=b2:homelab-offsite-backup
   sudo chmod 700 /volume1/docker/restic
   sudo chmod 600 /volume1/docker/restic/env
   ```
5. Pull restic image and initialize repo:
   ```bash
   sudo docker pull restic/restic:0.17.3
   sudo docker run --rm --env-file /volume1/docker/restic/env restic/restic:0.17.3 init
   ```
6. Deploy script and add cron entry:
   ```bash
   cat scripts/backup/restic-b2-backup.sh | ssh nas "sudo tee /usr/local/bin/restic-b2-backup.sh > /dev/null"
   ssh nas "sudo chmod +x /usr/local/bin/restic-b2-backup.sh"
   # Add to root crontab: 0 5 * * * /usr/local/bin/restic-b2-backup.sh
   ```

**Restore from B2:**

```bash
# List available snapshots
docker run --rm --env-file /volume1/docker/restic/env restic/restic:0.17.3 snapshots

# Restore specific snapshot to a target directory
docker run --rm \
    --env-file /volume1/docker/restic/env \
    -v /volume1/restore:/restore \
    restic/restic:0.17.3 restore <snapshot-id> --target /restore

# Restore specific path from latest snapshot
docker run --rm \
    --env-file /volume1/docker/restic/env \
    -v /volume1/restore:/restore \
    restic/restic:0.17.3 restore latest --target /restore --include /data/k3s
```

**Log:** `/var/log/restic-backup.log` on NAS.

### Longhorn Volume Snapshots

Longhorn takes automatic snapshots of all volumes every 12 hours (midnight and noon), retaining the 5 most recent. Managed by the `snapshot-12h` RecurringJob in `k8s/longhorn/recurring-snapshots.yaml`.

These provide fast, in-cluster point-in-time recovery for individual volumes without needing to restore from NAS or B2. Revert via the Longhorn UI or CLI.

### Not Backed Up

| Data | Location | Reason |
|------|----------|--------|
| Ollama models | nuc2 | Re-downloadable from upstream |

## Backup Monitoring

Backup scripts on nuc1 and nuc3 export Prometheus metrics via node-exporter's textfile collector. Three alerts fire in Prometheus:

| Alert | Condition | Severity |
|-------|-----------|----------|
| BackupStale | No successful backup for >26 hours | warning |
| BackupFailed | Last backup run exited with error | critical |
| BackupMetricMissing | Metrics not reported for 30+ minutes | warning |

Alerts are defined in `k8s/monitoring/values.yaml` under `additionalPrometheusRulesMap`.

## NAS Storage Summary

### Internal Storage (/volume1, 11TB SHR, 1.8TB used)

| Directory | Size | Description |
|-----------|------|-------------|
| homes/bert/Drive | 220GB | Synology Drive data |
| homes/bert/Photos | 28GB | Synology Photos library |
| video | 1.5TB | Plex media library (movies, TV, home video, music videos) |
| PlexMediaServer | 5.5GB | Plex metadata and config |
| homes (total) | 251GB | All user home dirs (admin, amber, bert, plex, tina) |
| NetBackup/k3s | ~900MB | k3s cluster backups (etcd, HA, Pi-hole, Prometheus) |

### External USB Drive (/volumeUSB1/usbshare, 15TB NTFS)

All backups in `/volumeUSB1/usbshare/backups/`:

| Directory | Contents |
|-----------|----------|
| homes/ | Mirror of `/volume1/homes/` |
| video/ | Mirror of `/volume1/video/` |
| plex/ | Plex metadata (excludes Cache, Crash Reports) |
| k3s/ | Mirror of `/volume1/NetBackup/k3s/` |

## Maintenance

**Redeploying backup scripts:** After editing `scripts/backup/nuc{1,3}-backup.sh`, copy to the target NUC:

```bash
cat scripts/backup/nuc1-backup.sh | ssh nuc1 "sudo tee /usr/local/bin/nuc-backup.sh > /dev/null"
cat scripts/backup/nuc3-backup.sh | ssh nuc3 "sudo tee /usr/local/bin/nuc-backup.sh > /dev/null"
```

**Redeploying restic script:** After editing `scripts/backup/restic-b2-backup.sh`:

```bash
cat scripts/backup/restic-b2-backup.sh | ssh nas "sudo tee /usr/local/bin/restic-b2-backup.sh > /dev/null"
```

**Checking backup health:**

```bash
# NUC logs
ssh nuc1 "sudo tail -20 /var/log/nuc-backup.log"
ssh nuc3 "sudo tail -20 /var/log/nuc-backup.log"

# NAS logs
ssh nas "tail -20 /var/log/backup.log"
ssh nas "tail -20 /var/log/restic-backup.log"

# Verify data on NAS
ssh nas "du -sh /volume1/NetBackup/k3s/*"

# Verify cron entries
ssh nuc1 "sudo crontab -l"
ssh nuc3 "sudo crontab -l"

# Check restic snapshots
ssh nas "sudo docker run --rm --env-file /volume1/docker/restic/env restic/restic:0.17.3 snapshots"

# Check Prometheus backup metrics
kubectl exec -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 -- \
    promtool query instant http://localhost:9090 'nuc_backup_success'
```

**If PVCs are recreated** (new UUIDs after PV deletion/recreation): No action needed — scripts use glob patterns that match by namespace and PVC name, not UUID.
