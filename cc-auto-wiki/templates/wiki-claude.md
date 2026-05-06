# Wiki Schema

This file is the schema for the project wiki. The capture sub-agent reads it on every run; the compile sub-agent reads it whenever it integrates new sources. Edit it freely — changes take effect on the next session.

## Capture guidance

<!-- {{capture_guidance}} -->

The following describes what to extract from Claude Code conversations and what to ignore. The capture sub-agent will apply this guidance literally, so be specific.

**What to preserve:**
- Decisions about architecture, libraries, data models, and APIs — including the reasoning and what alternatives were rejected.
- Trade-offs surfaced during discussion, with the costs accepted (not just the wins).
- Project-specific conventions discovered or agreed during the conversation.
- Things you'd need to re-derive from scratch if you came back to this code in three months.

**What to ignore:**
- Generic explanations of how standard libraries, languages, or tools work — those belong in the docs.
- The play-by-play of a debugging session unless it surfaced a non-obvious gotcha worth remembering.
- Routine file edits and tool calls that don't represent a decision.

**Project-specific framing:**
- (Add project-specific direction here over time — e.g., "this codebase is in a regulated domain; flag anything touching auth or PII," or "we care a lot about cold-start latency, capture every perf-related observation.")

## Wiki structure

The wiki has three layers:

1. `raw/sessions/` — immutable raw sources produced by capture. Never edit by hand. Filenames follow `YYYY-MM-DD-HHMM-<session-short>.md`.
2. `wiki/` — the synthesized knowledge base, owned and maintained by the compile step. Subdirectories: `decisions/`, `concepts/`, `entities/`. Add more as the wiki grows.
3. `index.md` and `log.md` at the wiki root.

## Page conventions

- **Frontmatter** on every wiki page:
  ```yaml
  ---
  title: <page title>
  type: decision | concept | entity
  created: YYYY-MM-DD
  updated: YYYY-MM-DD
  sources: [<raw-source-filename>, ...]
  ---
  ```
- **Links** are wiki-style: `[[Page Name]]`. Backlinks are maintained: if page A links to page B, page B's "Related" section should list A.
- **Dated claims**: when a claim might evolve, prefix it with the date — `As of 2026-05-05, the team uses SQLite…`. This makes contradictions easy to spot when sources from different dates disagree.
- **Contradictions** get a `> [!conflict]` callout inline rather than a silent overwrite. The user resolves them during the next compile pass.

## index.md conventions

`index.md` is a content catalog. Every wiki page is listed with:

```markdown
- [[Page Title]] — one-line summary (created YYYY-MM-DD, N sources)
```

Organized by category (Decisions, Concepts, Entities, etc.). The compile step updates this on every run.

## log.md conventions

Append-only chronological log. Every entry starts with a consistent prefix so it's grep-able:

```markdown
## [YYYY-MM-DD] capture | <topic>
## [YYYY-MM-DD] compile | <N sources, M pages touched>
```

`grep "^## \[" log.md | tail -10` gives you the last 10 events.
