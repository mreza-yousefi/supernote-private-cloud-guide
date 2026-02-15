#!/bin/bash
# Supernote Private Cloud backup script
# Uses restic (encrypted, incremental, versioned) + rclone (offsite to Google Drive)
#
# Usage:
#   ./cloud-backup.sh           Daily local backup (restic)
#   ./cloud-backup.sh --offsite Weekly offsite sync (rclone to Google Drive)
#
# Schedule via cron:
#   0 3 * * * /path/to/cloud-backup.sh >> /path/to/backup.log 2>&1
#   0 3 * * 6 /path/to/cloud-backup.sh --offsite >> /path/to/backup.log 2>&1
#
# Prerequisites:
#   sudo apt install restic rclone
#   restic init --repo /path/to/restic-repo
#   rclone config  (set up a Google Drive remote)

set -euo pipefail

# --- Configure these for your setup ---
INSTALL_DIR="$HOME/supernote"
RESTIC_REPO="$HOME/backups/supernote-restic"
RESTIC_PASSWORD_FILE="$HOME/backups/.restic-password"
DB_DUMP_DIR="$INSTALL_DIR/db_backup"
GDRIVE_REMOTE="gdrive:supernote-backup"
LOG_FILE="$HOME/backups/backup.log"
MYSQL_ROOT_PASSWORD="CHANGE_ME"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Step 1: Database dump ---
log "Starting MariaDB dump..."
mkdir -p "$DB_DUMP_DIR"
docker exec mariadb mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction supernotedb \
    > "$DB_DUMP_DIR/supernotedb-latest.sql" 2>>"$LOG_FILE"
log "MariaDB dump complete ($(du -sh "$DB_DUMP_DIR/supernotedb-latest.sql" | cut -f1))"

# --- Step 2: Restic backup ---
log "Starting restic backup..."
export RESTIC_REPOSITORY="$RESTIC_REPO"
export RESTIC_PASSWORD_FILE

restic backup \
    "$INSTALL_DIR/supernote_data" \
    "$DB_DUMP_DIR/supernotedb-latest.sql" \
    "$INSTALL_DIR/sndata/recycle" \
    "$INSTALL_DIR/.env" \
    "$INSTALL_DIR/.dbenv" \
    "$INSTALL_DIR/docker-compose.yml" \
    "$INSTALL_DIR/nginx-supernote.conf" \
    --tag supernote \
    2>>"$LOG_FILE"

log "Restic backup complete"

# --- Step 3: Prune old snapshots (keep 30 days) ---
log "Pruning old snapshots..."
restic forget \
    --keep-daily 30 \
    --prune \
    --tag supernote \
    2>>"$LOG_FILE"

log "Prune complete"

# --- Step 4: Offsite sync (only with --offsite flag) ---
if [[ "${1:-}" == "--offsite" ]]; then
    log "Starting offsite sync to Google Drive..."
    rclone sync "$RESTIC_REPO" "$GDRIVE_REMOTE" \
        --transfers 4 \
        --log-file "$LOG_FILE" \
        --log-level INFO
    # Optional: add --bwlimit 125k to limit upload speed
    log "Offsite sync complete"
fi

log "Backup finished successfully"
