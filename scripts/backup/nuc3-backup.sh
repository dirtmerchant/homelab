#!/bin/bash
# nuc3-backup.sh — backs up Home Assistant and Pi-hole data to NAS
# Deployed to /usr/local/bin/nuc-backup.sh on nuc3
# Runs daily at 04:00 via root crontab

set -euo pipefail

LOG="/var/log/nuc-backup.log"
NAS="bert@192.168.1.10"
NAS_BASE="/volume1/NetBackup/k3s"
RSYNC_OPTS=(-a --delete --rsync-path=/usr/bin/rsync)
STORAGE="/var/lib/rancher/k3s/storage"
METRICS_DIR="/var/lib/node-exporter/textfile_collector"
METRICS_FILE="$METRICS_DIR/nuc_backup.prom"
NODE="nuc3"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

write_failure_metrics() {
    cat > "$METRICS_DIR/nuc_backup.$$.prom" <<PROM
# HELP nuc_backup_success Whether the last backup succeeded (1=success, 0=failure).
# TYPE nuc_backup_success gauge
nuc_backup_success{node="$NODE"} 0
PROM
    mv "$METRICS_DIR/nuc_backup.$$.prom" "$METRICS_FILE"
}

trap write_failure_metrics ERR

log "=== nuc3 backup started ==="

# Home Assistant config
HA_DIRS=("$STORAGE"/*_homeassistant_homeassistant-config)
if [ -d "${HA_DIRS[0]}" ]; then
    log "Syncing Home Assistant config..."
    rsync "${RSYNC_OPTS[@]}" "${HA_DIRS[0]}/" "$NAS:$NAS_BASE/homeassistant/" >> "$LOG" 2>&1
    log "Home Assistant sync complete"
else
    log "WARNING: Home Assistant PVC directory not found"
fi

# Pi-hole config
PIHOLE_CFG_DIRS=("$STORAGE"/*_pihole_pihole-config)
if [ -d "${PIHOLE_CFG_DIRS[0]}" ]; then
    log "Syncing Pi-hole config..."
    rsync "${RSYNC_OPTS[@]}" "${PIHOLE_CFG_DIRS[0]}/" "$NAS:$NAS_BASE/pihole/config/" >> "$LOG" 2>&1
    log "Pi-hole config sync complete"
else
    log "WARNING: Pi-hole config PVC directory not found"
fi

# Pi-hole dnsmasq
PIHOLE_DNS_DIRS=("$STORAGE"/*_pihole_pihole-dnsmasq)
if [ -d "${PIHOLE_DNS_DIRS[0]}" ]; then
    log "Syncing Pi-hole dnsmasq..."
    rsync "${RSYNC_OPTS[@]}" "${PIHOLE_DNS_DIRS[0]}/" "$NAS:$NAS_BASE/pihole/dnsmasq/" >> "$LOG" 2>&1
    log "Pi-hole dnsmasq sync complete"
else
    log "WARNING: Pi-hole dnsmasq PVC directory not found"
fi

log "=== nuc3 backup finished ==="

# Write success metrics
cat > "$METRICS_DIR/nuc_backup.$$.prom" <<PROM
# HELP nuc_backup_success Whether the last backup succeeded (1=success, 0=failure).
# TYPE nuc_backup_success gauge
nuc_backup_success{node="$NODE"} 1
# HELP nuc_backup_last_success_timestamp_seconds Unix timestamp of last successful backup.
# TYPE nuc_backup_last_success_timestamp_seconds gauge
nuc_backup_last_success_timestamp_seconds{node="$NODE"} $(date +%s)
PROM
mv "$METRICS_DIR/nuc_backup.$$.prom" "$METRICS_FILE"
