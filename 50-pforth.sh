#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
ILS_CT="ils"
# pForth is built from the meshgraph-ils repo (build-time ABI freeze; read-only
# words only - no ydb_set binding exists anywhere in the extension).
do_ "repo cloned" lxc exec "$ILS_CT" -- test -d /opt/meshgraph-ils
[[ "$MODE" == "apply" ]] && lxc exec "$ILS_CT" -- git clone https://github.com/mjandrews1/meshgraph-ils.git /opt/meshgraph-ils 2>/dev/null || true
if [[ "$MODE" == "apply" ]]; then
    # pForth clone + build: bindings live at ils/probes/pforth_custom.c
    lxc exec "$ILS_CT" -- bash -c "cd /opt/meshgraph-ils && ./ils/probes/build_pforth.sh" # TODO: that script is a Phase-1 artifact
fi
do_ "pforth binary with ILS words" lxc exec "$ILS_CT" -- /opt/meshgraph-ils/ils/probes/pforth -e "0 s\" ydb.get\" nip find drop bye"
finish
