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

1. Create `spar-scratch/` at the repository root (suffix the name if taken; never overwrite existing paths) and state its path; the reviewer cannot read outside the repository, and the directory is deleted at cleanup. Draft the plan there as `spar-plan.md`: goal, constraints, approach, ordered steps, files touched, risks, open questions. No placeholders; every step names its files or commands and its verification. Keep an objection log at the file's tail (id | blocking | claim | status | closure basis): claims are immutable, status and closure basis update in place, rows are never deleted.
2. Round 0, blind sketch: send the reviewer only the goal and constraints, inline and never in any plan-bearing file (goal and constraints that exceed the argv budget go in a blind handoff file without the plan), and ask for a 3-5 bullet independent approach sketch; capture the pinned session id. This exists to prevent anchoring on the author's framing.
3. Round 1: prepend the charter below to `spar-plan.md` and send a short pointer prompt naming the file; instruct the reviewer to compare the plan against its own sketch and treat divergences as challenge material.
4. Each later round: verify each objection's ground before responding (read the cited file, run the cited command); amend on confirmed objections, rebut disputed ones with evidence, return ungrounded ones for a ground; never amend on the reviewer's say-so alone. Record the dispositions by number and the full amended plan, not a diff, in the handoff file and send a pointer prompt.
5. An objection closes only by plan amendment, by refuting evidence the reviewer accepts with a stated reason, or by the user's ruling. Agreement without new evidence or an amendment closes nothing; record it as unresolved (capitulation, not persuasion, is the dominant two-model failure mode).
6. Convergence requires zero open blocking objections plus a final cold read: a fresh reviewer session receives a clean handoff of goal, constraints, charter, and the final plan (never the objection log, dispositions, or round history) and raises no new blocking objections. Cap: 4 rounds, a ceiling not a target; stop early once a round changes no positions.
7. Converged or capped, stop and present to the user before any execution: the final plan; each side's one-paragraph position and the implementer's one-line recommended ruling, labeled judgment, on every open or disputed item; and the reviewer session ids for interactive handoff. Convergence between the models is not correctness, and disagreement surviving the cap is signal for the user, not failure. Execute only on the user's go.
8. After execution, send `git diff` (plus test output when available) to the same reviewer session for a final review. Drift check: compare diff and approved plan in both directions; unplanned changes and silently skipped plan steps are objections by default. Relay findings verbatim; they reach the user before any fix.

Diff-only mode, for work that did not go through a sparred plan: run steps 2 and 8 alone. Create the pinned session with a brief statement of the goal, then send the diff with the charter adapted to implementation review; the same objection, closure, and verdict rules apply, and findings go to the user before any fix is made.

## Reviewer charter (send verbatim in round 1)

You are the read-only reviewer in an adversarial planning loop; a different model drafted the plan. Challenge it on logic and evidence, not tone. Make each objection a single verifiable claim with a concrete failure scenario; number it, label it blocking or non-blocking, and ground it in a file, command, or document. Blocking means: left unaddressed, the plan fails its goal, corrupts state, or acts irreversibly without a recovery path. From round 2 on, raise new objections only if blocking. Treat the plan's stated confidence and verification claims as claims to verify, not as evidence. Do not agree to be agreeable: withdrawing an objection requires new evidence or an amendment, stated explicitly; agreement without either counts as unresolved. If you find nothing blocking on a first read, cite the three weakest points of the plan before your verdict stands. A sound plan deserves a short confirmation; inventing objections is as much a failure as rubber-stamping. End every reply with `VERDICT: CONVERGED` or `VERDICT: OPEN <blocking> BLOCKING / <non-blocking> NON-BLOCKING`.

## Rules

- The reviewer is advisory and read-only; the implementer alone edits files, and only after the user approves the plan.
- Relay reviewer objections in substance; do not soften or reframe them.
- Disagreements the implementer cannot resolve with evidence go to the user as disputed items, never silently accepted or dropped.
- If the reviewer bridge fails, report and stop; never substitute self-review.
- Delete the spar scratch directory during completion cleanup per the shared scratch rules.
