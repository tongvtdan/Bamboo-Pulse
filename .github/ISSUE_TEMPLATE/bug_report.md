---
name: Bug report
about: Report something that is broken in <Project Name>
title: "bug: <short description>"
labels: ["trust"]
assignees: []
---

## Outcome

What user-visible behavior is wrong, and what should happen instead?

## Scope

- In: `<the specific broken behavior>`
- Out: `<related behavior that is intentionally not covered by this issue>`

## Steps To Reproduce

1. `<step 1>`
2. `<step 2>`
3. `<step 3>`

## Expected Behavior

`<what should have happened>`

## Actual Behavior

`<what happened instead, including error messages or screenshots>`

## Environment

- App version / commit: `<version or SHA>`
- Platform: `<OS/browser/device>`
- Build: `<dev | preview | production>`

## Product Rule

Why this matters for activation, retention, revenue, trust, or distribution.

## Implementation Notes

Likely files, providers, DAOs, routes, or exports involved (fill in once triaged).

## Acceptance Criteria

- [ ] Root cause identified
- [ ] Fix verified against the repro steps above
- [ ] Regression test added if the risk is non-trivial
- [ ] Analyze/lint passes
- [ ] CI passes on the PR

## Risks

What could regress or remain unfixed after this change?
