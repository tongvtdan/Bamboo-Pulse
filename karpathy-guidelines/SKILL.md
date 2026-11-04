---
name: karpathy-guidelines
description: Behavioral guardrails for AI coding work. Use when writing, reviewing, debugging, refactoring, or planning code changes where the agent should avoid wrong assumptions, overengineering, drive-by edits, or unverifiable completion.
---

# Karpathy Guidelines

Use this skill as a quality gate for non-trivial `<Project Name>` coding, debugging, refactoring, review, or architecture work. Bias toward explicit assumptions, simple code, surgical diffs, and verified outcomes.

## Operating Loop

1. Define the user outcome and success criteria.
2. Surface assumptions that affect scope, data, safety, correctness, or fidelity of generated artifacts.
3. Choose the smallest implementation that satisfies the outcome.
4. Change only files and lines that trace to the request.
5. Verify with the narrowest meaningful test or command.
6. Report what changed, what passed, and any residual risk.

## Simplicity First

- Do not add speculative features, extension points, configuration systems, or new packages.
- Do not introduce an abstraction for a single caller unless it removes real local complexity.
- Prefer existing project patterns before new structure.
- Keep error handling grounded in realistic failure modes for this product (`<failure mode 1>`, `<failure mode 2>`, `<failure mode 3>`).
- If the solution feels large relative to the request, reduce scope before editing.

## Surgical Changes

- Match surrounding style.
- Do not reformat, rename, or refactor adjacent code as a side effect.
- Remove unused code only when your change made it unused.
- Mention unrelated concerns in the final handoff instead of editing them.

## Architectural Boundaries

These are hard constraints — do not cross them without an explicit user decision:

- **State**: `<where state lives, e.g. all application state lives in App.jsx / a specific store>`. Do not move state to new context providers or reducers without discussion.
- **Core logic**: `<where the core business/domain math lives, e.g. exporters.js, domain/>`. Keep these functions pure and deterministic where possible.
- **Styles**: reference design tokens via `<token mechanism, e.g. var(--token) from styles.css>`. Never inline color or spacing values.
- **Client/server boundary**: `<state the boundary, e.g. no backend calls / backend calls only through the API layer>`.
- **Dependencies**: do not add new packages without discussing the tradeoff first.

## Correctness Safety Rule

When a value or state cannot be determined confidently, default to the conservative/safe outcome (`<e.g. OPEN, unknown, blocked>`) — never to the optimistic outcome (`<e.g. OK, valid, approved>`). A false positive on `<the domain output that matters, e.g. an inspection report, a financial calculation, a compliance check>` is a trust failure.

## Project Fit

Prioritize work that improves one of:

- **Trust**: `<correctness area 1>`
- **Distribution**: `<export/share/artifact quality area>`
- **Activation**: `<time-to-first-value area>`

Challenge work that does not improve one of those outcomes.

## High-Risk Areas

Extra care required before changing these — manually verify all branches after any edit:

- `<critical function 1>` — `<what it computes and why it's risky>`
- `<critical function 2>` — `<what it computes and why it's risky>`
- `<critical export/artifact function>` — `<what could silently go wrong>`

## Examples

Read `references/examples.md` when a task involves ambiguous implementation, refactoring, review, or broad changes.
