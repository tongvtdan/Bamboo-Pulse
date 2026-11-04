# Bamboo Pulse contributor instructions

Author · [Dantino](https://dantino.vn)

Read the [spec](SPEC.md), [workflow](WORKFLOW.md), [design](DESIGN.md) for UI work, and the relevant source and tests. The [README](README.md) owns the runnable commands. [Shortcuts](SHORTCUTS.md) define task scope. Record verified work separately from assumptions.

Keep local observations read-only. Reject invalid, ambiguous, stale or mismatched session evidence. Preview is explicitly synthetic. Chat navigation requires a user action. Never log private chat data. Preserve current-user socket checks, bounded input, setup consent, safe retries, and restoration of user-owned configuration.

Use temporary sockets and synthetic homes in tests. Avoid broad refactors. Keep one writer per shared file and preserve unrelated changes. Disclose failed and unrun checks. Obtain human review for changes to security or privacy boundaries. Building and testing do not authorize signing, installation, pushing or publishing.
