# Chat shortcuts

These are natural-language request conventions. They are not installed slash commands, shell commands, product keyboard shortcuts, scheduled jobs, or permission grants.

Match the first word case-insensitively. Text after it defines the target and constraints. Resolve a missing target only from established task context; otherwise ask one concise question. Never invent a feature or failure. If there is no diff for a diff-based review, report that and request a target.

## Request catalogue

| Alias | Operation and default target | Allowed changes | Fictional Trail Log request |
| --- | --- | --- | --- |
| /Whatnext | Inspect current state, spec, and available backlog; recommend one achievable slice | Read-only | /Whatnext shorten time to first packing list |
| /Research | Research the supplied question and cite current sources; distinguish findings from inference | Read-only | /Research offline export approaches for packing lists |
| /Explain | Explain a supplied component or behavior from code and call paths | Read-only | /Explain how packing-list persistence handles restart |
| /Plan | Define scope, dependencies, acceptance, failure cases, and checks for the requested outcome | Plan in response; save a document only if requested | /Plan export a packing checklist |
| /Build | Implement the specified behavior within its acceptance criteria | Scoped source/docs edits and relevant verification | /Build let users check packed items while offline |
| /Investigate | Reproduce or trace the supplied symptom; report cause, evidence, and smallest fix | Diagnostics only; no implementation | /Investigate saved items disappearing after restart |
| /Fix | Reproduce and minimally correct the specified failure | Scoped edits and regression verification | /Fix empty item titles being saved |
| /Test | Run existing checks for the target or current diff | Test outputs only; no source edits | /Test packing-list persistence and restart behavior |
| /Addtests | Add missing tests derived from the behavior contract | Scoped test edits; no unrelated production changes | /Addtests duplicate item and failed-save cases |
| /Review | Audit the target or current diff and affected call paths; findings first with locations | Read-only | /Review local checklist storage changes |
| /Security | Assess security/privacy boundaries, misuse paths, and missing evidence | Read-only | /Security check whether exports expose private notes |
| /Critic | Challenge the proposed decision using explicit risks and disconfirming evidence | Read-only | /Critic adding social sharing before offline save works |
| /QA | Assess the slice against acceptance, including failure paths | PASS/FAIL/PENDING report; no source edits | /QA empty-list, failed-save, and restart cases |
| /Release | Assess the branch or commit against documented release gates | Read-only readiness assessment | /Release assess the current branch for offline-list reliability |
| /Team | Propose roles, ownership, review boundaries, and integration checks | Coordination plan only unless delegation is separately authorized | /Team plan ownership for storage and export |
| /Decision | Compare relevant options, recommend one, and state evidence and tradeoffs | Read-only; save only if requested | /Decision choose a checklist export format |
| /Status | Report current outcome, blocker, and next action in three bullets | Read-only | /Status |
| /Handoff | Summarize dated state, artifacts, checks, open work, and a self-contained resume prompt | Response only unless saving is requested | /Handoff |

Local artifacts from safe test runs are permitted; no alias authorizes commits, pushes, issue/PR changes, merges, deployment, spending, messages, or destructive operations by itself. Those require authority from the actual task or established project policy. Preserve existing security and human review gates.

A compound request is interpreted as a sequence: "/Review the docs, then update the naming rules" authorizes the review followed by the explicitly requested documentation edits.

## Modes select a perspective

Keep an existing project/task MODE. Otherwise default to SYNTHESIS. Modes may stack; they do not change operation permissions.

| Mode | Perspective | Trail Log example |
| --- | --- | --- |
| PRODUCT | User outcome, activation, retention, revenue | Reduce first-list setup steps |
| ARCHITECTURE | Boundaries, data flow, maintainability | Separate persistence from list rules |
| PATENT | Invention/IP questions and evidence needs | Identify a question needing qualified IP review |
| TRIZ | Contradictions and constrained invention | Reduce input effort while preserving useful detail |
| GROWTH | Distribution and conversion after value | Test demand for shareable list exports |
| PRETOTYPE | Cheapest credible test of an assumption | Observe users trying a paper packing checklist |
| CRITIC | Failure modes and contrary evidence | Test whether exports matter before building them |
| SYNTHESIS | Reconcile product, engineering, and growth | Choose the next independently verifiable slice |

Example: MODE PRODUCT + ARCHITECTURE with "/Plan offline list export" changes the planning perspective; it still authorizes planning only.

See the [request library](docs/delivery/reusable-requests.md) for reusable request structure and [Trail Log](examples/trail-log.md) for a complete fictional walkthrough.
