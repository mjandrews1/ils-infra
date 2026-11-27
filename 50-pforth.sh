#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
ILS_CT="ils"
# pForth is built from the meshgraph-ils repo (build-time ABI freeze; read-only
# words only - no ydb_set binding exists anywhere in the extension).
# The binary lands at /opt/pforth/build/pforth_standalone per the repo's
# ils/probes/build_pforth.sh (cross-layer fix, Nov 27 2026 - the build script
# is the authority on its own output path).
#
# RECORDED FALLBACK TRIGGER (decision, Nov 27 2026, design doc "Language-count
# decisions"): Forth is kept because read-only-by-construction mechanically
# enforces "globals are truth" at the probe layer. IF the pForth
# extension-mechanism TODO-verify turns ugly on current master at Phase 1,
# the probe layer folds into Python (yottadb binding, already present for the
# sync daemon) and read-only becomes discipline. If that happens: write the
# decision down with its reason, retire this script's build step, and move
# the probe words to Python - do not half-patch both.
PFORTH_BIN=/opt/pforth/build/pforth_standalone
do_ "repo cloned" lxc exec "$ILS_CT" -- test -d /opt/meshgraph-ils
[[ "$MODE" == "apply" ]] && lxc exec "$ILS_CT" -- git clone https://github.com/mjandrews1/meshgraph-ils.git /opt/meshgraph-ils 2>/dev/null || true
if [[ "$MODE" == "apply" ]]; then
    # pForth clone + build: bindings live at ils/probes/pforth_custom.c
    lxc exec "$ILS_CT" -- bash -c "cd /opt/meshgraph-ils && ./ils/probes/build_pforth.sh" # TODO: that script is a Phase-1 artifact
fi
do_ "pforth binary present" lxc exec "$ILS_CT" -- test -x "$PFORTH_BIN"
do_ "pforth binary with ILS words" lxc exec "$ILS_CT" -- "$PFORTH_BIN" -e "0 s\" ydb.get\" nip find drop bye"
finish
