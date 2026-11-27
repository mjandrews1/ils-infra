# Artifact lineage — how the sources progressed

Three source artifacts, oldest to newest, and how each is represented in this
repo. The progression is lossless: nothing in an older generation is missing
from the newer ones except its own superseded decisions, which are recorded
below and in the postmortem.

## Gen 1 (oldest): ils-infra provisioning scripts PDF

- Drafted pre-rebuild (its disk-surgery checklist still names SHRINK-IN-PLACE
  as the chosen path — proof it predates the from-scratch decision of Nov 26).
- Transcribed into this repo as the founding commit, with the four bugs its
  first real execution exposed (see docs/postmortem-2026-11-26.md).
- Its disk-surgery checklist survives at docs/disk-surgery-checklist.md —
  historical record plus a reusable ritual (export-before-surgery,
  restore-drill-after).

## Gen 2: code-drafts-by-role PDF (22 pp)

- Application layer by language role, sections 1–12: Python loaders + sync
  daemon, M trigger/watchman/CIRC, Lua spaces/sync/rebuild/opac, Prolog
  resolver, pForth probes, Dafny sketch, reliability annex, the performance
  evidence system, Phase-2 loaders, consolidated alert rules, auth/RBAC/CLI.
- Ends at section 12.6 (route boundary table).
- Its content is fully carried by Gen 3; nothing unique remains except the
  PDF's own OCR-garbled formatting.

## Gen 3 (newest): code-drafts-by-role.md

- Everything in Gen 2, cleaned of OCR damage, PLUS section 13: the Dafny
  promotion criteria (the gate, not the proofs) with MUST/NEGATIVE criteria
  and standing scope limits.
- This is the canonical contract for the application layer, and the authority
  the cross-layer commit of Nov 27 reconciled the infra scripts against
  (zchg* region mapping, CIRC region contents, pForth binary path,
  watch.4th invocation).

## Repo commits mapping

| Repo commit | Source generation | What it carries |
| --- | --- | --- |
| founding (bbe23fc + follows) | Gen 1 + live fixes | all 16 scripts, four bug repairs found on real hardware |
| cross-layer fix (2c919f6) | Gen 3 | infra scripts aligned to app-layer contracts |
| belt-and-suspenders pass | Gen 3 | alert-rule emitters, perf cron, LUKS apply idempotency + self-verification |

## Standing rule

The code drafts (Gen 2/3) are application-layer and live in the
meshgraph-ils repo when it exists. This repo (ils-infra) carries host and
guest provisioning only. Cross-layer contracts (paths, global names, metric
names, cron schedules) are checked at every generation bump: when a newer
draft changes a contract, the infra scripts follow, with a dated comment.
