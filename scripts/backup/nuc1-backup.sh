#!/bin/bash
# nuc1-backup.sh — backs up etcd snapshots and Prometheus data to NAS
# Deployed to /usr/local/bin/nuc-backup.sh on nuc1
# Runs daily at 04:00 via root crontab

set -euo pipefail

LOG="/var/log/nuc-backup.log"
NAS="bert@192.168.1.10"
NAS_BASE="/volume1/NetBackup/k3s"
RSYNC_OPTS=(-a --delete --rsync-path=/usr/bin/rsync)
STORAGE="/var/lib/rancher/k3s/storage"
METRICS_DIR="/var/lib/node-exporter/textfile_collector"
METRICS_FILE="$METRICS_DIR/nuc_backup.prom"
NODE="nuc1"

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

log "=== nuc1 backup started ==="

# etcd snapshots
ETCD_DIR="/var/lib/rancher/k3s/server/db/snapshots"
if [ -d "$ETCD_DIR" ]; then
    log "Syncing etcd snapshots..."
    rsync "${RSYNC_OPTS[@]}" "$ETCD_DIR/" "$NAS:$NAS_BASE/etcd/" >> "$LOG" 2>&1
    log "etcd sync complete"
else
    log "WARNING: etcd snapshot directory not found: $ETCD_DIR"
fi

# Prometheus data — use glob to find PVC directory
PROM_DIRS=("$STORAGE"/*_monitoring_prometheus-*)
if [ -d "${PROM_DIRS[0]}" ]; then
    log "Syncing Prometheus data..."
    rsync "${RSYNC_OPTS[@]}" "${PROM_DIRS[0]}/" "$NAS:$NAS_BASE/prometheus/" >> "$LOG" 2>&1
    log "Prometheus sync complete"
else
    log "WARNING: Prometheus PVC directory not found"
fi

log "=== nuc1 backup finished ==="

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
