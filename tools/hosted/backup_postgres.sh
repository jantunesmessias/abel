#!/usr/bin/env bash
set -euo pipefail

: "${CONTROL_PLANE_DATABASE_URL:?CONTROL_PLANE_DATABASE_URL is required}"
: "${CONTROL_PLANE_BACKUP_DIRECTORY:?CONTROL_PLANE_BACKUP_DIRECTORY is required}"

umask 077
mkdir -p -- "$CONTROL_PLANE_BACKUP_DIRECTORY"
if [[ ! -d "$CONTROL_PLANE_BACKUP_DIRECTORY" || -L "$CONTROL_PLANE_BACKUP_DIRECTORY" ]]; then
  echo 'Backup destination must be a real directory.' >&2
  exit 64
fi

pg_dump_command="${POSTGRES_DUMP:-pg_dump}"
command -v "$pg_dump_command" >/dev/null 2>&1 || {
  echo 'pg_dump is unavailable.' >&2
  exit 69
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$CONTROL_PLANE_BACKUP_DIRECTORY/control-plane-$timestamp.dump"
partial="$backup.partial"
checksum="$backup.sha256"
trap 'rm -f -- "$partial"' EXIT

started="$(date +%s)"
"$pg_dump_command" \
  --dbname="$CONTROL_PLANE_DATABASE_URL" \
  --format=custom \
  --compress=zstd:9 \
  --no-owner \
  --no-privileges \
  --file="$partial"
mv -- "$partial" "$backup"
(
  cd -- "$CONTROL_PLANE_BACKUP_DIRECTORY"
  sha256sum -- "${backup##*/}" > "${checksum##*/}"
)
chmod 0600 -- "$backup" "$checksum"
finished="$(date +%s)"

printf 'backup=%s\n' "$backup"
printf 'checksum=%s\n' "$checksum"
printf 'bytes=%s\n' "$(stat -c %s -- "$backup")"
printf 'elapsed_seconds=%s\n' "$((finished - started))"
