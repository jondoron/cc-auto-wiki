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
- Reconfigure (continue with steps 2+, and warn that this will overwrite the schema's Capture guidance section if they edit it)

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

### 4. Confirm gitignore behavior

Ask: "Should `<wiki-root>/raw/` be gitignored? Raw sources contain verbatim conversation excerpts that may include credentials or transient state — most users want them local-only, with only the compiled `wiki/` committed."

Default recommendation: yes, gitignore raw. Capture their choice as `raw_gitignored: true|false`.

### 5. Confirm and write

Summarize the four choices:
- Wiki root path
- Capture guidance (the paragraph)
- Model for capture (default: `claude-haiku-4-5-20251001` — keep it cheap; capture runs on every session end)
- Gitignore raw or not

Once confirmed, perform the writes:

**a. Create the directory tree.**
```
mkdir -p <wiki-root>/{raw/sessions,wiki/{decisions,concepts,entities}}
```

**b. Drop the templates.** Read `${CLAUDE_PLUGIN_ROOT}/templates/wiki-claude.md`, replace the `<!-- {{capture_guidance}} -->` marker AND the surrounding "The following describes…" placeholder text with the user's actual guidance paragraph, and write to `<wiki-root>/CLAUDE.md`. Then copy `${CLAUDE_PLUGIN_ROOT}/templates/index.md` and `templates/log.md` to `<wiki-root>/index.md` and `<wiki-root>/log.md`.

**c. Update `.claude/settings.json`.** Add or merge the `cc-auto-wiki` key:
```json
{
  "cc-auto-wiki": {
    "root": "<relative-wiki-root>",
    "model": "<model>",
    "raw_gitignored": <true|false>
  }
}
```
Use `jq` via Bash to merge cleanly so any existing settings are preserved. Create the file with `{}` first if it doesn't exist.

**d. Update `.gitignore` if requested.** Append `<wiki-root>/raw/` (or the absolute equivalent for the project) if `raw_gitignored` is true and the line isn't already present.

### 6. Tell the user what's next

Print a concise summary:
- "Created wiki at `<path>`. Capture guidance is editable at `<path>/CLAUDE.md`."
- "Auto-capture will fire on `SessionEnd` and `PreCompact` going forward. The first capture will produce a file in `<path>/raw/sessions/`."
- "Run `/cc-auto-wiki:compile` when you have a few captures and want to integrate them into the wiki proper."
- "Run `/cc-auto-wiki:ingest` mid-session if you want to capture immediately."

## Rules

- **Do not write any files until the user has confirmed in step 5.** This skill is conversational; jumping ahead surprises the user.
- **Treat the Capture guidance as the user's voice, not yours.** Don't paraphrase it into something more "professional." Preserve their phrasing.
- **Never overwrite an existing `<wiki-root>/CLAUDE.md` without explicit confirmation** — it may contain edits the user made after init.
- **If anything ambiguous comes up** (the wiki root path conflicts with an existing directory of unrelated content, the user gives contradictory answers), stop and ask rather than guessing.
