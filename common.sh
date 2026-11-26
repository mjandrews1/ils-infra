#!/usr/bin/env bash
# Shared harness: every script sources this. --check flips global MODE.
set -euo pipefail
MODE="apply"; CHECKS_Passed=0; CHECKS_Failed=0
[[ "${1:-}" == "--check" ]] && MODE="check"
log() { printf '%s [%s] %s\n' "$(date -Is)" "${MODE}" "$*" >&2; }
ok() { CHECKS_Passed=$((CHECKS_Passed+1)); log "PASS: $*"; }
drift() { CHECKS_Failed=$((CHECKS_Failed+1)); log "DRIFT: $*"; }
require_root() { [[ $EUID -eq 0 ]] || { log "must run as root"; exit 2; }; }
# do_ <description> <command...> - runs in apply mode; verifies by exit code in --check
do_() {
    local desc="$1"; shift
    if [[ "$MODE" == "check" ]]; then
        if "$@" >/dev/null 2>&1; then ok "$desc"; else drift "$desc"; fi
    else
        log "APPLY: $desc"
        "$@"
    fi
}
# file_contains <file> <needle> - idempotent config-append guard
file_contains() { grep -qF -- "$2" "$1" 2>/dev/null; }
finish() {
    log "summary: ${CHECKS_Passed} passed, ${CHECKS_Failed} failed"
    [[ $CHECKS_Failed -eq 0 ]] || exit 1
}
