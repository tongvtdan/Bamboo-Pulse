# Project Agent Workflow Template

Start a product project with shared instructions for coding agents, a small issue/PR workflow, and explicit evidence for completion.

For a filled-in example, read [Trail Log](examples/trail-log.md), a fictional offline packing-checklist app. Product names, prefixes, issue numbers, metrics, and results there are illustrative; they are not live configuration.

## Start a new project

1. Choose **Use this template** on the repository to create a new repo, or copy the files (including hidden .github files) into an existing project. For an existing repo, inspect overlapping files and merge instructions instead of overwriting them.
2. Read the Trail Log example, then fill actual product, stack, ownership, commands, and non-goals in [AGENTS.md](AGENTS.md). Delete irrelevant sections.
3. Fill [DESIGN.md](DESIGN.md) with the actual visual/interaction contract. It is a detailed reference; keep only what the MVP needs.
4. Turn one outcome into an independently verifiable slice in [SPEC.md](SPEC.md).
5. Configure [WORKFLOW.md](WORKFLOW.md) for the actual repository, default branch, board, and required checks. Its frontmatter is documentation, not an installed automation.
6. Fill [PROJECT_STATE.md](PROJECT_STATE.md) from current evidence. Leave the prefix UNCONFIRMED until the owner confirms it under [CHAT_NAMING.md](CHAT_NAMING.md). Examples never assign a real prefix or sequence.
7. Review [SHORTCUTS.md](SHORTCUTS.md) once. These aliases work through project instructions; they are not registered native slash commands.
8. Adapt [app/AGENTS.md](app/AGENTS.md) only if the app folder has different placement or command rules. Rename/move it to the actual app root and correct its relative links; remove it when unnecessary.
9. Configure the opt-in [.github/workflows/ci.yml.example](.github/workflows/ci.yml.example), then rename it to ci.yml. In WORKFLOW.md, set the documentation field `ci.enabled` to `true`; do not add an `enabled` key to the GitHub Actions YAML. Require the actual lint-test-build check and any project-specific gates; preserve existing protection/review requirements.
10. Replace the template README with a product README when ready. Keep the fictional example as a reference or remove it and update its links.

A template-generated repo copies files, not the original repo's issues, board configuration, branch protection, or external integrations. Configure and verify those in the new project.

## What each file owns

| File | Responsibility | Fictional Trail Log example |
| --- | --- | --- |
| [AGENTS.md](AGENTS.md) | Product contract, architecture boundaries, actual commands | Preserve offline checklist saves |
| [CODEX.md](CODEX.md) / [CLAUDE.md](CLAUDE.md) | Thin tool orientation pointing to shared rules | Same save contract in every coding client |
| [SHORTCUTS.md](SHORTCUTS.md) | Aliases, operation permissions, MODE perspectives | /Investigate a restart loss; /Fix the specified cause |
| [CHAT_NAMING.md](CHAT_NAMING.md) | Confirmed prefix, environment marker, shared counter policy | TL-X-01, TL-C-02, TL-W-03 |
| [PROJECT_STATE.md](PROJECT_STATE.md) | Identity/confirmation, assignments, task/evidence/resume | Save failure is PENDING until checked |
| [DESIGN.md](DESIGN.md) | UI, tokens, states, copy, accessibility | Visible saving/saved/failed-save states |
| [SPEC.md](SPEC.md) | Scope, acceptance, issue-sized work | Preserve packed flags across restart |
| [WORKFLOW.md](WORKFLOW.md) | Issue/branch/PR/review/release loop | Review evidence before closing the issue |
| [Request library](docs/delivery/reusable-requests.md) | Reusable outcome/scope/failure/evidence requests | Verify failed-save and retry behavior |
| [Development guide](docs/delivery/development-team.md) | One writer, review, ownership transfer | Separate implementation from assigned QA |
| [Guardrails](karpathy-guidelines/SKILL.md) | Simple changes, explicit assumptions, verified outcomes | Reject blank items at the owning boundary |
| [.github/ISSUE_TEMPLATE/feature_request.md](.github/ISSUE_TEMPLATE/feature_request.md) | Feature issue body | Outcome, non-goals, failure acceptance |
| [.github/ISSUE_TEMPLATE/bug_report.md](.github/ISSUE_TEMPLATE/bug_report.md) | Bug issue body | Reproducer and regression evidence |
| [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md) | PR description | Actual commands and remaining gaps |

Keep one source per policy. Adapters link to canonical docs instead of copying them. Flag conflicts before acting; do not silently weaken a contract.

## Naming and alias behavior

Names use `<PREFIX>-<PLATFORM>-<NN> | <Task or Subsystem>`. X is Codex, C is ChatGPT Chat, W is ChatGPT Work. A project has one counter across those environments. Confirm a prefix once, inspect available inventories/archives/linked assignments, preserve existing numbers, and verify a native saved title before claiming success.

Without supported tools or sufficient identity/numbering evidence, continue the substantive task silently. A heading is not a title change.

Read-only aliases inspect and explain. /Build and /Fix authorize scoped implementation; /Addtests requests scoped tests; /Release assesses readiness; /Team proposes coordination. External writes, spawning agents, messages, commits, pushes, merges, deployment, and spending require authority from the actual task or project policy.

## GitHub Project setup

Use a user- or organization-owned Project. Reuse an existing board when appropriate; linking it does not automatically add all issues.

Example shell commands below require replacing every angle-bracket placeholder before use:

```sh
gh auth login
gh project create --owner <owner> --title "<Project Name> - <initiative>"
gh project link <project-number> --owner <owner> --repo <owner>/<repo>
gh project field-list <project-number> --owner <owner>
```

Inspect the existing Status field first. Configure its options in the UI instead of creating a duplicate. Suggested states: Backlog, Ready, In Progress, In Review, Done, Parked. Record the chosen field/label authority in WORKFLOW.md.

User board URLs follow `https://github.com/users/<owner>/projects/<number>`; organization board URLs follow `https://github.com/orgs/<owner>/projects/<number>`. Save the verified URL in project configuration. New boards, issues, and status changes still require task authority.

## Before first implementation

- Fill product/architecture/command placeholders; leave unverified claims explicitly pending.
- Confirm aliases and tool adapters agree about permissions and human review.
- Confirm naming examples are not live assignments.
- Make the actual app folder, paths, links, and commands match the repo.
- Configure/verify CI before requiring its job; retain existing security gates.
- Define one user outcome with normal, boundary, and failure acceptance.
- Record actual evidence rather than copying sample results.

Useful placeholder scan:

```sh
rg -n '<[^>]+>|TODO|TBD|FIXME|ISSUE_NUMBER' AGENTS.md PROJECT_STATE.md SPEC.md WORKFLOW.md DESIGN.md app .github
git diff --check
```

A placeholder scan helps setup; it is not a complete validation or evidence that the app works. Sample app commands are intentionally not runnable in this docs-only repository.

## Validate the template

Run the template-maintenance checks without installing dependencies:

```sh
python3 scripts/validate_template.py
```

The active `validate-template.yml` workflow runs this command for pull requests and pushes to main. It checks required template files, relative links/heading anchors, visible placeholders, whitespace, and CI starter references. The app CI starter remains opt-in.

When adopting the kit for a product, remove or adapt this maintenance script and its workflow together before deleting template-only files. Configure the product's own app checks separately; template validation is not an application test.
