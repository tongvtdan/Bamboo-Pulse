# Chat shortcuts

These are natural-language request conventions. They are not installed slash commands, shell commands, product keyboard shortcuts, scheduled jobs, or permission grants.

Match the first word case-insensitively. Text after it defines the target and constraints. Resolve a missing target only from established task context; otherwise ask one concise question. Never invent a feature or failure. If there is no diff for a diff-based review, report that and request a target.

## Request catalogue

| Alias | Operation and default target | Allowed changes |
| --- | --- | --- |
| /Whatnext | Inspect current state, spec, and available backlog; recommend one achievable slice | Read-only |
| /Research | Research the supplied question and cite current sources; distinguish findings from inference | Read-only |
| /Explain | Explain a supplied component or behavior from code and call paths | Read-only |
| /Plan | Define scope, dependencies, acceptance, failure cases, and checks for the requested outcome | Plan in response; save a document only if requested |
| /Build | Implement the specified behavior within its acceptance criteria | Scoped source/docs edits and relevant verification |
| /Investigate | Reproduce or trace the supplied symptom; report cause, evidence, and smallest fix | Diagnostics only; no implementation |
| /Fix | Reproduce and minimally correct the specified failure | Scoped edits and regression verification |
| /Test | Run existing checks for the target or current diff | Test outputs only; no source edits |
| /Addtests | Add missing tests derived from the behavior contract | Scoped test edits; no unrelated production changes |
| /Review | Audit the target or current diff and affected call paths; findings first with locations | Read-only |
| /Security | Assess security/privacy boundaries, misuse paths, and missing evidence | Read-only |
| /Critic | Challenge the proposed decision using explicit risks and disconfirming evidence | Read-only |
| /QA | Assess the slice against acceptance, including failure paths | PASS/FAIL/PENDING report; no source edits |
| /Release | Assess the branch or commit against documented release gates | Read-only readiness assessment |
| /Team | Propose roles, ownership, review boundaries, and integration checks | Coordination plan only unless delegation is separately authorized |
| /Decision | Compare relevant options, recommend one, and state evidence and tradeoffs | Read-only; save only if requested |
| /Status | Report current outcome, blocker, and next action in three bullets | Read-only |
| /Handoff | Summarize dated state, artifacts, checks, open work, and a self-contained resume prompt | Response only unless saving is requested |

Local artifacts from safe test runs are permitted; no alias authorizes commits, pushes, issue/PR changes, merges, deployment, spending, messages, or destructive operations by itself. Those require authority from the actual task or established project policy. Preserve existing security and human review gates.

A compound request is interpreted as a sequence: "/Review the docs, then update the naming rules" authorizes the review followed by the explicitly requested documentation edits.

See [Bamboo Pulse examples](docs/delivery/reusable-requests.md).
