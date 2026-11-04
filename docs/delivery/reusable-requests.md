# Reusable requests

[SHORTCUTS.md](../../SHORTCUTS.md) owns alias behavior and permissions. This file supplies request structure; do not copy a second alias policy into tool adapters.

## Compact request contract

For substantive work, identify:

- Outcome: one observable user or maintainer result.
- Sources: current files, issue, constraints, and versions.
- Scope: allowed surfaces, excluded changes, and authorized external actions.
- Ownership: lead, one writer, and required review.
- Acceptance: normal path, boundary case, and realistic failure case.
- Evidence: reproducible commands and required manual, physical, or external checks.

Scale this to the task. A small edit needs a sentence, not a new planning document. Missing optional details can be stated as assumptions; ask when a missing choice materially changes the result.

## Fictional Trail Log requests

| Request | Outcome, boundary, and evidence |
| --- | --- |
| /Whatnext reduce setup time | Inspect the current spec and implementation; recommend one slice, a product reason, acceptance, and the next check. |
| /Research offline list export | Compare practical options using cited primary sources; separate facts, assumptions, and unverified integration behavior. |
| /Explain restart restoration | Trace the save/load path with file locations; explain empty and corrupt-data behavior without implementing changes. |
| /Plan checklist export | Define scope, dependency decisions, happy/empty/error paths, ownership, and verification before implementation. |
| /Build save checked items offline | Update only list persistence and its callers. Packed flags survive restart. A failed save remains visible and preserves the last saved data. |
| /Investigate missing checked items | Reproduce with a minimal list, trace save/load ordering, distinguish confirmed cause from hypothesis, and propose the smallest fix. |
| /Fix empty titles being saved | Reject blank/whitespace titles at the owning boundary. Confirm valid titles still save and existing lists still load. |
| /Test current persistence diff | Run existing relevant checks and a restart reproduction; report actual commands, exit results, and untested paths. |
| /Addtests failed-save behavior | Derive tests from the contract: save error is visible, last saved list remains available, and retry does not duplicate entries. |
| /Review persistence diff | Report actionable defects with severity, location, impact, and a reproducer; label this as same-agent self-review if applicable. |
| /Security checklist export | Trace whether private notes cross storage or export boundaries; report evidence and gaps without claiming certification. |
| /Critic adding public profiles | Test the activation/revenue/retention rationale, identify disconfirming evidence, and recommend one smaller experiment. |
| /QA checklist save | Assess non-empty, empty, duplicate-item, failed-save, and restart criteria; report each as PASS, FAIL, or PENDING. |
| /Release current branch | Assess configured checks, acceptance, open findings, migrations, and required human review; report readiness without publishing. |
| /Team storage and export | Propose lead/writer/reviewer responsibilities and acceptance. Use separate agents only if the owner also authorizes delegation. |
| /Decision export format | Compare readable text and a formatted document against the current user job; recommend one with an explicit tradeoff. |
| /Status | Report outcome, blocker (or none), and one next action. Reconstruct from current evidence if session context is missing. |
| /Handoff | Include dated project/environment, scope/actual changes, artifacts/branch/commit, checks/results, pending evidence, and a self-contained resume prompt. |

The example paths and commands in [Trail Log](../../examples/trail-log.md) describe a fictional Flutter app. They become runnable only after a real project implements those files and commands.

## Handoff practice

Use [PROJECT_STATE.md](../../PROJECT_STATE.md) for durable state when saving is authorized. A /Handoff request alone produces a response; it does not grant file edits or commits.

A useful handoff states what was actually changed and checked, the exact remaining acceptance gap, and one next success criterion. Exclude secrets, raw patient/sensor data, and unrelated private project details.
