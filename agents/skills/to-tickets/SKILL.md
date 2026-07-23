---
name: to-tickets
description: Break a plan, spec, or the current conversation into tracer-bullet tickets for the local Markdown issue tracker, with one file per ticket and explicit blocking edges.
disable-model-invocation: true
---

# To Tickets

Break a plan, spec, or conversation into a set of **tickets** — tracer-bullet vertical slices, each declaring the tickets that **block** it.

Assume the project uses a local Markdown issue tracker under `.scratch/`. Do not rely on or invoke `/setup-matt-pocock-skills`.

## Local project conventions

- One feature lives in `.scratch/<feature-slug>/`.
- Its spec is `.scratch/<feature-slug>/spec.md`.
- Implementation tickets are separate files at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order. Never create one combined tickets file.
- Record triage state with a `Status:` line near the top. New tickets use `ready-for-agent`.
- Append later comments or conversation history under a `## Comments` heading.
- Before exploring, read the root `CONTEXT-MAP.md` if present and each linked `CONTEXT.md` relevant to the work; otherwise read the root `CONTEXT.md` if present.
- Read relevant ADRs under `docs/adr/` and, in a multi-context repo, relevant context-scoped ADRs such as `src/<context>/docs/adr/`.
- Missing domain documents are not an error. Proceed silently.
- Use glossary terms from the relevant `CONTEXT.md` rather than inventing synonyms. Surface any conflict with an ADR explicitly.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a spec or ticket path, read the full file, including `## Comments`. If the user passes only an issue number, resolve it within the relevant `.scratch/<feature-slug>/issues/` directory. If the feature directory is not explicit, infer it from the referenced spec or current conversation; ask only when multiple existing directories are equally plausible.

### 2. Explore the codebase (optional)

Read the applicable domain documents. If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests) — vertical, NOT a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Any prefactoring should be done first

</vertical-slice-rules>

Give each ticket its **blocking edges** — the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket — green is promised only there.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct — does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.

### 5. Publish the tickets to the local tracker

Publish the approved tickets as separate files under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, creating the directories if needed. Reuse the feature directory containing the source spec when there is one; otherwise derive a concise kebab-case feature slug from the work.

Number tickets from `01` in dependency order, with blockers before the tickets they gate. Each file's `Blocked by` entry lists the numbers and titles it depends on. Use the per-ticket template below.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

Do not modify the source spec or any parent ticket.

<local-ticket-template>

# <NN> — <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective — not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None — can start immediately".

**Status:** ready-for-agent

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

</local-ticket-template>

Avoid specific file paths or code snippets in ticket bodies — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.
