# Development ownership and review

Use only the perspectives needed for the task. One agent can cover product, engineering, and growth; describe its review as same-agent self-review. Do not claim independent verification unless another authorized reviewer performed it.

## Roles

| Role | Responsibility | Fictional Trail Log example |
| --- | --- | --- |
| Lead | Scope, task contract, assignments, integration, and evidence | Keep offline-list saving as the single outcome |
| Implementation writer | Smallest implementation within the owning boundary | Change checklist persistence and its direct caller |
| QA reviewer | Independently assess acceptance and failure paths when assigned | Check failed save, restart, and duplicate-item behavior |
| Security/domain reviewer | Review affected trust boundaries when required | Check export privacy or device behavior |
| Human owner | Resolve product decisions and approve protected actions | Accept a release after required evidence |

## One writer at a time

The current writer owns edits to shared artifacts. Reviewers inspect and run safe relevant checks without changing tracked files. Before transferring ownership, record the outgoing writer, affected paths, diff/branch/commit, check results, open findings, and incoming writer.

Isolated authorized worktrees can separate implementation work; integration into a shared artifact still has one writer. /Team alone creates a coordination plan. It does not authorize subagent spawning, new chats, messages, or assignments in external systems.

## Review and release

Reviewers use acceptance criteria derived from the task, not tests that merely repeat implementation. Report PASS, FAIL, or PENDING with evidence. The lead checks unresolved findings and integrates only within the owner's authorization.

Human review remains mandatory for sensitive data, entitlements, payments, notifications, hardware, migrations, or AI decisions that affect users. Preserve configured producer/verifier/protected-execution boundaries, physical human ACCEPT, consume-before-sign, replay/policy gates, and disabled approval controls when present. A document update, shortcut, or successful software test never bypasses them.

Follow [WORKFLOW.md](../../WORKFLOW.md) for issue/PR states and [PROJECT_STATE.md](../../PROJECT_STATE.md) for evidence and handoff fields.
