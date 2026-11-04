# `<Project Name>` SPEC

For a filled-in fictional slice, see [Trail Log](examples/trail-log.md#specmd-example). Example facts are not live backlog or verified evidence. [WORKFLOW.md](WORKFLOW.md) owns tracker/review rules, [SHORTCUTS.md](SHORTCUTS.md) owns operation permissions, and [PROJECT_STATE.md](PROJECT_STATE.md) records current evidence.

## Insight

The issue tracker should not become storage for vague app ideas. Every issue should map to a measurable product loop: activation, retention, revenue, trust, or distribution.

The current highest-leverage issue family is not "more features." It is `<strategic bottleneck>`.

## Decision

Use this spec as the execution bridge between project docs and GitHub Issues.

Issue hierarchy:

```text
Repo: <org>/<repo>
  -> GitHub Project: <Project Name> <release> - <initiative>
  -> Epic labels: activation, retention, trust, revenue, distribution, release
  -> Issues: shippable slices sized 0.5-2 days, each on its own branch and PR
```

Do not create issues larger than one independently verifiable product slice.

## Sync Model

### Project

Recommended GitHub Project:

```text
<Project Name> <release> - <initiative>
```

Project URL:

```text
https://github.com/users/<owner>/projects/<number>
```

For an organization, use `https://github.com/orgs/<owner>/projects/<number>` instead. Record the actual verified URL.

Repo:

```text
https://github.com/<org>/<repo>
```

Project outcome:

```text
<A measurable user/business outcome for this release>
```

Project success metrics:

- `<activation metric>`
- `<retention metric>`
- `<trust metric>`
- `<revenue metric>`
- `<distribution metric>`

### Epic Types

| Epic Label | Outcome | Owner Surface |
| --- | --- | --- |
| `epic:activation` `<name>` | User reaches first value faster | onboarding, home, setup |
| `epic:retention` `<name>` | User has a reason to return | reminders, streaks, weekly loop |
| `epic:trust` `<name>` | Claims and data are correct | calculations, persistence, outputs |
| `epic:revenue` `<name>` | User can pay after value is shown | entitlements, paywall, checkout |
| `epic:distribution` `<name>` | Product creates share or channel artifact | exports, referrals, store assets |
| `epic:release` `<name>` | Build is shippable | CI, tests, localization, routing, release checks |

### Labels

Recommended category/priority labels (create once in repo settings or via `gh label create`). The `status:*` labels below are optional: create/use them only when WORKFLOW.md selects labels as the status authority or explicitly configures synchronization.

- `activation`
- `retention`
- `revenue`
- `trust`
- `distribution`
- `release-blocker`
- `priority:p0`
- `priority:p1`
- `status:ready`
- `status:in-progress`
- `status:in-review`
- `status:parked`
- `<domain-label>`

## Issue Template

The canonical issue body lives in [.github/ISSUE_TEMPLATE/feature_request.md](.github/ISSUE_TEMPLATE/feature_request.md), a Markdown issue template. Its structure:

```markdown
## Outcome

What user or business behavior changes?

## Scope

- In:
- Out:

## Sources And Ownership

Current source files/contracts, owner, current writer, and required reviewers.

## Product Rule

Activation, retention, revenue, trust, or distribution reason.

## Implementation Notes

Likely files, providers, DAOs, routes, localization, APIs, migrations, or device surfaces.

## Acceptance Criteria

- [ ] User-visible behavior works
- [ ] Edge or empty state handled
- [ ] Realistic failure path preserves data and exposes an actionable error
- [ ] Copy/localization updated if needed
- [ ] Tests added or updated where risk is non-trivial
- [ ] Analyze/lint passes
- [ ] Tests pass or known unrelated failures are documented in the PR

## Analytics

Events to add or verify.

## Risks

What could break trust, data correctness, revenue, distribution, or release readiness?
```

## Current Execution Backlog

### P0-1: `<Issue Title>`

Epic:

```text
Activation: <Epic Name>
```

Outcome:

```text
<Concrete user outcome>
```

Scope:

- `<in scope item>`
- `<in scope item>`
- `<in scope item>`

Out:

- `<out of scope item>`
- `<out of scope item>`

Likely files:

- `<app_folder>/lib/features/<feature>/`
- `<app_folder>/lib/core/<area>/`
- `<app_folder>/test/<area>/`

Acceptance:

- `<acceptance criterion>`
- `<acceptance criterion>`
- `<acceptance criterion>`

Branch / PR:

```text
git checkout -b feature/<issue-number>-<short-slug>
gh pr create --fill --title "<Issue Title>" --body "Closes #<issue-number>"
```

### P0-2: `<Issue Title>`

Epic:

```text
Trust: <Epic Name>
```

Outcome:

```text
<Concrete trust/data outcome>
```

Scope:

- `<in scope item>`
- `<in scope item>`

Acceptance:

- `<acceptance criterion>`
- `<acceptance criterion>`

### P1-1: `<Issue Title>`

Epic:

```text
Revenue: <Epic Name>
```

Outcome:

```text
<Concrete revenue or monetization outcome>
```

Scope:

- `<in scope item>`
- `<in scope item>`

Acceptance:

- `<acceptance criterion>`
- `<acceptance criterion>`

## Status Rules

Use the single status authority configured in WORKFLOW.md and recorded in PROJECT_STATE.md: either the board Status field or status labels. Label names in parentheses below apply only to a configured label workflow; board-only projects do not require them.

- Backlog: not selected for current sprint
- Ready: clear scope and acceptance criteria (`status:ready`)
- In Progress: actively being implemented on a branch (`status:in-progress`)
- In Review: PR open, code complete, waiting for CI/review pass (`status:in-review`)
- Done: PR merged, issue auto-closed via `Closes #<number>`, verification noted in the PR
- Parked: valid but intentionally deferred (`status:parked`)

```mermaid
stateDiagram-v2
    [*] --> Backlog
    Backlog --> Ready: scope + acceptance criteria written
    Ready --> InProgress: branch created, configured state updated
    InProgress --> InReview: evidence ready for review, configured state updated
    InReview --> InProgress: changes requested
    InReview --> Done: PR approved + merged
    Backlog --> Parked: intentionally deferred
    Ready --> Parked: intentionally deferred
    Parked --> Backlog: reprioritized
    Done --> [*]
```

Do not close an issue as completed until acceptance criteria are satisfied and evidence is recorded. Writing down a gap does not satisfy it. Canceled or duplicate issues require an explicit reason and any replacement link.

For authorized implementation runs, follow WORKFLOW.md. Read-only aliases do not mutate issues, boards, or PRs. When tracker/PR publication is authorized:

- move the selected issue to the configured In Progress state and open a draft PR when a first reviewable change is available
- leave completed implementation work as an open PR with the issue's configured In Review state, not merged
- add a PR comment containing what changed, verification commands, pass/fail result, and next risk
- do not merge sensitive data, entitlement, payment, notification, migration, hardware, or AI-decision work directly; require human review

## Sprint Shape

Recommended first sprint:

```text
Sprint 1: <Theme>
  P0-1 <Issue>
  P0-2 <Issue>
  P0-3 <Issue>
```

Reason:

- directly improves `<activation/retention/revenue/trust/distribution>`
- validates `<key assumption>`
- removes `<major blocker>`

## Definition Of Ready

An issue is ready when it has:

- clear user outcome
- one owner surface
- explicit non-goals
- acceptance criteria
- likely file areas
- test expectation
- activation, retention, revenue, trust, or distribution rationale
- the configured Ready state (board Status or `status:ready` label, as selected in WORKFLOW.md)
- normal, boundary, and failure acceptance with required evidence and owner

## Definition Of Done

An issue is done when:

- the user-visible behavior works
- data is persisted or migrated safely if needed
- empty and error states are handled
- copy/localization is updated if needed
- analytics events are added or consciously deferred
- configured required CI checks pass on the PR (starter job: `lint-test-build`)
- at least one review approval is recorded (unless solo-merge is explicitly allowed)
- the PR is merged to the default branch and the issue is closed via a closing keyword, or the work is explicitly accepted under project policy

Evidence uses VERIFIED, REPORTED, ESTIMATED, HYPOTHESIS, or UNKNOWN/PENDING; acceptance uses PASS, FAIL, or PENDING. See PROJECT_STATE.md. Tests alone do not prove physical validation, paid demand, or release approval.

## Release Gate

Before public release work, verify:

- onboarding produces first-session value
- core loop is correct and repeatable
- product claims do not overpromise
- premium users have a working entitlement path if monetized
- locked paid actions have a clear upgrade path
- notifications are permission-aware if used
- public naming matches the brand
- `main` is green on CI and tagged for the release
