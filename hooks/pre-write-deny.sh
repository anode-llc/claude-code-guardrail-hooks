#!/usr/bin/env bash
#
# pre-write-deny.sh — Stage (2) DENY (hard control)
#
# Runs on the PreToolUse event for Edit/Write. Inspects what is about to be
# written and blocks the write if it violates a rule that causes real harm
# when broken. This is the strongest stage: it stops the tool call before it
# happens. Use it only for rules where (a) a violation causes real damage and
# (b) the detection pattern is narrow enough to avoid false positives.
#
# Claude Code contract:
# - stdin  : JSON with { "tool_name", "tool_input": { "file_path",
#            "old_string", "new_string", "content", ... } }
# - To DENY: print structured JSON with
#     hookSpecificOutput.permissionDecision = "deny"
#   and exit 0. Under bypassPermissions mode a plain non-zero exit does NOT
#   reliably stop the write — only the structured "deny" decision does. See
#   the README technical note.
# - To ALLOW: exit 0 with no output.
#
# ── Two safety devices are mandatory for a deny hook to be permanent ───────
#
#   (a) NEW-VIOLATIONS-ONLY: an edit carries both the text before (old_string)
#       and the text after (new_string). Inspect only violations that the new
#       text introduces and that were not already present in the old text.
#       Otherwise a single pre-existing violation elsewhere in the file blocks
#       every future edit to that file — the tool deadlocks and the hook gets
#       ripped out. Do not force cleanup of old debt on every write.
#
#   (b) EMERGENCY BYPASS: a mechanical block, when working correctly, also
#       forbids the human's "just this once" exception. Provide one explicit
#       escape hatch (an env var) so a human can intentionally disable the
#       check for a specific task. Leaving it on permanently is a policy
#       violation, but it must exist.
#
# Also wire a short timeout (5s) in settings.json for this hook. If the check
# ever hangs, the timeout drops it and the write proceeds, so a broken control
# does not deadlock all work. See settings.example.json.
#
# This is a skeleton. Fill in find_violations() with your own detection.

set -euo pipefail

# ── Safety device (b): emergency bypass ────────────────────────────────────
# Rename this variable to something specific to your rule.
if [ "${SKIP_GUARDRAIL_CHECK:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only inspect the files this rule applies to. Narrow the target as much as
# possible — a rule that fires on every file is a rule that will be removed.
#
# --- PLACEHOLDER: scope the rule to your target files -----------------------
# Example: only guard a specific file.
#
#   case "$FILE_PATH" in
#     *"path/to/guarded-file.md") ;;   # in scope, keep going
#     *) exit 0 ;;                     # out of scope, allow
#   esac
# ----------------------------------------------------------------------------

# Only Edit / Write carry text to inspect.
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

# Pull the before/after text. Edit provides old_string + new_string; Write
# provides content (and has no prior text, so old is empty).
if [ "$TOOL_NAME" = "Edit" ]; then
  NEW_TEXT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty')
  OLD_TEXT=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // empty')
else
  NEW_TEXT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty')
  OLD_TEXT=""
fi

# ── find_violations ─────────────────────────────────────────────────────────
# Return a JSON array of violations (empty array [] means "allow").
# Implements safety device (a): report only violations present in the new text
# and NOT present in the old text.
#
# The example below is deliberately generic (a per-line length cap) so the
# skeleton runs. Replace the is_violation() logic with your own rule.
RESULT=$(NEW_TEXT="$NEW_TEXT" OLD_TEXT="$OLD_TEXT" python3 << 'PYEOF'
import os, json

new_text = os.environ.get("NEW_TEXT", "")
old_text = os.environ.get("OLD_TEXT", "")

# --- PLACEHOLDER: define what a violation is -------------------------------
# Return a normalized key for each candidate unit you want to check. Here the
# unit is a line and the rule is "no line longer than MAX_LEN characters".
# Swap in your own unit (a paragraph, a comment, a token) and your own test.
MAX_LEN = 300

def candidates(text):
    """Yield (key, unit) pairs. key is used for the old/new diff."""
    for line in text.splitlines():
        yield line, line

def is_violation(unit):
    return len(unit) > MAX_LEN

def describe(unit):
    preview = unit[:100].replace("\n", " ")
    return {"chars": len(unit), "over": len(unit) - MAX_LEN, "preview": preview}
# ---------------------------------------------------------------------------

# Safety device (a): only flag units that are new in this edit.
old_keys = {key for key, _ in candidates(old_text)}

violations = []
for key, unit in candidates(new_text):
    if key in old_keys:
        continue          # pre-existing, not introduced by this edit — skip
    if is_violation(unit):
        violations.append(describe(unit))

print(json.dumps(violations, ensure_ascii=False))
PYEOF
)

# No new violations → allow.
if [ "$RESULT" = "[]" ]; then
  exit 0
fi

# Build a human-readable reason for the denial.
REASON=$(RESULT="$RESULT" python3 << 'PYEOF'
import os, json

violations = json.loads(os.environ["RESULT"])
lines = ["Blocked by guardrail: this edit introduces a rule violation."]
lines.append("")
for v in violations:
    lines.append(f"  - {v['chars']} chars (over by {v['over']}): {v['preview']}...")
lines.append("")
lines.append("Fix the flagged content and write again.")
lines.append("Emergency bypass: set SKIP_GUARDRAIL_CHECK=1 to disable this hook for one task.")
print(chr(10).join(lines))
PYEOF
)

# ── DENY ────────────────────────────────────────────────────────────────────
# Structured deny decision. This is the only form that reliably stops a write
# under bypassPermissions mode. Note: exit 0, not non-zero.
jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
