#!/usr/bin/env bash
SHELL=/bin/bash
BASH_ENV=/app/environment
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

BACKUP_DIR="$(ls -tr ${ARK_SERVER_VOLUME}/backup/|tail -1)"
BACKUP_FILE="$(ls -tr ${ARK_SERVER_VOLUME}/backup/${BACKUP_DIR}/|tail -1)"

if [[ ! -z "${BACKUP_FILE}" ]]; then
  echo "Uploading file to S3..."
  aws s3 cp ${ARK_SERVER_VOLUME}/backup/${BACKUP_DIR}/${BACKUP_FILE} ${AWS_BUCKET_URL}/main.tar.bz2
else
  echo "No backup files found."
fi
