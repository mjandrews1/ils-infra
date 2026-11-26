# ils-infra

Provisioning scripts for the meshgraph ils node (\`container\`: Intel Mac mini, Ubuntu Server 26.04, YottaDB + Tarantool co-located per the FFI-co-location decision).

## Contract

- Every script supports \`--check\` (read-only verification: prints what would change and what's already compliant, exits non-zero on drift)
- All writes idempotent
- Run order is the file-number order
- 05-luks.sh is the only destructive-capable script: explicit target argument, full-disk emptiness proof, typed YES gate
- Secrets (restic.passwd, UMLS credentials, Porkbun keys) are pre-staged root-only files, NEVER in this repo

## Layout

\`\`\`
ils-infra/
    common.sh           shared --check harness, idempotency, drift reporting
    00-preflight.sh     firmware checks: Ubuntu 26.04, 32GB RAM, disk, LUKS
    05-luks.sh          guarded LUKS creation ritual (refuses non-empty targets)
    10-lxd.sh           LXD container "ils" + profile (memlock-aware)
    20-yottadb.sh       YottaDB install + user + env + region layout (GDE)
    30-tarantool.sh     Tarantool install + ils user + systemd unit
    40-security.sh      ufw, chrony, memlock limits, unattended-upgrades, auditd
    45-clevis.sh        clevis-luks client verify on container (bind is manual disk-setup)
    50-pforth.sh        clone meshgraph-ils, build pForth with read ABI
    60-backup.sh        restic to storage + restore-drill helper
    70-monitoring.sh    node_exporter + textfile dir (consumes watch.4th output)
    80-verify.sh        full-sweep read-only verification
    90-bouncer.sh       DDNS + Caddy DNS-01 + fail2ban on bouncer (Phase 3)
    tang-desktop.sh     RUNS ON desktop (Tang server; out of numbered run order)
    timed.sh            FLEET-WIDE: UTC + common NTP sources + skew metric
    storage.sh          RUNS ON storage: restic target user/dir/key-slot/ufw
\`\`\`

## Run order

00 always (both modes) → 05 (LUKS ritual, apply BEFORE data, guarded) → 10 → 20 → 30 → 40 → 45 → 50 → 60 → 70, then 80 after any later change. All in apply mode on first provision, --check mode thereafter.

\`tang-desktop.sh\` runs on desktop independently, BEFORE the first reboot that relies on Clevis unlock. \`timed.sh\` runs once per node. \`storage.sh\` runs once on storage.

## Honest gaps (deliberate)

- **TODO-verify items**: YottaDB ydbinstall flags, GDE invocation / mupip create/journal sequences, Tarantool tt vs tarantoolctl instance handling on 3.x, pForth extension mechanism on current master — drafted from documented shapes, verify against installed versions on provisioning day.
- **LUKS bind is manual**: 05-luks.sh performs the ritual; the clevis-luks bind to desktop's Tang happens at disk-setup time by hand (passphrase + bind + header backup together), then 45-clevis.sh verifies it stays healthy.
- **Not provisioned here**: desktop Prometheus/Grafana (Phase 4 alerting), bouncer router-side prerequisites (WAN port-forwards, Porkbun A record — manual like LUKS).
- **Key-based SSH fleet-wide**, no passwords. Pin unattended-upgrades Automatic-RebootTime clear of the 2:30 backup window on all nodes.

## Postmortems

\`docs/\` carries incident records. Start with \`docs/postmortem-2026-11-26.md\` — the from-scratch rebuild of container that proved the backup loop under live fire, and the four script bugs found by first real execution.
