#!/usr/bin/env bash
# Full read-only sweep for the ils node: run after any post-provision change.
# Modeled on fleet_sweep.sh discipline (read-only, drift is the signal).
source "$(dirname "$0")/common.sh"; require_root
for script in 00-preflight.sh 10-lxd.sh 20-yottadb.sh 30-tarantool.sh 40-security.sh 45-clevis.sh 50-pforth.sh 60-backup.sh 70-monitoring.sh; do
    log "=== $script --check ==="
    bash "$(dirname "$0")/$script" --check
done
log "node swept; see per-script summaries above"
