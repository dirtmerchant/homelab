#!/bin/bash
# restic-b2-backup.sh — offsite backup from NAS to Backblaze B2 via restic
# Deployed to /usr/local/bin/restic-b2-backup.sh on NAS
# Runs daily at 05:00 via root crontab (after Tier 1 at 03:00 and Tier 2 at 04:00)
#
# Prerequisites:
#   - /volume1/docker/restic/env with B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_PASSWORD, RESTIC_REPOSITORY
#   - restic/restic:0.17.3 Docker image pulled
#   - restic repo initialized: docker run --rm --env-file /volume1/docker/restic/env restic/restic init

set -euo pipefail

LOG="/var/log/restic-backup.log"
ENV_FILE="/volume1/docker/restic/env"
IMAGE="restic/restic:0.17.3"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

log "=== restic B2 backup started ==="

if [ ! -f "$ENV_FILE" ]; then
    log "ERROR: env file not found: $ENV_FILE"
    exit 1
fi

# Run restic backup via Docker
# Mount source directories as read-only
docker run --rm \
    --env-file "$ENV_FILE" \
    -v /volume1/NetBackup/k3s:/data/k3s:ro \
    -v /volume1/homes:/data/homes:ro \
    -v /volume1/PlexMediaServer:/data/plex:ro \
    "$IMAGE" backup \
    /data/k3s \
    /data/homes \
    /data/plex \
    --exclude="*.tmp" \
    --exclude="Cache" \
    --exclude="Crash Reports" \
    --tag "scheduled" \
    >> "$LOG" 2>&1

log "Backup complete, applying retention policy..."

# Apply retention policy: 7 daily, 4 weekly, 6 monthly
docker run --rm \
    --env-file "$ENV_FILE" \
    "$IMAGE" forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune \
    >> "$LOG" 2>&1

log "Retention policy applied"

# Weekly integrity check (Sundays only)
if [ "$(date +%u)" -eq 7 ]; then
    log "Running weekly integrity check..."
    docker run --rm \
        --env-file "$ENV_FILE" \
        "$IMAGE" check \
        >> "$LOG" 2>&1
    log "Integrity check complete"
fi

log "=== restic B2 backup finished ==="
