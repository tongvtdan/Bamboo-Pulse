# Trail Log: fictional project walkthrough

Trail Log is an invented offline packing-checklist app for weekend hikers. Every product name, prefix, issue number, assignment, metric, date, and result below is illustrative. No app, title assignment, completed test, repository, user demand, or release is established by this example.

Keep this reference separate from live project instructions. Copy the structure, then replace facts using the real project and owner confirmation.

## Project setup example

| Field | Fictional value |
| --- | --- |
| Product | Trail Log |
| Core user | A weekend hiker preparing a short trip |
| Promise | Create a packing checklist and keep packed items saved offline |
| First value | Create a list and check one item without an account |
| Stack | Flutter; persistence behind a small repository interface |
| Implementation root | app/ |
| Product loop | Create list → pack items → reopen before departure → reuse next trip |
| Activation metric | First list with one checked item |
| Retention metric | Lists reused for a later trip |
| Revenue hypothesis | Some users may pay for reusable list packs after core value is proven |
| MVP non-goals | Social feed, cloud sync, BLE devices, automatic route advice |

These metrics define things to measure; no target or paid demand is validated here.

## AGENTS.md example

Product: Trail Log helps weekend hikers prepare a reusable packing list offline.

Priority: Preserve list contents and packed flags across restarts.

Ownership: UI lives in app/lib/features/checklists/; persistence is behind the checklist repository; core list rules have no UI or network dependency. Follow the actual code layout if it differs.

Boundaries: Creating, editing, and reopening a local checklist requires no login. Add cloud sync only under an explicitly authorized task. Keep failure states visible; never show "Saved" when persistence failed.

Task contract: For offline save, edit persistence and direct callers only. Acceptance includes packed flags surviving restart, an empty list loading safely, and failed saves preserving the last saved data.

Read SHORTCUTS.md for aliases, CHAT_NAMING.md for title policy, and PROJECT_STATE.md for current assignments/evidence. Do not duplicate these policies in tool adapters.

## Chat naming example

Fictional confirmation: On 2030-04-12 the example owner said, "Use TL for Trail Log." A real project must obtain its own confirmation.

The example inventory has TL-X-01 | Offline Checklist, TL-C-02 | Activation Experiment, and TL-W-03 | Export Acceptance. They share a project counter. TL-X-04 | Restart Persistence is a candidate only after checking all recorded assignments, available archives, linked platforms, and concurrent assignments.

| Case | Expected action |
| --- | --- |
| Prefix is unconfirmed | Ask once when naming can otherwise proceed; save the answer |
| Existing TL-X-01 title is valid | Preserve title and number |
| An archived task has 07; 05–06 are absent | Reserve history; use 08 as the next candidate after recheck |
| ChatGPT Work task concerns coding | Use W because the actual environment is Work |
| Title setter unavailable | Continue the task silently; do not claim a rename |
| Duplicate 04 assignments found | Resolve conflict before allocating; continue substantive work |
| Two sessions attempt candidate 04 | Reserve it under exclusive writer ownership before renaming; the other session rechecks the record |
| Shared reservation ownership cannot be established | Skip allocation and continue the task without claiming a safe number |
| Native listing is capped | Treat it as partial; check other available recorded evidence |
| Save succeeds but verification is unavailable | Keep the candidate reserved/pending, not verified |

## SHORTCUTS.md example

- /Investigate checked items disappear after restart: trace the bug; report evidence and a minimal proposal.
- /Fix checked items disappear after restart: implement the scoped correction and verify the failure case.
- /QA offline save: report acceptance verdicts with evidence.
- /Release offline save: assess readiness; publication still needs its own authority.
- /Team offline save: propose ownership; delegation still needs explicit authorization.

MODE PRODUCT + ARCHITECTURE with /Plan offline save asks for a plan informed by user value and persistence boundaries.

## DESIGN.md example

Use a calm, readable checklist. Make the next packing action obvious. Show unchecked, packed, saving, saved, and save-failed states with text as well as icons. Keep packed state visible in high-contrast settings and with larger text.

Example semantic tokens: canvas #F7F8FA, ink #17212B, primary #145A74, success #246B3C, danger #A82525; spacing 4/8/16/24 logical pixels. Validate actual contrast and accessibility before adopting them.

An empty checklist offers "Add your first item." A save error keeps edits visible and offers Retry; it does not falsely confirm persistence.

## SPEC.md example

Illustrative issue #12: Keep packed flags after restart.

- Outcome: A hiker reopens the app and sees the same packed items.
- Product reason: Activation and repeat use depend on trusting the saved list.
- In: save/load mapping and its immediate UI feedback.
- Out: accounts, sync, notifications, unrelated redesign.
- Writer: one implementation agent; reviewer checks persistence and failure behavior.
- Acceptance: flags survive restart; empty list loads; failed save preserves last saved data; retry does not duplicate items.
- Required evidence: focused repository test, restart walkthrough, and save-failure check.
- Status: In Review only after evidence; Done only after acceptance and merge/explicit acceptance under project policy.

## WORKFLOW.md example

Work on feature/12-restart-persistence from main. Read issue #12 and the current task contract, claim its authorized status, implement the slice, and open a draft PR linked to the issue.

Record actual command output. After required checks and review, the authorized maintainer may merge to the default branch; only then does a closing keyword automatically close the linked issue. App publication is a separate action.

Example commands for a hypothetical implementation:

```sh
cd app
flutter analyze
flutter test test/features/checklists/checklist_repository_test.dart
```

This template repository does not contain that app or test. Do not run or report these commands as verified template checks.

## Project state example

This is a fictional state record, not a live assignment ledger.

| Field | Illustrative value |
| --- | --- |
| Updated | 2030-04-12 10:00 UTC |
| Project/environment | Trail Log / Codex / /workspace/trail-log |
| Confirmed prefix/source | TL / example owner's instruction on 2030-04-12 |
| Inventory coverage | Fictional local active/archive records plus linked Chat/Work assignments |
| Highest recorded number | 03 |
| Next candidate | 04; recheck required before use |
| Writer | Implementation agent A |
| Allowed scope | Save/load mapping and direct callers |
| Branch | feature/12-restart-persistence |
| Commit | UNRECORDED in this fictional record |
| Dirty files | app/lib/features/checklists/checklist_repository.dart |
| Review | Required persistence review pending |

Illustrative acceptance report:

| Criterion | Verdict | Evidence label | Evidence that would be needed |
| --- | --- | --- | --- |
| Packed flags survive restart | PENDING | HYPOTHESIS | Actual restart reproduction and persisted-value check |
| Empty list loads | PENDING | UNKNOWN/PENDING | Actual empty-list test |
| Failed save preserves last data | PENDING | UNKNOWN/PENDING | Injected save failure and subsequent reload |
| Users will pay for reusable lists | PENDING | HYPOTHESIS | A demand experiment with observed behavior |

Next action: reproduce the restart failure with a two-item list. Success means a recorded reproduction identifies whether data is lost during save or load.

## Handoff example

Date/environment: 2030-04-12 UTC, fictional Trail Log in Codex.

Authorized outcome: Keep packed flags after restart. Scope: persistence and direct callers. Exclusions: cloud sync and unrelated UI work.

Current evidence: No implementation or test execution is asserted by this example. Acceptance remains PENDING. Branch/file references above illustrate how to record real state.

Resume prompt: Resume Trail Log's offline-save task in /workspace/trail-log. Read AGENTS.md, applicable scoped instructions, PROJECT_STATE.md, SPEC.md, and issue #12 if accessible. Verify current branch, commit, and dirty files. Reproduce the two-item restart failure, then change only save/load mapping and direct callers under the task's authorization. Verify restart, empty-list, failed-save, and retry cases. Record actual commands/results, unresolved acceptance, and required reviewer findings. Do not infer release or publication authority.
