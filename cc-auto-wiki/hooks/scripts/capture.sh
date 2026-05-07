#!/usr/bin/env bash
# Capture entry point. Invoked by SessionEnd / PreCompact hooks and by the
# /cc-auto-wiki:auto-wiki-ingest skill. Reads stdin JSON ({transcript_path, session_id,
# cwd}), composes a prompt, runs `claude -p` headless, and writes a single
# raw source markdown file to <wiki-root>/raw/sessions/.
#
# Always exits 0 — capture is best-effort and must never disrupt the user's
# session. Errors are appended to $HOME/.claude/cc-auto-wiki.log.

set -uo pipefail

TRIGGER="${1:-manual}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

# Recursion guard. Capture invokes `claude -p`, which itself loads this plugin
# and would fire SessionEnd on completion — without this guard, every capture
# spawns a capture which spawns a capture. Set by this script when it invokes
# claude -p (see below).
if [[ "${WIKI_PLUGIN_INTERNAL:-0}" = "1" ]]; then
  exit 0
fi

wp_log "capture.sh fired trigger=$TRIGGER pid=$$"
wp_require_jq || exit 0

# --- Read stdin JSON ----------------------------------------------------------
INPUT="$(cat)"
if [[ -z "$INPUT" ]]; then
  wp_log "no stdin input; aborting"
  exit 0
fi

TRANSCRIPT_PATH="$(jq -r '.transcript_path // empty' <<<"$INPUT")"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT")"

if [[ -z "$TRANSCRIPT_PATH" || -z "$SESSION_ID" || -z "$CWD" ]]; then
  wp_log "missing fields: transcript=$TRANSCRIPT_PATH session=$SESSION_ID cwd=$CWD"
  exit 0
fi

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  wp_log "transcript file does not exist: $TRANSCRIPT_PATH"
  exit 0
fi

# --- Resolve config -----------------------------------------------------------
WIKI_ROOT="$(wp_wiki_root "$CWD" || true)"
if [[ -z "$WIKI_ROOT" ]]; then
  wp_log "wiki not configured for cwd=$CWD; silent no-op"
  exit 0
fi

SCHEMA="$WIKI_ROOT/CLAUDE.md"
if [[ ! -f "$SCHEMA" ]]; then
  wp_log "wiki schema missing at $SCHEMA; silent no-op"
  exit 0
fi

MODEL="$(wp_model "$CWD")"
GUIDANCE="$(wp_slice_guidance "$SCHEMA")"

if [[ -z "${GUIDANCE//[[:space:]]/}" ]]; then
  wp_log "no Capture guidance section in $SCHEMA; using fallback"
  GUIDANCE="(No Capture guidance section found. Capture decisions, trade-offs, alternatives, and architecture notes by default.)"
fi

# --- Idempotency: skip if already captured for this session+trigger ------------
SID_SHORT="$(wp_session_short "$SESSION_ID")"
SESSIONS_DIR="$WIKI_ROOT/raw/sessions"
mkdir -p "$SESSIONS_DIR"

shopt -s nullglob
existing=("$SESSIONS_DIR"/*-"$SID_SHORT"-"$TRIGGER".md)
shopt -u nullglob
if (( ${#existing[@]} > 0 )); then
  wp_log "already captured session=$SID_SHORT trigger=$TRIGGER; skipping"
  exit 0
fi

# --- Build composed prompt ----------------------------------------------------
if [[ ! -f "$PLUGIN_ROOT/prompts/capture-system.md" ]]; then
  wp_log "capture-system.md missing at $PLUGIN_ROOT/prompts/; aborting"
  exit 0
fi

SYSTEM_PROMPT="$(cat "$PLUGIN_ROOT/prompts/capture-system.md")"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_DATE="$(date -u +%Y-%m-%d)"
NOW_HHMM="$(date -u +%H%M)"

PROMPT_FILE="$(mktemp -t cc-auto-wiki-prompt.XXXXXX)"
trap 'rm -f "$PROMPT_FILE"' EXIT

{
  printf '%s\n' "$SYSTEM_PROMPT"
  printf '\n---\n\n# Capture guidance (project-specific, from %s)\n\n' "$SCHEMA"
  printf '%s\n' "$GUIDANCE"
  printf '\n---\n\n# Session metadata\n\n'
  printf -- '- session_id: %s\n' "$SESSION_ID"
  printf -- '- trigger: %s\n' "$TRIGGER"
  printf -- '- captured_at: %s\n' "$NOW_ISO"
  printf '\n---\n\n# Task\n\nThe transcript for this session is a JSONL file at:\n\n%s\n\n' "$TRANSCRIPT_PATH"
  printf 'Use the Read tool to read it (in chunks if it is long). Then produce the markdown output exactly as specified in the system instructions above. Output ONLY the markdown body — start with the "# <topic>" line, no preamble.\n'
} > "$PROMPT_FILE"

# --- Invoke claude -p ---------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  wp_log "claude CLI not on PATH; cannot capture"
  exit 0
fi

wp_log "invoking claude -p model=$MODEL session=$SID_SHORT trigger=$TRIGGER"
# WIKI_PLUGIN_INTERNAL=1 makes the sub-invocation's hook short-circuit, so we
# don't recurse when the headless session ends and fires SessionEnd.
RESULT_JSON="$(WIKI_PLUGIN_INTERNAL=1 claude -p "$(cat "$PROMPT_FILE")" \
  --allowedTools "Read" \
  --output-format json \
  --model "$MODEL" 2>>"$WP_LOG_FILE")" || {
  wp_log "claude -p exited non-zero"
  exit 0
}

if [[ -z "$RESULT_JSON" ]]; then
  wp_log "claude -p produced no output"
  exit 0
fi

IS_ERROR="$(jq -r '.is_error // false' <<<"$RESULT_JSON" 2>/dev/null || echo false)"
if [[ "$IS_ERROR" = "true" ]]; then
  ERR_MSG="$(jq -r '.result // "(no message)"' <<<"$RESULT_JSON" 2>/dev/null)"
  wp_log "claude -p reported is_error=true: $ERR_MSG"
  exit 0
fi

BODY="$(jq -r '.result // empty' <<<"$RESULT_JSON" 2>/dev/null || true)"
if [[ -z "$BODY" ]]; then
  wp_log "could not parse .result from claude output"
  exit 0
fi

# Trim any preamble the model may emit before the first H1. The system prompt
# says to start with "# <topic>", but models sometimes prepend "Here is the
# capture:" or similar. Drop everything up to and including the line before
# the first "# " heading.
BODY="$(printf '%s\n' "$BODY" | awk '/^# / { found = 1 } found')"
if [[ -z "${BODY//[[:space:]]/}" ]]; then
  wp_log "no H1 heading found in model output; aborting"
  exit 0
fi

# Pull the topic from the first H1 line for the log entry.
TOPIC="$(printf '%s\n' "$BODY" | awk '/^# / { sub(/^# */, ""); print; exit }')"
[[ -z "$TOPIC" ]] && TOPIC="(untitled)"

# --- Write the raw source -----------------------------------------------------
OUT_FILE="$SESSIONS_DIR/${NOW_DATE}-${NOW_HHMM}-${SID_SHORT}-${TRIGGER}.md"

{
  printf -- '---\n'
  printf -- 'session_id: %s\n' "$SESSION_ID"
  printf -- 'trigger: %s\n' "$TRIGGER"
  printf -- 'captured_at: %s\n' "$NOW_ISO"
  printf -- 'compiled: false\n'
  printf -- 'topics: []\n'
  printf -- '---\n\n'
  printf '%s\n' "$BODY"
} > "$OUT_FILE"

# --- Append log entry ---------------------------------------------------------
LOG="$WIKI_ROOT/log.md"
{
  printf '\n## [%s] capture | %s\n\n' "$NOW_DATE" "$TOPIC"
  printf -- '- trigger: %s\n' "$TRIGGER"
  printf -- '- source: [%s](raw/sessions/%s)\n' "$(basename "$OUT_FILE")" "$(basename "$OUT_FILE")"
} >> "$LOG"

wp_log "captured -> $OUT_FILE"
exit 0
