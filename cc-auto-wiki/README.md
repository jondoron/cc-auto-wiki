# cc-auto-wiki

A Claude Code plugin that auto-captures Claude Code conversations as Karpathy-style raw sources, then compiles them into a persistent project wiki on demand.

Inspired by [Karpathy's LLM wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — a structured, interlinked markdown knowledge base that the LLM incrementally builds and maintains as new sources arrive.

## What it does

Knowledge produced during Claude Code conversations — design decisions, trade-offs, alternatives considered, architectural rationale — disappears when the session ends. This plugin keeps it.

Two stages:

1. **Capture** runs automatically on `SessionEnd` and `PreCompact`, and on demand via `/cc-auto-wiki:auto-wiki-ingest`. Each run produces one markdown file under `<wiki-root>/raw/sessions/`. Capture is fast, asynchronous, and never blocks the user.
2. **Compile** runs only when you invoke `/cc-auto-wiki:auto-wiki-compile`. It integrates pending raw sources into a synthesized wiki — creating and updating pages, maintaining cross-references, flagging contradictions.

What gets captured is governed by a free-form **Capture guidance** section in `<wiki-root>/CLAUDE.md` that you write and edit freely. Edits take effect on the next session — no plugin reload.

## Install

```bash
claude --plugin-dir /path/to/cc-auto-wiki
```

(Or wire it into a marketplace once one's available.)

## Use

```
/cc-auto-wiki:auto-wiki-init       # interactive first-run setup
/cc-auto-wiki:auto-wiki-ingest     # manual capture mid-session
/cc-auto-wiki:auto-wiki-compile    # integrate pending raw sources into the wiki
```

After `/cc-auto-wiki:auto-wiki-init` the plugin will:

- Auto-capture on every `SessionEnd` and `PreCompact` for this project
- Stage captures under `<wiki-root>/raw/sessions/`
- Append a one-line entry per capture to `<wiki-root>/log.md`

You compile when you're ready.

## Configuration

Mechanical settings live in `.claude/settings.json` under an `cc-auto-wiki` key:

```json
{
  "cc-auto-wiki": {
    "root": "wiki",
    "model": "claude-haiku-4-5-20251001"
  }
}
```

Editorial direction — *what* to capture — lives in `<wiki-root>/CLAUDE.md` under a `## Capture guidance` heading. Edit it freely; the capture sub-agent reads it on every run.

## Layout

```
<wiki-root>/
├── CLAUDE.md           ← schema & capture guidance (you edit this)
├── index.md            ← content catalog (compile maintains this)
├── log.md              ← chronological event log
├── raw/sessions/       ← staged raw sources (immutable)
└── wiki/               ← category subdirectories chosen at init
    └── …                ← named to fit your project
```

There are no fixed default categories. During `/cc-auto-wiki:auto-wiki-init` the agent reads your capture guidance and proposes a layout tailored to it (e.g., `compliance-decisions/`, `phi-handling/`, `audit-runbooks/` for a healthcare repo; `experiments/`, `datasets/`, `findings/` for a research repo); you refine that proposal until it fits. The compile sub-agent reads the `## Wiki structure` section of `<wiki-root>/CLAUDE.md` to decide where new pages go, so each category should have a one-line description.

## Troubleshooting

Capture is best-effort and silent. Errors land in `$HOME/.claude/cc-auto-wiki.log`:

```bash
tail -50 ~/.claude/cc-auto-wiki.log
```

Common issues:
- **No raw source produced after SessionEnd** — check that `/cc-auto-wiki:auto-wiki-init` has been run for this project (`.claude/settings.json` must have an `cc-auto-wiki` key) and that `<wiki-root>/CLAUDE.md` exists.
- **`claude` not on PATH inside the hook** — async hooks inherit the shell's PATH; if your shell rc files don't add it, set it in the plugin's `settings.json` or in your user `settings.json` `env` block.
- **`jq` missing** — install it; the hook scripts depend on it.

## Status

v0.1 — ingest only. Query (`/cc-auto-wiki:ask`) and lint (`/cc-auto-wiki:lint`) are planned for later.
