#!/usr/bin/env bash
# Nightly logical backup of the Shareby schema from Supabase (the free plan has no
# downloadable backups). Keeps the last 14 dumps.
#   crontab -e  ->  30 3 * * * /opt/shareby/deploy/backup.sh >> /var/log/shareby-backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"
DIR=${BACKUP_DIR:-/var/backups/shareby}
mkdir -p "$DIR"
URL=$(grep -E '^DATABASE_URL=' .env | cut -d= -f2-)
FILE="$DIR/shareby-$(date +%F).dump"
docker run --rm --network host -e PGSSLMODE=require postgres:17-alpine \
  pg_dump "$URL" --schema=shareby --format=custom --no-owner --no-privileges > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"
ls -1t "$DIR"/shareby-*.dump | tail -n +15 | xargs -r rm --
echo "$(date -Is) backup ok: $FILE ($(du -h "$FILE" | cut -f1))"
# Restore into a database:  pg_restore --no-owner -d "$URL" --clean --if-exists FILE
