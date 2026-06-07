# Backup Plan

## Current State (as of 2026-06-07)

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

**Schedule:** NUCs push at 04:00, NAS cascades to USB at 03:00. On the first day, NAS→USB won't include k3s data (NUCs haven't pushed yet). After day one, the cascade picks up the previous day's k3s backups.

**Logs:** `/var/log/nuc-backup.log` on nuc1 and nuc3.

### Not Backed Up

| Data | Location | Reason |
|------|----------|--------|
| Ollama models | nuc2 | Re-downloadable from upstream |

### Tier 3: Offsite (not yet implemented)

**Goal:** Protect against NAS failure, theft, fire, ransomware.

**Options:**
- **Backblaze B2 + restic**: Cheapest cloud storage ($6/TB/mo). restic provides encryption, deduplication, and incremental backups. Back up `/volume1/NetBackup/` and `/volume1/homes/` to B2.
- **Synology Cloud Sync**: Built-in DSM package, supports Backblaze B2, S3, Google Drive. Simpler setup but less flexible.
- **Second NAS at another location**: Most robust, most expensive.

**Priority:** Not urgent. Tier 1 and 2 cover the most likely failure modes (disk failure, node failure). Offsite covers catastrophic scenarios.

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

**Checking backup health:**

```bash
# NUC logs
ssh nuc1 "sudo tail -20 /var/log/nuc-backup.log"
ssh nuc3 "sudo tail -20 /var/log/nuc-backup.log"

# NAS log
ssh nas "tail -20 /var/log/backup.log"

# Verify data on NAS
ssh nas "du -sh /volume1/NetBackup/k3s/*"

# Verify cron entries
ssh nuc1 "sudo crontab -l"
ssh nuc3 "sudo crontab -l"
```

**If PVCs are recreated** (new UUIDs after PV deletion/recreation): No action needed — scripts use glob patterns that match by namespace and PVC name, not UUID.
