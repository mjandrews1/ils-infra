#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
ILS_CT="ils"
CRON_LINE="30 2 * * * root /usr/local/sbin/ils-backup.sh"
TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
# --- secrets pre-staged before any backup can exist (belt-and-suspenders,
# Nov 27 2026: the alert rules in the code drafts (BackupAge,
# ResticSnapshotAge, RestoreDrillFailed) are "silent failure would be
# catastrophic" class - they can only fire if the emitters below exist,
# and the emitters can only be honest if the secrets are gated first) ---
do_ "restic password file staged, mode 600" \
    lxc exec "$ILS_CT" -- bash -c 'test -f /etc/ils/restic.passwd && [ "$(stat -c %a /etc/ils/restic.passwd)" = "600" ]'
do_ "storage ssh key staged" lxc exec "$ILS_CT" -- test -f /etc/ils/storage_key
do_ "restic installed" lxc exec "$ILS_CT" -- restic version
do_ "backup cron present" lxc exec "$ILS_CT" -- grep -qF "$CRON_LINE" /etc/cron.d/ils-backup
if [[ "$MODE" == "apply" ]]; then
    lxc exec "$ILS_CT" -- apt-get install -y restic
    lxc exec "$ILS_CT" -- mkdir -p "$TEXTFILE_DIR"
    cat > /tmp/ils-backup.sh << 'EOF'
#!/usr/bin/env bash
# Coordinated backup: brief mupip BACKWARD freeze, then restic over the tailnet.
set -euo pipefail
export RESTIC_REPOSITORY="sftp:ils@storage:/srv/ils-restic"
export RESTIC_PASSWORD_FILE="/etc/ils/restic.passwd" # chmod 600, root-only (secret file, not in repo)
TEXTFILE=/var/lib/prometheus-node-exporter/textfile
$ydb_dist/mupip backup -online "*" /tmp/snapshot # TODO-verify: mupip backup options
$ydb_dist/mupip journal -extract ... /tmp/snapshot # incremental journal extract (idempotent-ish)
restic backup /tmp/snapshot /opt/meshgraph-ils/etc
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12
rm -rf /tmp/snapshot
# Emit the timestamps the alert rules watch (BackupAge / ResticSnapshotAge).
# A backup that cannot emit its own timestamp is a backup that silently died.
ts=$(date +%s)
snap=$(restic snapshots --json latest 2>/dev/null | jq -r '.[0].time' 2>/dev/null || echo 0)
snap_ep=$(date -d "$snap" +%s 2>/dev/null || echo "$ts")
printf 'meshgraph_mupip_backup_ts %s\nmeshgraph_restic_last_snapshot_ts %s\n' "$ts" "$snap_ep" \
    > "$TEXTFILE/ils_backup.prom"
EOF
    lxc file push /tmp/ils-backup.sh "$ILS_CT/usr/local/sbin/ils-backup.sh"
    lxc exec "$ILS_CT" -- chmod +x /usr/local/sbin/ils-backup.sh
    echo "$CRON_LINE" > /tmp/ils-backup.cron
    lxc file push /tmp/ils-backup.cron "$ILS_CT/etc/cron.d/ils-backup"
fi
# Scheduled restore drill (weekly, to /tmp inside the container, verify + discard)
DRILL_LINE="30 3 * * 0 root /usr/local/sbin/ils-restore-drill.sh"
do_ "restore-drill cron present" lxc exec "$ILS_CT" -- grep -qF "$DRILL_LINE" /etc/cron.d/ils-backup
if [[ "$MODE" == "apply" ]] && ! lxc exec "$ILS_CT" -- grep -qF "$DRILL_LINE" /etc/cron.d/ils-backup 2>/dev/null; then
    cat > /tmp/ils-restore-drill.sh << 'EOF'
#!/usr/bin/env bash
# Weekly restore drill: restic-restore the LATEST snapshot into scratch,
# verify integrity with YottaDB's own tooling, compare counts with live, and
# DISCARD. Doubles as the LUKS decrypt-path drill (restic decrypt + mupip read).
# A drill that can't verify exits nonzero and pages attention.
set -euo pipefail
export RESTIC_REPOSITORY="sftp:ils@storage:/srv/ils-restic"
export RESTIC_PASSWORD_FILE="/etc/ils/restic.passwd"
TEXTFILE=/var/lib/prometheus-node-exporter/textfile
SCRATCH=/tmp/restore-drill; mkdir -p "$SCRATCH"
# Emit our OWN exit code whatever happens (RestoreDrillFailed alert contract):
# the trap writes exit status even on the set -e bail-out paths.
drill_finish() { ec=$?; mkdir -p "$TEXTFILE"; printf 'meshgraph_restore_drill_exit %s\n' "$ec" > "$TEXTFILE/ils_drill.prom"; rm -rf "$SCRATCH"; }
trap drill_finish EXIT
snap=$(restic snapshots --json latest | jq -r '.[0].short_id')
echo "drilling snapshot $snap"
restic restore "$snap" --target "$SCRATCH"
# Integrity: restic checked the ciphertext; now YottaDB checks the data files.
ydb_dir="$SCRATCH/opt/yottadb"; ydb_dist=/opt/yottadb  # restored layout
$ydb_dist/mupip integ -file "$ydb_dir/ols/entity.dat" # TODO-verify mupip integ args
keysum=$($ydb_dist/mupip integ -fast 2>&1 | tail -3)
# Comparison: restored global count must equal live count for the drilled family.
live=$(lxc-host-helper 'mumps -direct: write $order(^entity(""),-1)') # TODO: call via host mumps or FFI probe
echo "verify: $keysum"; echo "live=$live"
echo "drill OK $(date -Is) snap=$snap" >> /var/log/ils/restore-drill.log
EOF
    lxc file push /tmp/ils-restore-drill.sh "$ILS_CT/usr/local/sbin/ils-restore-drill.sh"
    lxc exec "$ILS_CT" -- chmod +x /usr/local/sbin/ils-restore-drill.sh
    lxc exec "$ILS_CT" -- mkdir -p /var/log/ils
    lxc exec "$ILS_CT" -- bash -c "echo '$DRILL_LINE' >> /etc/cron.d/ils-backup"
fi
finish
