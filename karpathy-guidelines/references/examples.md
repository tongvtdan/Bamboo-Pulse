# Guardrail examples using a fictional project

Trail Log is a fictional offline packing-checklist app. These examples illustrate decisions, not implemented features or actual verification.

## Hidden assumptions

Weak approach: change list persistence without checking empty lists, corrupt saved data, or interrupted saves.

Better approach: trace save/load and define expected behavior for each failure case before editing. Preserve the last saved list on a failed write; label unchecked cases PENDING.

## Unnecessary abstraction

Weak approach: add a plugin registry for future checklist formats when only plain checklist items exist.

Better approach: keep the existing small repository interface. Add a new abstraction only when actual callers and complexity justify it; no arbitrary count of examples automatically warrants one.

## Unrelated refactoring

Weak approach: fix packed flags while renaming unrelated widgets and reorganizing feature folders.

Better approach: change save/load mapping and its direct caller, verify restart behavior, and report unrelated cleanup separately.

## Verifiable goals

Weak approach: "make saving more reliable."

Better approach: "a two-item list keeps packed flags after restart; a failed save retains the last saved list and exposes Retry." Record actual reproduction and check results before claiming PASS.

## Architectural boundaries

Weak approach: add mandatory cloud login because local save failed.

Better approach: keep the offline workflow and investigate the owning persistence path. A new sync/auth boundary needs its own scoped decision and authority.

## Conservative status

Weak approach: show "Saved" immediately even if persistence has failed.

Better approach: distinguish saving, saved, and failed-save states, preserve edits, and let the user retry. Unknown success remains unknown.

## Instruction drift

Weak approach: duplicate all shortcut/naming rules in CODEX.md and CLAUDE.md and later update only one.

Better approach: link both adapters to SHORTCUTS.md, CHAT_NAMING.md, and PROJECT_STATE.md. Read current files before concluding that an older adapter describes the actual architecture.

## Evidence honesty

Weak approach: copy a sample flutter test command and report it passed.

Better approach: run only configured commands against real files, record the output, and report unperformed checks as PENDING. The fictional walkthrough is not test evidence.
