#!/bin/bash
# Supernote Private Cloud backup script
# Schedule via cron, e.g.: 0 3 * * * /path/to/cloud-backup.sh
#
# Configure these paths for your setup:
BACKUP_DIR="/mnt/your-nas/supernote-backup"
INSTALL_DIR="$HOME/supernote"
MYSQL_ROOT_PASSWORD="YOUR_ROOT_PASSWORD"

# Database dump with timestamp
mkdir -p "$INSTALL_DIR/db_backup"
docker exec mariadb mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" supernotedb \
  > "$INSTALL_DIR/db_backup/supernotedb-$(date +%Y%m%d).sql"

# Sync files to backup destination
rsync -a "$INSTALL_DIR/supernote_data/" "$BACKUP_DIR/files/"
rsync -a "$INSTALL_DIR/db_backup/" "$BACKUP_DIR/db_backup/"
