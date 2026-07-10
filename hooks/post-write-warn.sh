#!/usr/bin/env bash
#
# post-write-warn.sh — Stage (3) WARN (soft control)
#
# Runs on the PostToolUse event for Edit/Write. Inspects what was just written
# and emits a warning if it finds a pattern worth flagging — but never blocks.
# Use this stage for rules where a single violation does little harm but the
# debt rots if left unseen, and where blocking every write would freeze the
# work (e.g. content that is legitimate to write during development but must be
# cleaned up before some later milestone).
#
# Claude Code contract:
# - stdin  : JSON with { "tool_name", "tool_input": { "file_path", ... } }.
#            PostToolUse runs AFTER the write has already happened, so read the
#            file from disk rather than trusting the tool_input echo.
# - stdout : plain text. It is surfaced to the model as a warning. Emitting
#            text does NOT undo or block the write — that is the point.
# - Never deny here. Warning only. If you need to stop a write, that rule
#   belongs in the DENY stage, not this one.
#
# This is a skeleton. Fill in scan_file() with your own detection.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only inspect Edit / Write on a real file.
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac
[ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ] || exit 0

# Scope the scan to the files this rule cares about.
#
# --- PLACEHOLDER: scope the rule to your target files -----------------------
# Example: only warn about source files being prepared for public release.
#
#   case "$FILE_PATH" in
#     *.md|*.txt) ;;      # in scope
#     *) exit 0 ;;        # out of scope
#   esac
# ----------------------------------------------------------------------------

# ── scan_file ───────────────────────────────────────────────────────────────
# Print one warning line per finding. Print nothing if the file is clean.
#
# The example below flags a placeholder pattern so the skeleton runs. Replace
# the grep with your own detection (e.g. non-English comments in a repo you
# publish in English, TODO markers, secrets-shaped strings).
FINDINGS=$(
  # --- PLACEHOLDER: replace with your own detection -------------------------
  # Example: flag lines containing the literal marker "FIXME".
  grep -n "FIXME" "$FILE_PATH" 2>/dev/null || true
  # --------------------------------------------------------------------------
)

# Nothing to warn about.
if [ -z "$FINDINGS" ]; then
  exit 0
fi

COUNT=$(printf '%s\n' "$FINDINGS" | grep -c . || true)

cat <<EOF
[guardrail warning] ${COUNT} pattern match(es) in ${FILE_PATH}:
${FINDINGS}

This is a warning only — the write was NOT blocked. Clean this up before the
relevant milestone (e.g. before publishing / releasing).
EOF

exit 0
