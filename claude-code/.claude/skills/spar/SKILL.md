---
name: spar
description: Cross-model plan sparring with adversarial review rounds to evidence-based convergence, then execution and diff review.
disable-model-invocation: true
allowed-tools: Bash(opencode run *)
---

# Spar - Cross-Model Plan Sparring

Adversarial plan review between Claude Code and OpenCode: the session running this skill is the implementer; the counterpart model is a read-only reviewer in a pinned headless session. Convergence is evidence-based, and the user arbitrates anything left open.

## Reviewer incantations

Requires: the `opencode` CLI, `jq`, and a read-only `reviewer` agent in the OpenCode config; this repo tracks it in `opencode/.config/opencode/opencode.json` under `agent.reviewer` with `permission: { "edit": "deny", "bash": { "*": "deny" } }`. This skill's `allowed-tools` frontmatter pre-approves `Bash(opencode run *)` for the invoking turn, so no global allowlist entry is needed.

The reviewer is OpenCode (model pinned; update the pin when the preferred model changes):

- First round: `SID=$(timeout 300 opencode run --format json -m openai/gpt-5.6-sol --agent reviewer "<prompt>" | head -1 | jq -r .sessionID)`; validate the `ses_` prefix; the reply text is in the message events of the same output.
- Later rounds: `timeout 300 opencode run -s "$SID" -m openai/gpt-5.6-sol --agent reviewer "<prompt>"`, always run from the directory where the session was created (cross-directory resume hangs the CLI).
- Never pass `--auto`. Interactive handoff for the user: `opencode -s "$SID"`.

## Protocol

1. Draft the plan into the session scratch directory as `spar-plan.md`: goal, approach, ordered steps, files touched, risks, open questions. State the path to the user.
2. Round 1: send the reviewer the full plan text with the charter below; capture the pinned session id.
3. Each later round: answer every objection by number, either amending the plan or rebutting with evidence (file contents, command output, document citations); send the rebuttals plus the full amended plan, not a diff.
4. An objection closes only by plan amendment, by refuting evidence the reviewer accepts with a stated reason, or by the user's ruling. Agreement without a stated reason closes nothing; treat it as still open.
5. Convergence requires zero open blocking objections plus a final cold read: the reviewer rereads the complete amended plan fresh and confirms no new blocking objections. Round cap: 4.
6. Converged or capped, stop and present to the user before any execution: the final plan, each side's one-paragraph position on every open or disputed item, and the reviewer session id for interactive handoff. Execute only on the user's go.
7. After execution, send `git diff` (plus test output when available) to the same reviewer session for a final review; relay its findings verbatim.

## Reviewer charter (send verbatim in round 1)

You are the read-only reviewer in an adversarial planning loop; a different model drafted the plan. Challenge it on logic and evidence, not tone. Number every objection, label each blocking or non-blocking, and ground each in a file, command, or document. Do not agree to be agreeable: withdrawing an objection requires stating what evidence or amendment changed your assessment. A sound plan deserves a short confirmation; inventing objections is as much a failure as rubber-stamping. End every reply with `VERDICT: CONVERGED` or `VERDICT: OPEN <blocking> BLOCKING / <non-blocking> NON-BLOCKING`.

## Rules

- The reviewer is advisory and read-only; the implementer alone edits files, and only after the user approves the plan.
- Relay reviewer objections in substance; do not soften or reframe them.
- Disagreements the implementer cannot resolve with evidence go to the user as disputed items, never silently accepted or dropped.
- Delete the scratch plan file during completion cleanup per the shared scratch rules.
