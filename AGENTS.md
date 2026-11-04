---
description: Root operating guide for agents working in the <Project Name> workspace.
alwaysApply: true
---

# Project operating contract

Resolve this template's placeholders before implementation. [Trail Log](examples/trail-log.md) is a fictional example, never an instruction to configure or rename a live project.

## Operating model and project memory

Balance product outcome, engineering simplicity, and growth. Prefer the smallest reliable slice that improves activation, retention, or revenue; explain how trust and distribution support those outcomes. Challenge scope without a clear product reason.

Default response: a concise title, insight, decision, execution, actual verification, and one next action. Scale ceremony to the task.

| Field | Value |
| --- | --- |
| Product/public promise | `<Project Name>`: `<specific user outcome>` |
| Public name/internal codename | `<Public Product Name>` / `<Internal Codename or same>` |
| Implementation root and stack | `<app_folder>/`; `<actual framework/runtime versions>` |
| Ship path | `<first input>` → `<first value>` → `<repeat use>` → `<paid/distribution moment>` |
| Non-goals | `<explicit exclusions and reopening condition>` |
| Repository/board | `<owner>/<repo>`; `<verified project URL>` |
| Naming and current task | [PROJECT_STATE.md](PROJECT_STATE.md) |

Fictional example: Trail Log helps hikers save a packing list offline. The current slice preserves packed flags across restart; accounts and sync are excluded. The example assigns no prefix to a real project.

## Required sources

Before substantial work read this contract, the nearest scoped AGENTS.md, [the guardrails](karpathy-guidelines/SKILL.md), [WORKFLOW.md](WORKFLOW.md), relevant [SPEC.md](SPEC.md) sections, and [project state](PROJECT_STATE.md). Read [DESIGN.md](DESIGN.md) for UI/copy work.

| Topic | Canonical owner |
| --- | --- |
| Product, architecture boundaries, actual commands | Root/scoped AGENTS.md |
| Aliases, MODE perspectives, operation permissions | [SHORTCUTS.md](SHORTCUTS.md) |
| Chat-title policy | [CHAT_NAMING.md](CHAT_NAMING.md) |
| Confirmed identity/prefix, assignments, task/evidence | [PROJECT_STATE.md](PROJECT_STATE.md) |
| Request structure and examples | [Request library](docs/delivery/reusable-requests.md) |
| Ownership transfer and review | [Development guide](docs/delivery/development-team.md) |
| Issue, PR, CI, review, and release gates | [WORKFLOW.md](WORKFLOW.md) |
| Fictional filled-in walkthrough | [Trail Log](examples/trail-log.md) |

Tool adapters link to these sources. Flag conflicting contracts; never silently rewrite one. Scoped guides refine local placement and commands without weakening root security/release gates. Explicit user scope and applicable project contracts govern.

## Task and evidence contract

Establish outcome, current sources, allowed/excluded changes, owner/writer, acceptance including realistic failure cases, required evidence, review, and constraints. A small edit needs a short response, not a planning document.

Read-only requests permit inspection and safe diagnostics. Build/Fix permit the stated changes. "Review then update" includes the explicitly requested edits. Follow SHORTCUTS.md for full permissions; no alias/MODE grants external writes, publication, messages, spending, or delegation by itself.

Preserve existing PRODUCT, ARCHITECTURE, PATENT, TRIZ, GROWTH, PRETOTYPE, CRITIC, and SYNTHESIS meanings and allow stacking. Default to SYNTHESIS only when no project/task mode is set.

Label claims VERIFIED, REPORTED, ESTIMATED, HYPOTHESIS, or UNKNOWN/PENDING. Acceptance is PASS, FAIL, or PENDING. Record actual commands/results and relevant versions. A build alone does not prove behavior or real-world readiness.

## Naming and shortcuts

Follow CHAT_NAMING.md and the confirmed identity/assignments in PROJECT_STATE.md. Format: `<PREFIX>-<PLATFORM>-<NN> | <Task or Subsystem>`; X = Codex, C = ChatGPT Chat, W = ChatGPT Work. Each project keeps one cross-platform counter.

Never infer a prefix or reuse assigned numbers. Preserve valid existing titles/numbers. Inspect available inventories, archives, linked platforms, and recorded assignments; recheck concurrency and verify the native saved title. If tooling/identity/safe numbering cannot be verified, continue substantive work silently. Naming never grants creating, messaging, moving, or bulk-renaming tasks.

Honor aliases case-insensitively. /Review audits; /Fix requests a scoped correction; /Test runs existing checks; /Addtests requests tests. Chat aliases and application keyboard shortcuts are separate.

## Architecture and ownership

Fill these boundaries using the actual codebase. Do not reorganize code to match an example map.

| Boundary | Contract to fill |
| --- | --- |
| UI/navigation | `<owning paths and existing patterns>` |
| State/domain | `<owner, invariants, pure logic boundaries>` |
| Persistence/migrations | `<source schema, storage API, migration rules>` |
| Client/server | `<offline requirements and explicit network/auth boundaries>` |
| Design/copy | `<tokens, localization, accessibility>` |
| Exports/devices/AI decisions | `<input/output contract and conservative failure states>` |
| Generated files | `<sources, commands, files not to edit>` |

Preserve user changes. Follow nearby code and existing dependencies. Explain a new dependency's necessity and maintenance cost; retain project approval requirements. Keep local-first behavior unless the task requires otherwise. Missing/ambiguous critical inputs remain unknown/pending rather than falsely successful.

Keep one writer at a time on shared artifacts. Use only necessary reviewers and label same-agent self-review honestly. Follow the development guide for ownership transfer.

## Commands and verification

Run app commands from `<app_folder>/`. Replace these with actual runnable commands:

- Install: `<install command>`.
- Analyze/lint: `<analyze/lint command>`.
- Targeted test: `<test command>`.
- Run/build: `<run command>` / `<build command>`.
- Generation/migration/localization: `<commands or not applicable>`.

The opt-in CI starter is .github/workflows/ci.yml.example. Configure before renaming to ci.yml; the starter check is lint-test-build. Keep required checks in WORKFLOW.md aligned with actual jobs.

For docs check links, examples, permission consistency, and diff whitespace. For code verify the user-visible path and closest meaningful regression checks. Expand checks when shared contracts change. Persistence, migrations, sync, entitlements, notifications, BLE/hardware, exports, routing, and user-affecting AI outputs need risk-appropriate evidence.

Never weaken CI, branch protection, human review, or protected-execution controls. Sensitive data, entitlements, payments, notifications, migrations, hardware, or user-affecting AI decisions require human review. Software tests do not establish hardware qualification, clinical validation, paid demand, or qualified human security sign-off.

## Completion and handoff

Report outcome, changed artifacts, acceptance PASS/FAIL/PENDING, actual evidence, open risks, and one next action. Save durable state only when authorized, using PROJECT_STATE.md rather than parallel logs.

A handoff includes date/timezone, project/environment, authorized scope/actual changes, artifact/repo/branch/commit links, worktree state, decisions, checks/results, pending physical/external evidence, next success criterion, and a self-contained resume prompt. Exclude secrets, raw patient/sensor data, and unrelated private details.
