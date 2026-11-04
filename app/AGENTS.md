---
description: App-level guide for agents working inside <app_folder>.
alwaysApply: true
---

# AGENTS.md

This file orients coding agents working in the main `<Project Name>` application.

For product policy, follow the root `../AGENTS.md` first. This nested guide wins only for exact code placement, commands, generated files, and app-specific workflow.

Use the canonical [shortcuts](../SHORTCUTS.md), [naming policy](../CHAT_NAMING.md), [project state](../PROJECT_STATE.md), and [development ownership](../docs/delivery/development-team.md). Do not duplicate them here. If this file moves deeper than one directory below the root, repair these relative links.

The Flutter-style layout below is illustrative, not an instruction to restructure another stack. [Trail Log](../examples/trail-log.md) shows a fictional app example.

## Project Summary

`<Project Name>` is `<specific category>` for `<target user>`.

Primary goals when editing:

- preserve `<core product framing>`
- shorten time to `<first value moment>`
- keep claims conservative and evidence-backed
- favor local-first, privacy-friendly behavior
- avoid breaking the main platform workflow

## Repo Layout

Inside this app:

- `lib/app/`: bootstrap, root app widget, routing
- `lib/core/`: shared infrastructure, database, analytics, notifications, theme, widgets, constants
- `lib/domain/`: cross-feature domain models and logic
- `lib/features/`: user-facing feature areas
- `lib/l10n/`: localization source and generated files, if used
- `test/`: focused regression, unit, and widget tests

Adjust this section to the actual app structure.

## Current Architecture Reality

The root docs may describe a clean layered architecture. The live codebase may only partially enforce it.

Practical guidance:

- follow the existing local structure in the area you touch
- prefer feature-local changes over broad refactors unless explicitly requested
- keep business logic out of widgets when reasonable
- use the state management already present in the repo
- treat the documented architecture as direction, not as a reason to reorganize during small fixes

## Current Product Priority

The highest-leverage product work is:

```text
<current ship path>
```

Prefer work that improves one of:

- first-session activation
- recurring loop completion
- data trust
- entitlement or paywall conversion after value
- distribution artifact

## Tech Stack

- `<Frontend framework and version>`
- `<State management>`
- `<Routing>`
- `<Local persistence>`
- `<Backend/sync>`
- `<Subscriptions/payments>`
- `<Notifications/device APIs>`
- `<Localization>`

## Commands

Run commands from this folder unless a task clearly belongs elsewhere.

Core commands:

- `<install command>`
- `<analyze/lint command>`
- `<test command>`
- `<run command>`

Generated code:

- `<codegen command>`
- `<localization command>`

Release asset commands, if needed:

- `<icon/splash/build command>`

After configuration, keep these commands aligned with the active CI workflow. The template ships an opt-in `.github/workflows/ci.yml.example`; do not claim it runs before configuration.

## Generated Files

Do not hand-edit generated artifacts unless the user explicitly asks for it.

Generated or generated-adjacent files currently tracked in git include:

- `<generated file>`
- `<generated file>`

When changing database/schema/source models:

- edit source files
- regenerate generated output
- run targeted tests

When changing UI copy:

- update source copy/localization files
- regenerate localization if required
- do not hardcode new user-facing strings if localized strings are appropriate

## Testing Expectations

At minimum, after meaningful app changes, run:

- `<analyze/lint command>`
- `<test command>`

If you touch routing, notifications, persistence, billing, hardware, sync, or logic-heavy flows, prefer adding or updating tests near the affected area. A failing check in CI blocks merge.

## Editing Guidance

- keep changes scoped
- do not remove or rewrite large document sets unless requested
- do not rename feature folders casually
- preserve supported localization
- keep optional user data optional in product language and logic
- avoid unsupported safety, health, finance, legal, or AI-certainty claims

## Known Codebase Notes

- `<note about generated files>`
- `<note about architecture mismatch>`
- `<note about current technical debt>`
- current git status may include unrelated changes; do not revert user work you did not create

## Safe Contribution Strategy

When working on a task:

1. inspect the nearest feature, provider, repository, DAO, widget, or service before changing patterns
2. check whether strings belong in localization/copy files
3. check whether a data model change requires generation or migration
4. run analysis/tests after edits when feasible
5. summarize assumptions around unfinished or placeholder product surfaces
6. open the PR early as a draft if the issue is large, so CI and reviewers can track progress

## Spec Workflow

Use the root `SPEC.md` when turning product work into GitHub issues.

Issue mapping:

- one GitHub Project = active release or initiative
- one Epic label = product loop or risk area
- one Issue = independently shippable slice sized roughly 0.5-2 days

Every issue should state whether it improves activation, retention, revenue, trust, or distribution. If it does not improve one of those, challenge the scope before building.

## File Placement Heuristics

Use these defaults unless the surrounding code suggests otherwise:

- new app-wide infrastructure: `lib/core/`
- new feature screens/widgets/state: corresponding folder under `lib/features/`
- cross-feature business models or rules: `lib/domain/`
- product or architecture docs: `docs/` or root docs

## Non-Goals For Small Tasks

Avoid bundling in unrelated cleanup such as:

- reorganizing the entire feature tree to match the ideal architecture
- consolidating all duplicate widget concepts in one pass
- changing pricing, positioning, or safety messaging without explicit direction
- replacing local-first flows with backend-required flows
