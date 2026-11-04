# Chat naming

This file owns chat-title policy. [PROJECT_STATE.md](PROJECT_STATE.md) owns project identity, confirmation evidence, linked inventories, and recorded assignments. Naming never authorizes creating, messaging, moving, or bulk-renaming chats.

## Project configuration

Start with the project-state fields unresolved. Ask the owner to confirm a missing prefix once when supported naming tools and sufficient inventory are otherwise available. Save the answer and its source in project state. Never infer a prefix from a directory, repository, example, or product name.

Each project owns one counter across platforms. Preserve a valid existing title and its assigned number.

Use `<PREFIX>-<PLATFORM>-<NN> | <Task or Subsystem>`.

| Actual environment | Marker |
| --- | --- |
| Codex | X |
| ChatGPT Chat | C |
| ChatGPT Work | W |

Other tools require an owner-confirmed marker before assignment. Never choose the marker from the subject of the task. If identity, mode, title access, or safe numbering cannot be verified, silently skip naming and continue substantive work. Explain a limitation only if asked.

Projectless chats use a concise descriptive title with no prefix or sequence.

## Assignment procedure

1. Verify the actual project, environment, current title, and stored naming instructions.
2. Preserve existing valid assignments, including legacy titles unless an individual correction is authorized.
3. Inspect available project chats, archives, recorded assignments, linked platform histories, and other accessible hosts. Record inventory coverage and limitations; a capped listing is partial evidence.
4. Resolve identity conflicts, duplicate assignments, or ambiguous numbering before allocating. Never reuse a recorded number, fill a historical gap, merge project counters, or claim a partial inventory is complete.
5. Use one more than the highest recorded or reserved number across inspected assignments as a candidate. If checked evidence shows no linked platform/host assignments, the checked local maximum plus one is a candidate; UNKNOWN linked coverage is not evidence of absence.
6. Recheck concurrent assignments and reserve the candidate in the shared record under exclusive writer ownership before setting the title. If a shared record or exclusive ownership cannot be established, skip allocation rather than claim a collision-free number.
7. Use a supported native title setter, then verify the saved title. Only then mark the reserved record verified and record the saved title/reference. A response heading is not a sidebar rename. An unverified or failed attempt keeps its reservation pending until explicitly resolved; do not silently free or reuse it.

Use at least two digits; after 99 continue to 100 without wrapping. Retain existing larger numbers and reserved assignments. If safe allocation remains uncertain, skip naming and continue work.

Do not read credentials, use private web APIs, or write app databases to obtain a title or inventory. Use a read-only local inventory helper only when explicitly configured and authorized for that environment; record its host/platform limits.

## Fictional example

The example owner has confirmed TL for the fictional Trail Log project. This is not a prefix assignment for a project created from this template.

| Assignment | Environment | Meaning |
| --- | --- | --- |
| TL-X-01 \| Offline Checklist | Codex | First assigned task |
| TL-C-02 \| Activation Experiment | ChatGPT Chat | Shared project counter |
| TL-W-03 \| Export Acceptance | ChatGPT Work | Shared project counter |
| TL-X-04 \| Restart Persistence | Codex | Next candidate after checking all recorded assignments |

Renaming the first task after an authorized scope correction keeps 01. Discovering an archived TL-C-07 assignment makes 08 the next candidate even if 05 and 06 are absent from the available listing. The examples are not an inventory.

See the [worked example](examples/trail-log.md#chat-naming-example) for confirmation and conflict cases.
