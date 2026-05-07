---
name: auto-wiki-ingest
description: Manually capture the current conversation as a wiki raw source. Useful mid-session when a decision lands and the user wants it staged immediately rather than waiting for SessionEnd.
disable-model-invocation: true
---

You are running a manual capture for the cc-auto-wiki. This is the same flow that fires automatically on `SessionEnd` and `PreCompact`, but invoked on demand.

## Procedure

### 1. Verify the wiki is configured

Run via Bash:
```bash
jq -r '."cc-auto-wiki".root // empty' .claude/settings.json 2>/dev/null
```

If the result is empty, tell the user: "The wiki isn't configured for this project yet. Run `/cc-auto-wiki:auto-wiki-init` first." and stop.

### 2. Locate the current session's transcript

The current Claude Code transcript lives in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<encoded-cwd>/<session-id>.jsonl`, where `<encoded-cwd>` is the cwd with `/` replaced by `-`.

Run:
```bash
CWD="$(pwd)"
ENCODED="${CWD//\//-}"
PROJ_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/${ENCODED}"
TRANSCRIPT="$(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null | head -n 1)"
SESSION_ID="$(basename "$TRANSCRIPT" .jsonl)"
echo "TRANSCRIPT=$TRANSCRIPT"
echo "SESSION_ID=$SESSION_ID"
```

If `$TRANSCRIPT` is empty, tell the user: "No transcript found for this project. Has Claude Code been writing to disk this session?" and stop.

The most-recently-modified `.jsonl` is the current session.

### 3. Invoke capture.sh

Pipe a JSON payload to the capture script:
```bash
jq -n \
  --arg t "$TRANSCRIPT" \
  --arg s "$SESSION_ID" \
  --arg c "$CWD" \
  '{transcript_path: $t, session_id: $s, cwd: $c}' \
  | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/capture.sh" manual
```

The script always exits 0; check `$HOME/.claude/cc-auto-wiki.log` if you want to see what happened.

### 4. Confirm to the user

After running, list any new file in `<wiki-root>/raw/sessions/`:
```bash
WIKI_ROOT="$(jq -r '."cc-auto-wiki".root' .claude/settings.json)"
ls -t "$WIKI_ROOT/raw/sessions" | head -3
```

Tell the user the new filename and offer to read it back if they want to review what was captured.

## Rules

- **Don't second-guess the capture sub-agent.** Your job is plumbing — find the transcript, hand it off. Editorial choices are governed by `<wiki-root>/CLAUDE.md` Capture guidance.
- **Don't run `/cc-auto-wiki:auto-wiki-compile` automatically afterwards.** Compile is a separate, deliberate step the user invokes when they want to integrate sources into the wiki.
- **If capture fails silently** (no new file appears), point the user at `$HOME/.claude/cc-auto-wiki.log` and let them debug.
