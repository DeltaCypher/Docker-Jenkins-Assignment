#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  mysql_backup_s3.sh  –  MySQL Backup + S3 Upload Script
#
#  What this script does:
#   1. Dumps the MySQL database to a compressed .sql.gz file
#   2. Names the file with date+time so backups don't overwrite
#   3. Uploads the file to your S3 bucket
#   4. Deletes local backup files older than N days
#   5. Logs every action with timestamp
#
#  Prerequisites on your VM:
#    sudo apt install mysql-client awscli -y
#    aws configure        ← enter your AWS access key + secret
#
#  Usage:
#    chmod +x mysql_backup_s3.sh
#    ./mysql_backup_s3.sh                 # backup all settings from config
#    ./mysql_backup_s3.sh myapp_db        # backup a specific database
#
#  Schedule (add to crontab for daily 2 AM backup):
#    crontab -e
#    0 2 * * * /opt/scripts/mysql_backup_s3.sh >> /var/log/mysql_backup.log 2>&1
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ══════════════════════════════════════════════
#  ⚙️  CONFIGURATION  – Edit these values!
# ══════════════════════════════════════════════

# MySQL connection details (match your docker-compose.yml)
DB_HOST="127.0.0.1"          # use 127.0.0.1 (not 'localhost') with TCP
DB_PORT="3306"
DB_USER="root"
DB_PASSWORD="rootpassword"    # ← your MySQL root password
DB_NAME="myapp_db"            # ← database to back up ("--all-databases" for all)

# Local backup folder on the VM
BACKUP_DIR="/opt/backups/mysql"
RETAIN_DAYS=7                 # delete local backups older than this many days

# Amazon S3 settings
S3_BUCKET="s3://your-bucket-name"          # ← your S3 bucket
S3_FOLDER="mysql-backups"                  # folder inside the bucket
AWS_REGION="ap-south-1"                    # ← your AWS region (Mumbai = ap-south-1)

# Notification (optional) – set to empty string "" to disable
ALERT_EMAIL=""                # e.g. "admin@yourcompany.com"

# ══════════════════════════════════════════════
#  Color codes
# ══════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ══════════════════════════════════════════════
#  Logging helper – every line gets a timestamp
# ══════════════════════════════════════════════
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_ok()   { log "${GREEN}✅ $1${NC}"; }
log_err()  { log "${RED}❌ $1${NC}";  }
log_info() { log "${BLUE}ℹ️  $1${NC}"; }
log_warn() { log "${YELLOW}⚠️  $1${NC}"; }

# ══════════════════════════════════════════════
#  STEP 0: Allow override of DB name from CLI
# ══════════════════════════════════════════════
if [[ -n "${1:-}" ]]; then
    DB_NAME="$1"
    log_info "Using database from argument: $DB_NAME"
fi

# ══════════════════════════════════════════════
#  STEP 1: Create local backup directory
# ══════════════════════════════════════════════
log_info "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# ══════════════════════════════════════════════
#  STEP 2: Generate a timestamped filename
#  Example: myapp_db_2024-01-15_02-30-00.sql.gz
# ══════════════════════════════════════════════
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
BACKUP_FILENAME="${DB_NAME}_${TIMESTAMP}.sql.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

log_info "Backup file will be: $BACKUP_PATH"

# ══════════════════════════════════════════════
#  STEP 3: Check required tools exist
# ══════════════════════════════════════════════
for tool in mysqldump gzip aws; do
    if ! command -v "$tool" &>/dev/null; then
        log_err "Required tool not found: $tool"
        log_err "Install with: sudo apt install mysql-client awscli -y"
        exit 1
    fi
done
log_ok "All required tools found (mysqldump, gzip, aws)"

# ══════════════════════════════════════════════
#  STEP 4: Test MySQL connection before dumping
# ══════════════════════════════════════════════
log_info "Testing MySQL connection..."
if ! mysqladmin -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" ping --silent 2>/dev/null; then
    log_err "Cannot connect to MySQL at $DB_HOST:$DB_PORT"
    log_err "Check DB_HOST, DB_PORT, DB_USER, DB_PASSWORD in the script"
    exit 1
fi
log_ok "MySQL connection successful"

# ══════════════════════════════════════════════
#  STEP 5: Run the backup
#
#  mysqldump flags explained:
#   --single-transaction  → consistent snapshot without locking tables (InnoDB)
#   --quick               → streams rows instead of loading all into memory
#   --lock-tables=false   → avoids locking when using --single-transaction
#   --routines            → includes stored procedures & functions
#   --triggers            → includes triggers
#   --events              → includes scheduled events
#
#  The output is piped directly into gzip to save disk space.
# ══════════════════════════════════════════════
log_info "Starting MySQL dump for database: $DB_NAME ..."

if [[ "$DB_NAME" == "--all-databases" ]]; then
    DUMP_FLAGS="--all-databases"
else
    DUMP_FLAGS="--databases $DB_NAME"
fi

mysqldump \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -p"$DB_PASSWORD" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --routines \
    --triggers \
    --events \
    $DUMP_FLAGS \
    | gzip > "$BACKUP_PATH"

# Verify the file was created and is not empty
if [[ ! -s "$BACKUP_PATH" ]]; then
    log_err "Backup file is empty or was not created!"
    exit 1
fi

BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log_ok "Database dump complete → $BACKUP_PATH ($BACKUP_SIZE)"

# ══════════════════════════════════════════════
#  STEP 6: Upload to S3
#
#  aws s3 cp flags:
#   --region        → your AWS region
#   --storage-class → STANDARD_IA is cheaper for infrequent-access backups
#                     use STANDARD if you access backups often
# ══════════════════════════════════════════════
S3_DESTINATION="${S3_BUCKET}/${S3_FOLDER}/${BACKUP_FILENAME}"

log_info "Uploading to S3: $S3_DESTINATION ..."

if aws s3 cp "$BACKUP_PATH" "$S3_DESTINATION" \
       --region "$AWS_REGION" \
       --storage-class STANDARD_IA; then
    log_ok "Uploaded to S3 successfully: $S3_DESTINATION"
else
    log_err "S3 upload failed!"
    log_err "Check: aws configure   and verify bucket name + permissions"
    exit 1
fi

# ══════════════════════════════════════════════
#  STEP 7: Delete local backups older than RETAIN_DAYS
# ══════════════════════════════════════════════
log_info "Removing local backups older than $RETAIN_DAYS days..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$RETAIN_DAYS" -exec rm -f {} \;
log_ok "Old local backups cleaned up"

# List remaining local backups
log_info "Current local backups:"
ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || log_warn "No local backups found"

# ══════════════════════════════════════════════
#  STEP 8: List backups in S3 (confirmation)
# ══════════════════════════════════════════════
log_info "S3 backups in ${S3_BUCKET}/${S3_FOLDER}/:"
aws s3 ls "${S3_BUCKET}/${S3_FOLDER}/" --region "$AWS_REGION" | tail -10

# ══════════════════════════════════════════════
#  STEP 9: Send email alert (optional)
# ══════════════════════════════════════════════
if [[ -n "$ALERT_EMAIL" ]]; then
    SUBJECT="✅ MySQL Backup Successful – ${DB_NAME} – $(date '+%Y-%m-%d')"
    BODY="Backup: $BACKUP_FILENAME\nSize: $BACKUP_SIZE\nS3: $S3_DESTINATION"
    echo -e "$BODY" | mail -s "$SUBJECT" "$ALERT_EMAIL" 2>/dev/null \
        && log_ok "Email alert sent to $ALERT_EMAIL" \
        || log_warn "Email send failed (mail utility may not be configured)"
fi

# ══════════════════════════════════════════════
#  DONE!
# ══════════════════════════════════════════════
log_ok "══════════════════════════════════════════"
log_ok "  BACKUP COMPLETE"
log_ok "  DB      : $DB_NAME"
log_ok "  File    : $BACKUP_FILENAME"
log_ok "  Size    : $BACKUP_SIZE"
log_ok "  S3 Path : $S3_DESTINATION"
log_ok "══════════════════════════════════════════"
