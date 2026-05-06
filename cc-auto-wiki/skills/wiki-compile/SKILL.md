---
name: compile
description: Integrate pending raw sources into the project wiki. Reads each uncompiled source under raw/sessions/, updates or creates wiki pages, maintains cross-references, updates index.md and log.md, and surfaces contradictions and redundancies to the user.
disable-model-invocation: true
---

You are running the compile step for the cc-auto-wiki. The capture step has already produced raw sources from past conversations; your job is to weave them into the wiki proper.

## Setup

First, read the procedure document at `${CLAUDE_PLUGIN_ROOT}/prompts/compile-system.md`. That file is the authoritative procedure — follow it exactly.

Then, resolve the wiki root:
```bash
WIKI_ROOT_REL="$(jq -r '."cc-auto-wiki".root // empty' .claude/settings.json)"
if [[ -z "$WIKI_ROOT_REL" ]]; then echo "wiki not configured"; exit 1; fi
WIKI_ROOT="$(cd "$WIKI_ROOT_REL" && pwd)"
echo "WIKI_ROOT=$WIKI_ROOT"
```

If unconfigured, tell the user to run `/cc-auto-wiki:init` and stop.

## Execution

Apply the procedure from `compile-system.md` against this `WIKI_ROOT`:

1. List pending sources: files under `$WIKI_ROOT/raw/sessions/` whose frontmatter has `compiled: false`.
2. Read `$WIKI_ROOT/CLAUDE.md` (the schema) and `$WIKI_ROOT/index.md` (the catalog).
3. Process sources in chronological order (filename starts with `YYYY-MM-DD-HHMM-`).
4. For each source: identify pages to update or create, integrate the material respecting the schema's conventions, maintain cross-references, surface contradictions inline with `> [!conflict]` callouts.
5. Update `$WIKI_ROOT/index.md` with new pages and one-line summaries.
6. Append a single `## [YYYY-MM-DD] compile | <N sources, M pages touched>` line to `$WIKI_ROOT/log.md`.
7. Flip `compiled: true` and add `compiled_at: <ISO>` to each processed source's frontmatter. Do not modify the source body.

## Reporting

After the run, give the user a structured summary:

- **Compiled:** list of source filenames processed
- **Pages created:** new wiki pages with one-line descriptions
- **Pages updated:** existing wiki pages and what changed in each
- **Contradictions flagged:** any `> [!conflict]` callouts you added — the user should resolve these
- **Redundancies noticed:** sources or pages that seem to duplicate each other
- **Things you weren't sure about:** material you couldn't comfortably place in the wiki

Be specific in the report — file paths, page titles, one sentence of substance per item. The user reads this to decide what to follow up on.

## Rules

- **The user is in the loop.** If the compile pass touches more than ~5 pages or you're unsure how to integrate something, pause and ask before continuing.
- **Never modify raw sources beyond their frontmatter.** They're the audit trail.
- **Never delete the `## Capture guidance` section of the schema.** That belongs to the user.
- **Don't try to be clever about restructuring.** Integrate new material around existing structure rather than rewriting whole pages.
- **Date evolving claims.** Per the schema, prefix claims that may go stale with the date.
