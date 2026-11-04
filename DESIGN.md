---
version: alpha
name: <Project Name>-design-system
description: "Design system and product experience contract for <Project Name>. This file tells AI agents how the product should look, feel, behave, and protect trust while generating UI."
colors:
  primary: "#<hex>"
  on-primary: "#<hex>"
  primary-hover: "#<hex>"
  primary-focus: "#<hex>"
  canvas: "#<hex>"
  surface-1: "#<hex>"
  surface-2: "#<hex>"
  surface-3: "#<hex>"
  hairline: "#<hex>"
  hairline-strong: "#<hex>"
  ink: "#<hex>"
  ink-muted: "#<hex>"
  ink-subtle: "#<hex>"
  success: "#<hex>"
  warning: "#<hex>"
  danger: "#<hex>"
  info: "#<hex>"
typography:
  display-xl:
    fontFamily: "<Display Font>, <fallback>"
    fontSize: 48px
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: 0
  display-lg:
    fontFamily: "<Display Font>, <fallback>"
    fontSize: 36px
    fontWeight: 700
    lineHeight: 1.12
    letterSpacing: 0
  headline:
    fontFamily: "<Text Font>, <fallback>"
    fontSize: 24px
    fontWeight: 650
    lineHeight: 1.2
    letterSpacing: 0
  title:
    fontFamily: "<Text Font>, <fallback>"
    fontSize: 20px
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: 0
  body:
    fontFamily: "<Text Font>, <fallback>"
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0
  body-sm:
    fontFamily: "<Text Font>, <fallback>"
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: 0
  caption:
    fontFamily: "<Text Font>, <fallback>"
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.35
    letterSpacing: 0
  button:
    fontFamily: "<Text Font>, <fallback>"
    fontSize: 14px
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: 0
rounded:
  xs: 4px
  sm: 6px
  md: 8px
  lg: 12px
  xl: 16px
  pill: 9999px
spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  section: 80px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: 10px 16px
  card:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 16px
  input:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: 10px 12px
---

# `<Project Name>` Design System

See [Trail Log's design example](examples/trail-log.md#designmd-example) for concrete fictional tokens, checklist states, and failure copy. Adapt them to the actual product and verify contrast/accessibility; sample values are not validated design decisions.

## Purpose

This file is the visual and interaction contract for `<Project Name>`. AI agents should read it before generating screens, components, marketing surfaces, onboarding flows, paywalls, reports, dashboards, or share/export artifacts.

`AGENTS.md` explains how to build the project. `DESIGN.md` explains how the product should look, feel, and communicate.

## Product Experience North Star

`<Project Name>` helps `<target user>` achieve `<primary outcome>` through `<core mechanism>`.

The product should make value obvious through this ladder:

```text
Day 0: <instant value>
Day 7: <first repeat proof>
Day 30: <compounding or premium value>
```

Design every major surface to improve one of:

- Activation: user reaches the first value moment faster.
- Retention: user understands why to return.
- Revenue: paid value appears after utility is demonstrated.
- Trust: claims, data, and UI states feel accurate.
- Distribution: the product creates a shareable/exportable artifact.

## Visual Theme And Atmosphere

### Design Personality

`<Project Name>` should feel:

- `<tone 1>`: `<what this means visually>`
- `<tone 2>`: `<what this means visually>`
- `<tone 3>`: `<what this means visually>`

Examples:

- Health or behavior apps: calm, credible, warm, evidence-oriented.
- AI workflow tools: precise, fast, technical, low-friction.
- Hardware control apps: reliable, tactile, status-clear, safety-aware.
- Founder/operator tools: dense, utilitarian, comparison-friendly.

### Density

Use `<low | medium | high>` information density.

Rules:

- Primary workflow screens should show the next action without hunting.
- Dashboards should be dense only when repeated scanning is the job.
- Empty states should create action, not explain the whole product.
- Avoid decorative panels that do not help decision-making.

### Visual Metaphor

The visual system should center on `<main artifact or metaphor>`.

Examples:

- Proof card.
- Measurement tape.
- Timeline.
- Device signal.
- Prompt flow graph.
- Weekly report.

The artifact should appear in the first meaningful screen, not only in settings or marketing copy.

## Color Palette And Roles

Use semantic tokens, not one-off colors.

### Brand And Accent

| Token | Hex | Role |
| --- | --- | --- |
| `{colors.primary}` | `#<hex>` | Primary CTA, selected state, key progress signal |
| `{colors.primary-hover}` | `#<hex>` | Hover or pressed state |
| `{colors.primary-focus}` | `#<hex>` | Focus rings and active outlines |
| `{colors.on-primary}` | `#<hex>` | Text/icons on primary |

### Surfaces

| Token | Hex | Role |
| --- | --- | --- |
| `{colors.canvas}` | `#<hex>` | Page/app background |
| `{colors.surface-1}` | `#<hex>` | Cards, panels, sheets |
| `{colors.surface-2}` | `#<hex>` | Elevated or selected panels |
| `{colors.surface-3}` | `#<hex>` | Menus, overlays, secondary chrome |
| `{colors.hairline}` | `#<hex>` | Default borders and dividers |
| `{colors.hairline-strong}` | `#<hex>` | Focus, selected, or high-emphasis borders |

### Text

| Token | Hex | Role |
| --- | --- | --- |
| `{colors.ink}` | `#<hex>` | Primary text |
| `{colors.ink-muted}` | `#<hex>` | Secondary text |
| `{colors.ink-subtle}` | `#<hex>` | Captions, helper text, disabled text |

### Semantic

| Token | Hex | Role |
| --- | --- | --- |
| `{colors.success}` | `#<hex>` | Completed, improved, synced, connected |
| `{colors.warning}` | `#<hex>` | Needs attention, incomplete, caution |
| `{colors.danger}` | `#<hex>` | Error, destructive action, invalid state |
| `{colors.info}` | `#<hex>` | Neutral insight, help, contextual note |

### Color Rules

Do:

- Use the primary color for the main action and selected state.
- Keep semantic colors reserved for semantic meaning.
- Ensure contrast passes accessibility expectations.
- Use surface changes before adding extra accent colors.

Do not:

- Create a one-note palette dominated by a single hue family.
- Use gradients as a substitute for layout, hierarchy, or content.
- Use warning/danger colors for normal progress.
- Add new colors without assigning a semantic role.

## Typography Rules

### Font Families

- Display: `<Display Font>` with fallback `<fallback stack>`.
- Text: `<Text Font>` with fallback `<fallback stack>`.
- Mono: `<Mono Font>` with fallback `<fallback stack>`.

Use system fonts if speed matters more than brand distinctiveness.

### Type Scale

| Token | Size | Weight | Line Height | Letter Spacing | Use |
| --- | --- | --- | --- | --- | --- |
| `{typography.display-xl}` | 48px | 700 | 1.05 | 0 | App hero, major report headline |
| `{typography.display-lg}` | 36px | 700 | 1.12 | 0 | Screen title, paywall headline |
| `{typography.headline}` | 24px | 650 | 1.2 | 0 | Section heading, card group title |
| `{typography.title}` | 20px | 600 | 1.25 | 0 | Card title, sheet title |
| `{typography.body}` | 16px | 400 | 1.5 | 0 | Default body and form text |
| `{typography.body-sm}` | 14px | 400 | 1.45 | 0 | Secondary body, compact rows |
| `{typography.caption}` | 12px | 500 | 1.35 | 0 | Labels, metadata, helper text |
| `{typography.button}` | 14px | 600 | 1.2 | 0 | Button and control labels |

### Typography Rules

- Do not scale font size with viewport width.
- Keep letter spacing at `0` unless the brand explicitly requires otherwise.
- Use display type only for true hero moments or major proof/report artifacts.
- Use compact titles inside cards, sidebars, dashboards, and tools.
- Body copy should be direct, specific, and easy to translate.

## Layout Principles

### Spacing System

Base unit: 4px.

| Token | Value | Use |
| --- | --- | --- |
| `{spacing.xxs}` | 4px | Tight icon/text gaps |
| `{spacing.xs}` | 8px | Compact element gaps |
| `{spacing.sm}` | 12px | Form/control groups |
| `{spacing.md}` | 16px | Default screen padding |
| `{spacing.lg}` | 24px | Card padding, section groups |
| `{spacing.xl}` | 32px | Major groups |
| `{spacing.xxl}` | 48px | Screen sections |
| `{spacing.section}` | 80px | Marketing or report sections |

### Grid And Containers

- Mobile content width: full width with `{spacing.md}` side padding.
- Tablet content width: constrained to readable columns or 2-column grids.
- Desktop content width: max `<container width, e.g. 1120px or 1280px>`.
- Use stable dimensions for cards, tiles, boards, counters, and toolbars.
- Avoid layout shifts when labels, icons, loading states, or values change.

### Page Rhythm

Primary app surfaces:

- first screen should be the product experience, not a marketing page
- one dominant action per screen state
- navigation should make repeated use fast

Marketing or store surfaces:

- product or offer must be visible in the first viewport
- hero should hint at the next section
- use real product visuals, screenshots, device mockups, or generated bitmap assets

## Depth And Elevation

Use surface hierarchy before heavy shadows.

| Level | Treatment | Use |
| --- | --- | --- |
| 0 | `{colors.canvas}` no border | Default background |
| 1 | `{colors.surface-1}` + `{colors.hairline}` | Cards, panels, list containers |
| 2 | `{colors.surface-2}` + `{colors.hairline-strong}` | Selected cards, focused panels |
| 3 | `{colors.surface-3}` + shadow/scrim if needed | Menus, sheets, overlays |
| 4 | Focus ring using `{colors.primary-focus}` | Keyboard focus, active input |

Rules:

- Avoid cards inside cards.
- Do not style entire page sections as floating cards.
- Use shadows sparingly and consistently.
- Modals and sheets must have clear dismissal and focus behavior.

## Shapes And Radius

| Token | Value | Use |
| --- | --- | --- |
| `{rounded.xs}` | 4px | Tags, small chips |
| `{rounded.sm}` | 6px | Compact controls |
| `{rounded.md}` | 8px | Buttons, inputs |
| `{rounded.lg}` | 12px | Cards, sheets |
| `{rounded.xl}` | 16px | Large artifacts, report previews |
| `{rounded.pill}` | 9999px | Pills, segmented controls, avatars |

Rules:

- Default cards should be 8-12px radius unless the brand calls for sharper geometry.
- Buttons should use icons where familiar symbols exist.
- Do not use large pill buttons everywhere; reserve pills for segmented controls, badges, and compact filters.

## Component Stylings

### Buttons

`button-primary`

- Background `{colors.primary}`, text `{colors.on-primary}`.
- Use for one dominant action per screen.
- Minimum tap height: 44px on mobile.
- Include icon when it clarifies action.

`button-secondary`

- Background `{colors.surface-1}`, text `{colors.ink}`.
- Border `{colors.hairline}`.
- Use for alternate actions that do not compete with the primary CTA.

`button-tertiary`

- Transparent or canvas background.
- Use for low-risk navigation, edit, cancel, or learn-more actions.

`button-danger`

- Use only for destructive actions.
- Require confirmation for irreversible changes.

### Inputs

- Background `{colors.surface-1}`.
- Border `{colors.hairline}`.
- Focus ring `{colors.primary-focus}`.
- Validation copy should be specific and placed near the field.
- Numeric inputs should use units, constraints, and clear invalid states.

### Cards

Use cards for repeated items, proof/report artifacts, dashboards, and modal content.

Card anatomy:

```text
title or label
primary value / content
supporting metadata
optional action
```

Rules:

- Do not put cards inside cards.
- Avoid decorative cards that do not hold a decision, state, or artifact.
- Keep text within the card; handle long values gracefully.

### Navigation

- Prefer tab bars for 3-5 persistent app destinations.
- Prefer side navigation only for desktop/tablet productivity tools.
- Keep labels product-specific, not generic.
- Current destination must be visually obvious.

### Segmented Controls, Toggles, Sliders

- Use segmented controls for modes.
- Use toggles/checkboxes for binary settings.
- Use sliders/steppers/inputs for numeric values.
- Use menus for option sets.
- Show selected, hover, pressed, disabled, and focus states.

### Empty, Loading, Error, Offline, Success

Every major workflow needs these states when relevant:

- Empty: explain the next action, not the whole product.
- Loading: preserve layout dimensions where possible.
- Error: say what failed and what the user can do.
- Offline: show what remains available locally.
- Success: confirm the action and show the next useful step.

## Core Product Surfaces

### First Session

Target flow:

```text
Welcome
  -> <minimum input>
  -> <instant result>
  -> <first target or next action>
  -> <retention setup>
  -> Home with <visible value> ready
```

First-session output:

```text
<Concrete output the user sees>
```

### Recurring Loop

```text
Open product
  -> see <current state>
  -> take <one dominant action>
  -> receive <confirmation/proof>
  -> return because <next reason>
```

### Monetization Moment

Free value:

- `<free activation value>`
- `<free core logging/action>`
- `<free first proof/result>`

Premium value:

- `<premium history/report/automation>`
- `<premium advanced insight>`
- `<premium export/share/integration>`
- `<premium convenience or saved effort>`

Recommended paid trigger:

```text
<Natural moment when user has enough value to understand paid utility>
```

Avoid paywalling basic activation.

## Data Visualization And Artifacts

Use charts, proof cards, reports, and exports only when they answer one clear question.

Rules:

- Label axes, units, and time ranges.
- Show insufficient-data states honestly.
- Do not imply causality from correlation.
- Use semantic color carefully in charts.
- Share/export artifacts should include product branding and the core proof/result.

## Motion And Interaction

Motion should clarify state changes, not entertain by default.

Use motion for:

- route transitions
- sheet/modal entry and dismissal
- progress completion
- state changes after user action
- hardware/device connection changes

Avoid:

- looping decorative motion on workflow screens
- slow transitions that block repeated use
- animation that hides loading or errors

## Responsive Behavior

### Breakpoints

| Name | Width | Key Changes |
| --- | --- | --- |
| Mobile | 0-479px | Single column, bottom nav, 44px touch targets |
| Mobile-Lg | 480-767px | Larger cards, still single column |
| Tablet | 768-1023px | Two-column opportunities, wider sheets |
| Desktop | 1024-1279px | Sidebar or split views if useful |
| Desktop-XL | 1280px+ | Max-width content, avoid stretched text |

### Touch And Accessibility

- Minimum touch target: 44px on mobile.
- Interactive icons need labels, tooltips, or accessible names.
- Keyboard focus must be visible.
- Text and controls must not overlap on narrow screens.
- Long words, translations, and numeric values must wrap or fit cleanly.

## Copy And Tone

Voice:

- specific, not generic
- direct, not abstract
- encouraging, not hype-driven
- evidence-oriented, not overconfident

Rules:

- Name the concrete utility, not vague "AI-powered" magic.
- Use conservative language for health, finance, legal, or behavior claims.
- Avoid shame, fear, or diagnostic certainty.
- Write copy that can translate cleanly.

## Trust Boundaries

`<Project Name>` can say:

- `<safe claim 1>`
- `<safe claim 2>`
- `<safe claim 3>`

`<Project Name>` should not say:

- `<unsupported claim 1>`
- `<unsupported claim 2>`
- `<unsupported claim 3>`

When data is incomplete:

- show what is missing
- explain the next action
- avoid fake progress, fake certainty, or hidden assumptions

## Do's And Don'ts

### Do

- Use the token system before inventing styles.
- Build the primary workflow as the first screen.
- Keep one dominant action per state.
- Show real product data, product screenshots, device state, or artifact previews.
- Make empty and insufficient-data states useful.
- Use product-specific labels.
- Keep monetization tied to concrete unlocked utility.

### Don't

- Do not create landing pages when the user asked for an app/tool.
- Do not build decorative dashboards before the core loop works.
- Do not use cards inside cards.
- Do not add gradient blobs, decorative orbs, or bokeh backgrounds.
- Do not hide invalid, missing, or low-confidence data.
- Do not introduce a new visual style for one feature.
- Do not let generated UI invent unsupported claims.

## Agent Prompt Guide

When asking an AI agent to build UI, include:

```text
Use DESIGN.md as the design system.
Build the <screen/flow/component> for <user outcome>.
Primary action: <action>.
Data states to handle: empty, loading, success, error, offline if relevant.
Do not add unsupported claims or decorative sections.
Use existing app patterns and tokens.
```

Fast screen prompt:

```text
Build <screen name> for <Project Name>.
It should help <target user> do <job>.
Use {colors.canvas}, {colors.surface-1}, {colors.primary}, and the typography tokens from DESIGN.md.
Include primary, empty, loading, and error states.
```

Component prompt:

```text
Create a reusable <component> using DESIGN.md tokens.
It must support default, hover/pressed, focused, disabled, loading, and error states where relevant.
Keep dimensions stable across content changes.
```

## Implementation Notes For Flutter

Map this design system into code:

- `ThemeData.colorScheme`: brand, surfaces, text, semantic colors.
- `TextTheme`: typography tokens.
- constants or theme extension: spacing, radius, shadows, component metrics.
- widgets: primary buttons, cards, inputs, badges, proof/report artifacts.

Do not hardcode colors, spacing, or type values repeatedly in feature widgets. Add or reuse theme tokens instead.
