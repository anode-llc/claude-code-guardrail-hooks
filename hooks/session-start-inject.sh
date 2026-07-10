#!/usr/bin/env bash
#
# session-start-inject.sh — Stage (1) PREVENT
#
# Runs on the SessionStart event. Injects standing context into the model
# before any work begins, so that recurring premises are re-stated every
# session instead of relying on the model to remember them.
#
# Claude Code contract:
# - stdin  : JSON with { "hook_event_name": "SessionStart", "source": ... }
# - stdout : JSON with hookSpecificOutput.additionalContext (a string).
#            That string is prepended to the model's context for the session.
# - Keep it short. This text is spent on every session, so treat it as a
#   budget, not a dumping ground.
#
# This is a skeleton. Fill in build_context() with the premises you want the
# model to see every time (recent work log, active constraints, house rules).
# Emit nothing (exit 0 with no output) when there is nothing to inject.

set -euo pipefail

# CLAUDE_PROJECT_DIR is set by Claude Code at hook time. Do not rely on the
# current working directory: hooks may run after a cd into another directory.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ---------------------------------------------------------------------------
# build_context: assemble the text to inject. Return it on stdout.
# Return an empty string to inject nothing.
#
# Example ideas (implement what fits your environment):
#   - the last N entries of a work log so the model resumes with continuity
#   - active constraints that are easy to forget mid-session
#   - a pointer to the house rules the model must follow
# ---------------------------------------------------------------------------
build_context() {
  local ctx=""

  # --- PLACEHOLDER: replace with your own context assembly ---------------
  # Example: inject a work-log tail if the file exists.
  #
  #   local log_file="${PROJECT_DIR}/WORKLOG.md"
  #   if [ -f "$log_file" ]; then
  #     ctx="<recent-work>"$'\n'"$(head -n 40 "$log_file")"$'\n'"</recent-work>"
  #   fi
  # -----------------------------------------------------------------------

  printf '%s' "$ctx"
}

CONTEXT="$(build_context)"

# Nothing to inject: exit quietly.
if [ -z "$CONTEXT" ]; then
  exit 0
fi

# Emit the structured SessionStart output. additionalContext must be a JSON
# string; jq handles the escaping.
jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
