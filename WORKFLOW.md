---
tracker:
  kind: github
  repo: "<owner>/<repo>"
  project_url: "<verified GitHub Project URL>"
  active_labels:
    - status:ready
    - status:in-progress
  review_label: status:in-review
branch:
  naming: "<type>/<issue-number>-<short-slug>"
  base: main
pull_request:
  draft_until_ready: true
  require_review: true
  close_keyword: "Closes #<issue-number>"
ci:
  starter_file: .github/workflows/ci.yml.example
  workflow_file: .github/workflows/ci.yml
  enabled: false
  required_checks:
    - lint-test-build
agent:
  max_concurrent_agents: 1
  max_turns: 8
  max_retry_backoff_ms: 300000
---

# Issue and delivery workflow

This is a documented operating contract. Frontmatter does not install a scheduler, GitHub integration, or autonomous runner. Configure supported integrations separately; never store secrets here.

Read [AGENTS.md](AGENTS.md), [the guardrails](karpathy-guidelines/SKILL.md), relevant [SPEC.md](SPEC.md) sections, and [PROJECT_STATE.md](PROJECT_STATE.md). [SHORTCUTS.md](SHORTCUTS.md) owns operation permissions; [the development guide](docs/delivery/development-team.md) owns writer/reviewer coordination.

## Project configuration

Record the actual repository, default branch, implementation root, board, and runnable commands. Choose board Status or status labels as the authoritative state; synchronize a second surface only when explicitly configured.

When using board Status, move the item through its configured options; `status:*` labels in the frontmatter are an optional label-based mapping, not a second required workflow. When using labels, create the chosen labels first and replace the previous status label on each transition. Record the chosen source in PROJECT_STATE.md; required checks and review apply independently of tracker choice.

Use `https://github.com/users/<owner>/projects/<number>` for personal projects or `https://github.com/orgs/<owner>/projects/<number>` for organizations. Linking a repository does not automatically add all issues; use configured automation or explicitly add authorized items.

Configure ci.yml.example and rename it to ci.yml. Set `ci.enabled: true` in this document's frontmatter only; it records setup state and does not control GitHub Actions. Do not add an `enabled` field to the Actions YAML. Verify the actual lint-test-build job before requiring it. Preserve existing required checks and branch protection. The disabled starter is not permission to disable a configured project gate.

## Read-only requests

Review, Explain, Investigate, Research, Security, QA, Status, Handoff, and Release inspect evidence without implementation or external mutations. /Plan and /Team produce plans unless the actual request authorizes more.

A compound request such as "review then update the docs" authorizes the specified edits. No alias by itself grants additional authority.

## Implementation loop

1. Read the actual task and linked sources. Use an existing issue when available; create/update issues or board items only under established task authorization.
2. Establish outcome, scope/non-goals, owner/writer, acceptance/failure cases, checks, and review. Challenge weak product rationale and recommend a smaller slice.
3. Set authorized task state to In Progress; record unavailable external state as PENDING without claiming a successful mutation.
4. Inspect current files, Git state, and applicable scoped guides. Branch from main unless the actual configured base differs. Use `<type>/<issue-number>-<short-slug>`, or an owner-approved task slug when no issue exists.
5. Implement one independently verifiable slice with one writer per shared artifact.
6. Run relevant checks; report PASS, FAIL, or PENDING for each acceptance criterion with actual evidence.
7. When publishing is authorized, open/update a draft PR linked to the issue. In a submitted PR body use a real closing keyword such as Closes #12 without code formatting.
8. After required checks, present the reviewable result and set the authorized state to In Review. Report changed artifacts, actual checks/results, unresolved findings, and next risk.
9. Do not self-merge without explicit owner solo-merge authority. Sensitive data, entitlements, payments, notifications, hardware, migrations, or user-affecting AI decisions require human review.

## Verification ladder

| Surface | Evidence |
| --- | --- |
| Docs | Internal links, examples, permission/naming consistency, diff whitespace |
| Narrow behavior | Closest relevant test plus user-visible path |
| Persistence | Normal, empty/corrupt, failed-save, restart/retry, migration cases as relevant |
| UI/copy | Tokens, accessibility, localization, empty/loading/error states |
| Export/artifact | Actual content/structure plus relevant manual/visual inspection |
| Hardware | Software checks plus actual or pending physical evidence |
| Shared contract | Affected callers and configured broader checks |

Use actual commands from root/scoped AGENTS.md; never report illustrative commands as executed. Record relevant tool/runtime versions. Software checks do not prove hardware qualification, clinical validation, paid demand, or human security approval.

## Review, completion, and release

In Review means implementation awaits required review; open findings and evidence gaps stay explicit. Done requires satisfied acceptance, recorded verification, and merge or explicit acceptance under project policy. Merely documenting a gap does not satisfy it.

PR closing keywords automatically close linked issues when merged into the default branch. For other targets, close only after required default-branch integration or an authorized manual decision.

Release assessment checks evidence and gates; it does not authorize publication/deployment. Preserve configured producer/verifier/protected-execution authorities, physical human ACCEPT, consume-before-sign, replay/policy gates, and disabled approval controls.

## Fictional example and handoff

Trail Log issue #12 preserves packed flags after restart. Use feature/12-restart-persistence from main; verify restart, empty-list, failed-save, and retry behavior. Acceptance remains PENDING until actually checked. See the [walkthrough](examples/trail-log.md#workflowmd-example).

A handoff records dated scope/actual changes, environment, artifacts/repo/branch/commit, worktree state, decisions, actual checks/results, open physical/external evidence, one next success criterion, and a self-contained resume prompt. Use [PROJECT_STATE.md](PROJECT_STATE.md) when saving is authorized.
