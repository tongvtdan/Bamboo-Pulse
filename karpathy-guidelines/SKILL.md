---
name: karpathy-guidelines
description: Behavioral guardrails for AI coding work. Use when writing, reviewing, debugging, refactoring, or planning code changes where the agent should avoid wrong assumptions, overengineering, drive-by edits, or unverifiable completion.
---

# Karpathy Guidelines

Use this skill as a quality gate for non-trivial `Bamboo Pulse` coding, debugging, refactoring, review, or architecture work. Bias toward explicit assumptions, simple code, surgical diffs, and verified outcomes.

## Implementation

Trace the normal entry point and one failing case before editing. Prefer a small correction in the owning app, core or runtime component. Keep unrelated formatting and generated outputs out of the diff. Verify the observable result and document the limits of the checks. See [examples](references/examples.md).
