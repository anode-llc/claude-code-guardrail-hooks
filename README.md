# claude-code-guardrail-hooks

Template hooks for turning a written rule that an AI agent keeps ignoring into
a mechanism that runs whether the agent cooperates or not.

If you hand an AI agent a rulebook (a `CLAUDE.md`, a house-style doc) and the
agent still breaks the rules, that is not a defect — following natural-language
instructions is probabilistic, and the longer a session runs the more the
rules recede. The fix is not a thicker rulebook. It is to move the rules that
cause real harm when broken out of the "please" world and into the "the
machine always runs this" world. In Claude Code, that mechanism is a **hook**:
a script that runs at a fixed point in the agent's work — before a write, after
a write, at session start, at session end — without going through the agent's
judgment.

But mechanisms are strong, and a control that is too strong freezes the floor:
it blocks legitimate work, the agent hits the same wall over and over, and a
human ends up babysitting it. So the point is not "mechanize everything." The
point is to match the strength of each control to the harm of breaking the
rule it enforces. This repo gives you four stages to sort your rules into, and
one skeleton hook per stage.

## The four-stage control decision table

Walk your rulebook one line at a time and ask three questions of each rule:

1. **Violation cost** — how much harm when it is broken?
2. **False-positive risk** — how likely is a check to also stop legitimate work?
3. **Human override** — is there a situation where a person needs to bend the
   rule on purpose?

Then sort each rule into one of four stages. Do not push everything into DENY.
Strong controls are for the high-cost lines only.

| Stage | When to use it (decision axes) | Claude Code event | Hook in this repo |
|---|---|---|---|
| **(1) Prevent** | Cheaper to never trigger the violation; a premise you want re-stated every time | `SessionStart` — inject the premise at the start of work | `hooks/session-start-inject.sh` |
| **(2) Deny** (hard control) | Breaking it causes real harm **and** the detection pattern is narrow | `PreToolUse` — refuse the write before it happens | `hooks/pre-write-deny.sh` |
| **(3) Warn** (soft control) | Low harm per violation, but it rots if ignored; you must not block on it | `PostToolUse` — warn after the write, never block | `hooks/post-write-warn.sh` |
| **(4) Remind** (catch inaction) | You need to catch what *didn't* happen (a forgotten record) | `Stop` / `SubagentStop` — nudge at the end of work | `hooks/stop-remind.sh` |

The mapping in one line each:

- **(1) Prevent** — stop the violation from arising in the first place. Cheaper
  to hand the agent the premise up front than to catch a violation later. Like
  handing a new hire the onboarding doc every time: pre-paid training cost.
- **(2) Deny** — the strongest stage. Only for rules that cause real harm when
  broken *and* whose detection pattern is narrow enough to avoid false
  positives. Because it is strong it is dangerous, so it ships with two safety
  devices (below).
- **(3) Warn** — for what is not worth stopping but rots if left unseen. The
  write goes through; a check runs afterward and warns only. Because it never
  blocks, a false positive does not freeze the floor.
- **(4) Remind** — a different shape: it catches *inaction*. A DENY hook
  inspects writes, so it can never notice a required record that was simply
  never written. This stage nudges at session end — softly, so discussion-only
  sessions are not nagged.

## Install

The hooks read `$CLAUDE_PROJECT_DIR`, so they work from anywhere in your repo.

```bash
# 1. Copy the hooks into your project.
git clone https://github.com/anode-llc/claude-code-guardrail-hooks
cp -r claude-code-guardrail-hooks/hooks ./hooks && chmod +x ./hooks/*.sh

# 2. Merge settings.example.json into your project's .claude/settings.json
#    (copy the "hooks" block; keep your existing settings).
cp claude-code-guardrail-hooks/settings.example.json .claude/settings.json
```

Each script is a **skeleton**: it runs as-is with a generic placeholder rule,
but the detection logic marked `PLACEHOLDER` is meant to be replaced with your
own. Deliberately **not** included: any environment-specific allowlist of
exceptions (the places where a "violation" is actually fine). That list is
specific to your rules — the skeleton leaves the frame and you fill in the
substance.

Requires `bash`, `jq`, and `python3` on `PATH`.

## The scripts

### `hooks/session-start-inject.sh` — (1) Prevent

Runs on `SessionStart`. Returns text in
`hookSpecificOutput.additionalContext`, which Claude Code prepends to the
session. Fill in `build_context()` with the premises you want re-stated every
session (a recent work-log tail, active constraints, a pointer to house
rules). Keep it short — this text is spent on every session. Emits nothing
when there is nothing to inject.

### `hooks/pre-write-deny.sh` — (2) Deny

Runs on `PreToolUse` for `Edit`/`Write`. Reads the pending write from stdin,
and if it introduces a violation, returns a structured **deny** decision that
stops the write. Fill in `find_violations()` with your own detection. Ships
with both safety devices and is designed for a 5-second timeout — see below.

### `hooks/post-write-warn.sh` — (3) Warn

Runs on `PostToolUse` for `Edit`/`Write`. The write has already happened, so
it reads the file from disk, scans it, and prints a warning if it finds a
flagged pattern. It never blocks. Fill in the scan with your own detection
(e.g. non-English comments in a repo you publish in English, leftover markers,
secret-shaped strings).

### `hooks/stop-remind.sh` — (4) Remind

Runs on `Stop` / `SubagentStop`. Checks whether an expected artifact is missing
and, if the session actually did work (it reads the transcript to skip
discussion-only sessions), nudges to produce it. It does not hard-stop.

## Safety devices on the DENY hook

A hard block is the most effective stage and the most likely to freeze the
floor. To make a DENY hook something you can leave installed permanently, it
needs two safety devices. A deny hook without them gets ripped out sooner or
later.

### (a) New-violations-only (false-positive guard)

The naive version inspects the whole file and blocks if any unit violates the
rule. That breaks immediately: if a pre-existing violation is already in the
file (written before you introduced the rule), then every future edit to that
file — even edits to an unrelated part — is blocked by that old, unrelated
violation. The tool deadlocks.

The fix: an edit carries **both** the text before (`old_string`) and the text
after (`new_string`). Inspect only the violations that the new text introduces
and that were not already present in the old text. Pre-existing debt passes
through untouched. You do not force a cleanup of old debt on every write. This
diff is implemented in `find_violations()` in `pre-write-deny.sh`.

### (b) Emergency bypass (escape hatch)

A mechanical block, precisely when it is working correctly, also forbids the
human's legitimate "just this once." For example, migrating old records may
require passing through a temporarily invalid state. If the machine allows no
exception, that legitimate work cannot proceed. Provide exactly one explicit
bypass — an environment variable — that disables the check for a single task:

```bash
SKIP_GUARDRAIL_CHECK=1 claude   # disable the deny hook for this run
```

Leaving it set permanently is itself a policy violation, but it must exist as
the escape hatch for when a human decides "for this task I am intentionally
turning it off." (The internal deployment this template is generalized from
uses a rule-specific name, `KOVITO_SKIP_SUMMARY_CHECK`; the public template
uses the generic `SKIP_GUARDRAIL_CHECK` — rename it to fit your rule.)

### 5-second timeout

Wire a short timeout (5s) on the deny hook in `settings.json` (see
`settings.example.json`). If the check ever hangs, the timeout drops it and the
write proceeds. This is insurance against the control itself breaking and
deadlocking all work — a broken guardrail should fail open, not freeze the
floor.

## Technical note: why `permissionDecision: "deny"`, not a non-zero exit

If you run Claude Code with `bypassPermissions` (the "don't ask me for every
action" mode), there is a trap: a hook that "blocks" the naive way — by exiting
with a non-zero status — does **not** reliably stop the write. Under
bypassPermissions the write can slip through. To stop it for certain, the hook
must return a structured deny decision on stdout and exit `0`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "…why it was blocked…"
  }
}
```

The management translation: a control is most dangerous when you *think* you
installed it. Depending on the run mode, a control you believe is in place may
not actually stop anything. So the thing to measure is not "did I add a
control" but "does it actually stop." Test that your deny hook actually blocks
under the mode you run in.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Anode LLC.
