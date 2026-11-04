# Project state

This is a fill-in state record, not evidence that a project, command, title, or release was verified. Replace unresolved fields with sourced facts. See the [fictional Trail Log record](examples/trail-log.md#project-state-example) before filling it in.

## Identity and naming

| Field | Value |
| --- | --- |
| Product | `<Project Name>` |
| Actual project root | `<absolute path verified in this environment>` |
| Repository | `<verified repository URL or none>` |
| Tracker state authority | `<board Status field/options or status labels; verified project/repository>` |
| Confirmed chat prefix | UNCONFIRMED |
| Confirmation source | `<owner instruction/date or pending>` |
| Naming policy | [CHAT_NAMING.md](CHAT_NAMING.md) |
| Linked platform projects/hosts | UNKNOWN until checked |
| Inventory coverage and time checked | `<sources, archives, caps, unavailable platforms, timestamp>` |
| Highest recorded or reserved number | UNKNOWN until checked |
| Next candidate | UNASSIGNED; calculate and recheck before use |

## Naming assignments

No assignments have been made by this template.

| Number | Platform | Saved title | Chat reference / confirmation evidence | State |
| --- | --- | --- | --- | --- |
| — | — | — | — | Unassigned |

Record verified, historical, and reserved assignments explicitly. Never convert an example row into a live assignment.

## Current task contract

- Updated at / timezone: `<date, time, timezone>`.
- Observable outcome: `<user-visible result>`.
- Sources inspected: `<current files, contracts, issue, and version>`.
- Allowed changes: `<surfaces and operations authorized>`.
- Excluded changes: `<explicit boundaries>`.
- Owner / current writer: `<person or agent>`.
- Mode / operation: `<existing MODE or SYNTHESIS; requested alias or operation>`.
- Acceptance: `<happy path, boundary, and realistic failure criteria>`.
- Required evidence: `<commands, manual checks, device or external checks>`.
- Review / release constraints: `<required reviewers and protected actions>`.
- Repo / branch / commit / worktree: `<actual values and dirty files, or unavailable>`.

## Evidence and acceptance

Label evidence: VERIFIED means actually checked; REPORTED means a source claim; ESTIMATED means an assumption/calculation; HYPOTHESIS means a testable belief; UNKNOWN/PENDING means not established.

Acceptance uses PASS, FAIL, or PENDING. PENDING is not PASS.

| Criterion | Verdict | Evidence label and source | Actual result / remaining gap |
| --- | --- | --- | --- |
| `<observable criterion>` | PENDING | UNKNOWN/PENDING | `<check still required>` |

Software checks do not establish hardware qualification, clinical validation, paid demand, production readiness, or qualified human security approval.

## Decisions and next action

- Decision and reason: `<chosen approach, evidence, constraints>`.
- Open risks / external evidence: `<remaining gaps and owner>`.
- Smallest next action: `<one action and its success criterion>`.

## Resume prompt

Resume `<Project Name>`, dated `<date/time/timezone>`, in `<environment and actual root>`. Read AGENTS.md, applicable scoped instructions, this state record, and the linked task sources. The authorized outcome is `<outcome>`; allowed changes are `<scope>`; exclusions and review gates are `<constraints>`. Current branch/commit and worktree are `<state>`. Completed work is `<artifacts>`. Actual checks/results are `<evidence>`; unresolved work and physical/external evidence are `<gaps>`. Next complete `<smallest action>` and verify `<success criterion>`. Recheck current files and Git state before editing. Do not assume publication or further authority.
