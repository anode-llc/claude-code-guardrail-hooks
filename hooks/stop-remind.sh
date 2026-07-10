#!/usr/bin/env bash
#
# stop-remind.sh — Stage (4) REMIND (catch inaction)
#
# Runs on the Stop / SubagentStop event. Catches the thing a DENY hook
# structurally cannot: a write that never happened. The DENY stage inspects
# writes, so it can never notice a required record that was simply not written
# (e.g. a forgotten work-log entry). This stage does. At the end of a session
# it checks whether an expected artifact is missing and, if so, nudges — but
# does not hard-stop, so sessions that legitimately had nothing to record are
# not nagged.
#
# Claude Code contract:
# - stdin  : JSON with { "hook_event_name": "Stop"|"SubagentStop",
#            "transcript_path", ... }
# - stdout : plain text reminder. Surfaced to the model. Does not block the
#            stop; it is a nudge, not a gate.
# - Emit nothing (exit 0) when the expected artifact already exists, or when
#   the session did nothing that would require it.
#
# This is a skeleton. Fill in the two checks below for your own environment.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ── Check 1: does the expected artifact already exist? ──────────────────────
# If the thing you want done is already done, say nothing.
#
# --- PLACEHOLDER: replace with your own "already done?" test ----------------
# Example: a dated work-log entry for today.
#
#   LOG_FILE="${PROJECT_DIR}/WORKLOG.md"
#   TODAY=$(date '+%Y-%m-%d')
#   [ -f "$LOG_FILE" ] || exit 0               # no log file: not this project
#   if grep -qF "## $TODAY" "$LOG_FILE"; then
#     exit 0                                    # already recorded today: done
#   fi
# ----------------------------------------------------------------------------

# ── Check 2: did this session actually do work worth recording? ─────────────
# Read the transcript and skip if the session made no edits (discussion-only
# sessions should not be nagged to write a work record).
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if ! grep -qE '"name":[[:space:]]*"(Edit|Write|MultiEdit|NotebookEdit)"' "$TRANSCRIPT"; then
    exit 0   # no edits this session — nothing to remind about
  fi
fi

# ── Reminder ────────────────────────────────────────────────────────────────
# Reached only when the artifact is missing AND the session did real work.
cat <<EOF
[reminder] This session made edits but the expected record was not written.
Before you finish, add the record you normally keep (e.g. a work-log entry).
EOF

exit 0
