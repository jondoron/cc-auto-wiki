#!/usr/bin/env bash
# Shared helpers for cc-auto-wiki hook scripts.
# Source this file; do not execute it directly.

WP_DEFAULT_MODEL="claude-haiku-4-5-20251001"
WP_LOG_FILE="${WP_LOG_FILE:-$HOME/.claude/cc-auto-wiki.log}"

wp_log() {
  mkdir -p "$(dirname "$WP_LOG_FILE")" 2>/dev/null || return 0
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$WP_LOG_FILE"
}

wp_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    wp_log "jq not found on PATH; cannot continue"
    return 1
  fi
}

# Merge .claude/settings.json and .claude/settings.local.json (local wins).
# Echoes a JSON object on stdout, or "{}" if neither file exists.
wp_load_settings() {
  local cwd="$1"
  local main="$cwd/.claude/settings.json"
  local local_overrides="$cwd/.claude/settings.local.json"

  if [[ -f "$main" && -f "$local_overrides" ]]; then
    jq -s '.[0] * .[1]' "$main" "$local_overrides"
  elif [[ -f "$main" ]]; then
    jq '.' "$main"
  elif [[ -f "$local_overrides" ]]; then
    jq '.' "$local_overrides"
  else
    echo '{}'
  fi
}

# Echo the wiki root absolute path. Return non-zero if not configured.
wp_wiki_root() {
  local cwd="$1"
  local root
  root=$(wp_load_settings "$cwd" | jq -r '."cc-auto-wiki".root // empty')
  [[ -z "$root" ]] && return 1
  if [[ "$root" != /* ]]; then
    root="$cwd/$root"
  fi
  echo "$root"
}

# Echo the model name to use for capture, defaulting if unset.
wp_model() {
  local cwd="$1"
  wp_load_settings "$cwd" | jq -r --arg d "$WP_DEFAULT_MODEL" '."cc-auto-wiki".model // $d'
}

# Extract the body of the "## Capture guidance" section from a markdown file.
# Stops at the next "## " heading or end of file.
wp_slice_guidance() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  awk '
    /^## Capture guidance[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## / { in_section = 0 }
    in_section { print }
  ' "$file"
}

# Encode a cwd into the project-directory name Claude Code uses
# (e.g. /Users/foo/bar -> -Users-foo-bar).
wp_encode_cwd() {
  local cwd="$1"
  echo "${cwd//\//-}"
}

# Echo the path of the most-recently-modified transcript jsonl for a given cwd.
# Honors CLAUDE_CONFIG_DIR; falls back to ~/.claude.
wp_latest_transcript() {
  local cwd="$1"
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local proj_dir="$config_dir/projects/$(wp_encode_cwd "$cwd")"
  [[ -d "$proj_dir" ]] || return 1
  # shellcheck disable=SC2012
  ls -t "$proj_dir"/*.jsonl 2>/dev/null | head -n 1
}

# Echo a short (8-char) version of a session id for filenames.
wp_session_short() {
  local sid="$1"
  echo "${sid:0:8}"
}
