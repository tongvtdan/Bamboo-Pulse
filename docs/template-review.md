# Template review and maintenance

Reviewed on 2026-10-23. This is a documentation review, not evidence that a generated application passes checks.

## Findings and changes

| Finding | User impact | Resolution |
| --- | --- | --- |
| No canonical request aliases or operation boundaries | A diagnosis or release check could be mistaken for permission to implement or publish | SHORTCUTS.md defines operation scope; reusable requests add outcome/failure/evidence structure |
| No shared naming or assignment record | Platforms could allocate duplicate numbers or claim an unverified rename | CHAT_NAMING.md owns policy; PROJECT_STATE.md owns confirmation and assignment evidence |
| Tool adapters duplicated product/architecture rules | Instructions can drift as a project evolves | Thin adapters link to canonical sources |
| Placeholder-only guidance | New users must invent what a completed contract looks like | Trail Log provides one fictional example across the document set |
| No explicit review ownership or writer transfer | Concurrent edits or self-review can be presented as independent review | Development guide defines one writer and honest reviewer attribution |
| Completion criteria allowed a documented gap to count as done | Unverified behavior could be reported completed | Acceptance gaps remain FAIL/PENDING until resolved or explicitly descoped |
| CI check names did not match the starter job | Branch protection and completion claims could reference nonexistent checks | Use lint-test-build and explicitly configure the opt-in starter |
| Runtime assumptions were unclear | A workflow document could be mistaken for an installed autonomous service | WORKFLOW.md identifies the frontmatter as an operating contract |

The reference documents were used for reusable operating patterns only. Product-specific architecture, customer data, production names, and domain claims are not copied into this template.

## Maintaining the template

Before changing a shared policy, update its canonical source and inspect adapters/callers for conflicting copies. Check internal links and sample consistency, required CI names, operation permissions, naming edge cases, and diff whitespace.

Test the instructions conceptually against: a missing prefix; an archived higher number; an unavailable title setter; a duplicate assignment; a read-only investigation; a separately authorized fix; a failed save; a pending device check; and an unapproved release action.

Application commands and sample outcomes must remain explicitly fictional until a real project implements and verifies them.

## Evidence for this revision

VERIFIED on 2026-10-23: a local Python standard-library scan checked 20 Markdown files, 84 relative links/anchors, all 18 aliases, required paths, fenced-block balance, trailing whitespace, starter CI job consistency, and accidental private-project identifiers. It exited 0 after correcting one example anchor. git diff --check also exited 0.

Same-agent self-review assessed the naming and operation scenarios above. No independent reviewer, application build/test run, physical validation, paid-demand validation, or release approval is claimed. The template has no sample application to execute.

## Post-merge review

The follow-up review found and corrected four adoption defects:

- P2: Unescaped angle-bracket placeholders in Markdown tables, headings, and prose could render as HTML and disappear. Code spans now preserve them, including project identity, commands, state fields, and sample URLs.
- P2: CI setup ambiguously referred to an enabled field. Instructions now identify `ci.enabled` in WORKFLOW.md as documentation only and explicitly exclude an `enabled` key in GitHub Actions YAML.
- P2: SPEC.md still required status labels after allowing board-only tracking. Ready/review states now use the configured single authority, and PROJECT_STATE.md records it.
- P2: Chat numbers were reserved only after renaming, leaving a race between sessions. Exclusive writer ownership and a recorded reservation now precede the native rename; unavailable ownership skips allocation and failed attempts keep their reservation.

VERIFIED: GitHub's GFM renderer returned visible literal project, outcome, path, and task placeholders from the corrected AGENTS.md and PROJECT_STATE.md. Local checks cover links, aliases, whitespace, unescaped prose placeholders, single-authority status rules, and reservation ordering. This follow-up remains same-agent review; application execution and independent review are not claimed.

## Merge validation

The template now includes a standard-library Python validator and a read-only GitHub Actions workflow. The validator checks required paths, relative links/anchors, visible placeholders, whitespace, and CI starter references while accepting intentional configured placeholders in code spans. README.md documents the local command and how to remove/adapt template-maintenance checks when starting a real product.
