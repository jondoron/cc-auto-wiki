---
name: init
description: First-run setup for the project wiki. Asks the user where the wiki should live, elicits free-form capture guidance, writes config to .claude/settings.json, creates the wiki directory tree, and drops the schema/index/log templates.
disable-model-invocation: true
---

You are running the cc-auto-wiki first-run setup. Your job is to interactively configure the wiki for this project.

## Procedure

### 1. Check for existing config

Read `.claude/settings.json` (it may not exist) and check whether an `cc-auto-wiki` key already exists. If it does, tell the user the current configured wiki root and ask whether they want to:
- Keep it (exit the skill silently)
- Reconfigure (continue with steps 2+). Warn that reconfiguring will overwrite the schema's Capture guidance and Wiki structure sections if they edit them. If the wiki already has content under existing category directories, do not delete those directories — note any categories that will become orphaned (i.e., no longer listed in the new schema) and tell the user so they can decide whether to remove them by hand.

### 2. Choose a wiki root

Ask the user where the wiki should live. Suggest `wiki/` at the repo root, but explain the trade-off:

> A wiki at `wiki/` is committed to git and team-shared (Karpathy's vision — the wiki is a first-class artifact). A wiki at `.claude/wiki/` is gitignored and personal. Pick whichever fits.

Accept any path the user chooses. Resolve it to an absolute path internally but store it relative to the repo root in config.

### 3. Elicit Capture guidance

This is the most important step — do not rush it. Ask the user, in their own words, what kinds of things they want preserved from their Claude Code conversations.

Ask follow-up questions and offer concrete examples to draw out specifics:

- "What decisions do you find yourself re-litigating? Library choices? Architectural splits? Naming conventions?"
- "Are there things that would have value if surfaced quickly — performance trade-offs, security caveats, regulatory constraints?"
- "What's the *least* useful thing to capture? Generic library explanations? Routine debugging steps? Style nits?"
- "Is there a domain framing that should color everything — e.g., 'this is an HFT trading system, latency observations matter,' or 'this is a regulated healthcare app, anything touching PHI gets a flag'?"

Aim for guidance that is **specific** — a single paragraph that another developer could read and understand exactly what to capture in this project. Vague answers like "important stuff" are a failure mode; push back gently and ask for examples.

When you have something solid, read it back to the user and confirm before writing it to disk.

### 3.5. Propose a category layout

The wiki organizes pages into top-level categories — each becomes a subdirectory under `<wiki-root>/wiki/`. The compile sub-agent uses these categories (and their descriptions in the schema) to decide where each new page goes.

**Do not start from a generic default like decisions/concepts/entities.** Use the Capture guidance the user just gave you to propose a layout that fits *their* project. Re-read the guidance, then ask yourself: "If I were filing the kinds of things this user wants captured, what 3–6 buckets would I actually reach for?" Stay specific to their domain — avoid catch-all buckets like "notes" or "miscellaneous."

A few shape examples to calibrate (do NOT copy these wholesale — they illustrate how to tailor to a domain):

- A regulated healthcare codebase might warrant: `compliance-decisions`, `phi-handling`, `auth-integrations`, `audit-runbooks`.
- An HFT trading system might warrant: `latency-decisions`, `market-protocols`, `failover-runbooks`, `instrument-models`.
- A research repo might warrant: `experiments`, `datasets`, `model-cards`, `findings`.

Present your proposal as:

```
- <name>  — <one-line purpose tied back to the user's capture guidance>
- <name>  — <...>
- <name>  — <...>
```

Then ask the user to react: keep as-is, rename, edit a description, remove a category, add new ones. Iterate until they're satisfied. If the user pushes back on the whole shape ("none of this fits"), throw away the proposal and start fresh from their feedback rather than nudging them back toward your first draft.

Rules for the final list:
- At least one category must remain.
- Each entry has a directory-safe name (lowercase, hyphens or underscores; no slashes or spaces). Reject names that would collide on case-insensitive filesystems.
- Descriptions are strongly encouraged — without them, the compile step has only the directory name to infer placement from. If the user explicitly chooses to omit a description, accept the entry as-is rather than inventing one.
- Preserve the user's wording when they edit a description (same rule as Capture guidance).

Read the final list back and confirm before moving on.

### 4. Confirm and write

Summarize the choices:
- Wiki root path
- Capture guidance (the paragraph)
- Category layout (the list of `name — description` entries)
- Model for capture (default: `claude-haiku-4-5-20251001` — keep it cheap; capture runs on every session end)

Once confirmed, perform the writes:

**a. Create the directory tree.** Always create `<wiki-root>/raw/sessions/`. Then create one subdirectory under `<wiki-root>/wiki/` per chosen category, using its directory-safe name. For example, if the agreed categories are `experiments`, `datasets`, `findings`:

```
mkdir -p <wiki-root>/raw/sessions
mkdir -p <wiki-root>/wiki/experiments <wiki-root>/wiki/datasets <wiki-root>/wiki/findings
```

If reconfiguring, do not delete pre-existing category directories that are no longer in the list — leave them and surface them to the user in step 5.

**b. Drop the templates.**

Read `${CLAUDE_PLUGIN_ROOT}/templates/wiki-claude.md` and produce `<wiki-root>/CLAUDE.md` by substituting two markers:

- `<!-- {{capture_guidance}} -->` — replace this marker AND the surrounding "The following describes…" placeholder text with the user's actual guidance paragraph.
- `<!-- {{categories_block}} -->` — replace with a bulleted list of the chosen categories. For each category, render one line of the form `   - \`<name>/\` — <description>` (three-space indent so it nests inside the numbered list). If a category has no description, render `   - \`<name>/\`` without the dash.

Read `${CLAUDE_PLUGIN_ROOT}/templates/index.md` and produce `<wiki-root>/index.md` by substituting:

- `<!-- {{category_sections}} -->` — replace with one second-level heading per category, in the user's chosen order. Use a sensible display title (capitalize the first letter of the directory name; turn hyphens/underscores into spaces — e.g., `post-mortems` → `Post mortems`). Under each heading, place `_(none yet)_`. Under the very first heading, instead place `_(none yet — run \`/cc-auto-wiki:compile\` after some captures have accumulated)_` so the hint shows up exactly once.

Copy `${CLAUDE_PLUGIN_ROOT}/templates/log.md` verbatim to `<wiki-root>/log.md`.

**c. Update `.claude/settings.json`.** Add or merge the `cc-auto-wiki` key:
```json
{
  "cc-auto-wiki": {
    "root": "<relative-wiki-root>",
    "model": "<model>"
  }
}
```
Use `jq` via Bash to merge cleanly so any existing settings are preserved. Create the file with `{}` first if it doesn't exist.

### 5. Tell the user what's next

Print a concise summary:
- "Created wiki at `<path>`. Capture guidance and the category layout are editable at `<path>/CLAUDE.md`."
- "Categories: <comma-separated list>. Add or rename categories later by editing the `## Wiki structure` section of the schema and creating the directories under `<path>/wiki/`."
- "Auto-capture will fire on `SessionEnd` and `PreCompact` going forward. The first capture will produce a file in `<path>/raw/sessions/`."
- "Run `/cc-auto-wiki:compile` when you have a few captures and want to integrate them into the wiki proper."
- "Run `/cc-auto-wiki:ingest` mid-session if you want to capture immediately."

If reconfiguring left behind any pre-existing category directories no longer in the chosen list, name them and tell the user they were preserved so they can decide whether to delete them by hand.

## Rules

- **Do not write any files until the user has confirmed in step 5.** This skill is conversational; jumping ahead surprises the user.
- **Treat the Capture guidance as the user's voice, not yours.** Don't paraphrase it into something more "professional." Preserve their phrasing.
- **Never overwrite an existing `<wiki-root>/CLAUDE.md` without explicit confirmation** — it may contain edits the user made after init.
- **If anything ambiguous comes up** (the wiki root path conflicts with an existing directory of unrelated content, the user gives contradictory answers), stop and ask rather than guessing.
