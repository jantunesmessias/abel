#!/usr/bin/env bash
set -euo pipefail

: "${CONTROL_PLANE_BACKUP_FILE:?CONTROL_PLANE_BACKUP_FILE is required}"
: "${PGHOST:?PGHOST is required}"
: "${PGUSER:?PGUSER is required}"

if [[ ! -f "$CONTROL_PLANE_BACKUP_FILE" || -L "$CONTROL_PLANE_BACKUP_FILE" ]]; then
  echo 'Backup must be a regular, non-symlink file.' >&2
  exit 64
fi
checksum="$CONTROL_PLANE_BACKUP_FILE.sha256"
if [[ ! -f "$checksum" || -L "$checksum" ]]; then
  echo 'Backup checksum sidecar is absent.' >&2
  exit 64
fi

max_age="${CONTROL_PLANE_MAX_BACKUP_AGE_SECONDS:-900}"
if [[ ! "$max_age" =~ ^[0-9]+$ || "$max_age" -lt 1 ]]; then
  echo 'CONTROL_PLANE_MAX_BACKUP_AGE_SECONDS is invalid.' >&2
  exit 64
fi
age="$(( $(date +%s) - $(stat -c %Y -- "$CONTROL_PLANE_BACKUP_FILE") ))"
if (( age < 0 || age > max_age )); then
  echo "Backup age ${age}s exceeds the RPO evidence window ${max_age}s." >&2
  exit 1
fi

pg_restore_command="${POSTGRES_RESTORE:-pg_restore}"
createdb_command="${POSTGRES_CREATEDB:-createdb}"
dropdb_command="${POSTGRES_DROPDB:-dropdb}"
for command_name in "$pg_restore_command" "$createdb_command" "$dropdb_command"; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Required PostgreSQL command is unavailable: $command_name" >&2
    exit 69
  }
done

(
  cd -- "$(dirname -- "$CONTROL_PLANE_BACKUP_FILE")"
  sha256sum --check --strict -- "${checksum##*/}"
)

admin_database="${CONTROL_PLANE_ADMIN_DATABASE:-postgres}"
restore_database="control_plane_rehearsal_$(date -u +%Y%m%d%H%M%S)_${BASHPID:-$$}"
if [[ ! "$restore_database" =~ ^control_plane_rehearsal_[0-9]{14}_[0-9]+$ ]]; then
  echo 'Generated rehearsal database name failed validation.' >&2
  exit 70
fi
created=0
cleanup() {
  if (( created == 1 )); then
    "$dropdb_command" --maintenance-db="$admin_database" --if-exists --force \
      "$restore_database" >/dev/null
  fi
}
trap cleanup EXIT

started="$(date +%s)"
"$createdb_command" --maintenance-db="$admin_database" "$restore_database"
created=1
"$pg_restore_command" \
  --dbname="$restore_database" \
  --exit-on-error \
  --single-transaction \
  "$CONTROL_PLANE_BACKUP_FILE"

CONTROL_PLANE_DATABASE_URL="dbname=$restore_database" \
  CONTROL_PLANE_RLS_ROLE="${CONTROL_PLANE_RLS_ROLE:-control_plane_app}" \
  POSTGRES_CLIENT="${POSTGRES_CLIENT:-psql}" \
  "$(dirname "${BASH_SOURCE[0]}")/verify_postgres_rls.sh"

finished="$(date +%s)"
elapsed="$((finished - started))"
rto_limit="${CONTROL_PLANE_RTO_LIMIT_SECONDS:-14400}"
if [[ ! "$rto_limit" =~ ^[0-9]+$ || "$rto_limit" -lt 1 ]]; then
  echo 'CONTROL_PLANE_RTO_LIMIT_SECONDS is invalid.' >&2
  exit 64
fi
if (( elapsed > rto_limit )); then
  echo "Restore took ${elapsed}s, exceeding the RTO limit ${rto_limit}s." >&2
  exit 1
fi

printf 'restore_database=%s\n' "$restore_database"
printf 'backup_age_seconds=%s\n' "$age"
printf 'restore_elapsed_seconds=%s\n' "$elapsed"
printf 'rpo_limit_seconds=%s\n' "$max_age"
printf 'rto_limit_seconds=%s\n' "$rto_limit"
echo 'Restore rehearsal passed; the temporary database will now be removed.'
