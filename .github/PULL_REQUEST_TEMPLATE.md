## Summary

`<1-3 sentences on what changed and why>`

Closes #ISSUE_NUMBER

Replace ISSUE_NUMBER with a real issue number in plain text, for example `Closes #12`. Remove the line when no issue exists.

## Changes

- `<change 1>`
- `<change 2>`

## Product Rule

Which of activation, retention, revenue, trust, or distribution this improves, and why now.

## Verification

Commands run and their result:

```sh
<install command>
<analyze/lint command>
<test command>
```

- [ ] Verified the user-visible path manually
- [ ] Existing tests pass, or known unrelated failures are documented below
- [ ] Added or updated tests for non-trivial risk areas
- [ ] Verified realistic failure behavior, or marked the required evidence PENDING

Fictional example: Trail Log preserves the last saved checklist after an injected save failure. Record the actual command/result here; the example itself is not evidence.

## Screenshots / Recordings

`<attach if the change is user-visible>`

## Risk / Follow-Up

`<what could still break, what to watch after merge, or the recommended next issue>`

## Checklist

- [ ] PR title and description are clear enough for a reviewer with no prior context
- [ ] Copy/localization updated if user-facing strings changed
- [ ] No unrelated changes bundled in
- [ ] Configured required CI is green (starter job: `lint-test-build`)
- [ ] Required human review and protected-action gates remain intact
