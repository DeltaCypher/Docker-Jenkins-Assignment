#!/bin/bash

# -----------------------------
# MySQL Database Backup Script
# -----------------------------

# Variables
DATE=$(date +%F-%H-%M-%S)
DB_NAME="mydatabase"
DB_USER="root"
DB_PASSWORD="mypassword"

BACKUP_DIR="/backup"
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_$DATE.sql"

S3_BUCKET="s3://my-mysql-backup-bucket"

# Create backup directory if not exists
mkdir -p $BACKUP_DIR

echo "Starting MySQL Backup..."

# Take MySQL backup
mysqldump -u $DB_USER -p$DB_PASSWORD $DB_NAME > $BACKUP_FILE

# Check backup status
if [ $? -eq 0 ]; then
    echo "Database backup completed successfully."
else
    echo "Database backup failed."
    exit 1
fi

echo "Uploading backup to S3..."

# Upload backup to S3
aws s3 cp $BACKUP_FILE $S3_BUCKET/

# Verify upload status
if [ $? -eq 0 ]; then
    echo "Backup uploaded successfully to S3."
else
    echo "S3 upload failed."
    exit 1
fi

echo "Backup process completed successfully."
