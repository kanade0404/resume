---
name: grill-with-docs
description: >-
  Grilling session that challenges your plan against the existing domain model,
  sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as
  decisions crystallise. Use when user wants to stress-test a plan against their
  project's language and documented decisions.
---
<!-- Source: https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md -->

<what-to-do>

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing.

For each question, first inspect the codebase and existing docs; ask only what remains unresolved.

</what-to-do>

<supporting-info>

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

Presence of `CONTEXT-MAP.md` at the root indicates a multi-context repository. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. Create `CONTEXT.md` when the first term is resolved. Create `docs/adr/` when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. Surface contradictions immediately: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

`CONTEXT.md` reflects resolved terms immediately at the point of resolution. Use the format in [CONTEXT-FORMAT.md](./references/CONTEXT-FORMAT.md).

`CONTEXT.md` artifact scope: glossary-only content, with no implementation detail, specification prose, scratch-pad notes, or decision-log material.

### Offer ADRs sparingly

Offer ADR creation only after confirming all three required criteria:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

Skip ADR creation whenever any criterion remains unconfirmed. Use the format in [ADR-FORMAT.md](./references/ADR-FORMAT.md).

</supporting-info>
