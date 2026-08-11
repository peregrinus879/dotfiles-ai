---
name: spar
description: Cross-model plan sparring with adversarial review rounds to evidence-based convergence, then execution and diff review.
---

# Spar - Cross-Model Plan Sparring

Adversarial plan review between Claude Code and OpenCode: the session running this skill is the implementer; the counterpart model is a read-only reviewer in a pinned headless session. Convergence is evidence-based, and the user arbitrates anything left open.

## Reviewer incantations

Requires: the `claude` CLI and `jq`. Read-only enforcement comes entirely from the flags below, so no Claude-side config is needed. For prompt-free rounds this repo's `opencode.json` allows `claude -p *` in the bash permission map, inserted before the redirect guard block where verify requires allow entries to sit.

The reviewer is Claude Code (repeat every flag on every call; they do not persist across resumes):

- First round: `sid=$(timeout 300 claude -p --output-format json --permission-mode plan --disallowedTools "Write Edit NotebookEdit Bash" --model claude-fable-5 "<prompt>" | jq -r .session_id)`; the reply text is in `.result`.
- Later rounds: the same flags plus `--resume "$sid"`.
- Interactive handoff for the user: `claude -r "$sid"`.

## Protocol

1. Draft the plan into the session scratch directory as `spar-plan.md`: goal, approach, ordered steps, files touched, risks, open questions. State the path to the user.
2. Round 0, blind sketch: send the reviewer only the goal and constraints, not the plan, and ask for a 3-5 bullet independent approach sketch; capture the pinned session id. This exists to prevent anchoring on the author's framing.
3. Round 1: send the reviewer the full plan text with the charter below; instruct it to compare the plan against its own sketch and treat divergences as challenge material.
4. Each later round: answer every objection by number, either amending the plan or rebutting with evidence (file contents, command output, document citations); send the rebuttals plus the full amended plan, not a diff.
5. An objection closes only by plan amendment, by refuting evidence the reviewer accepts with a stated reason, or by the user's ruling. Agreement without new evidence or an amendment closes nothing; record it as unresolved (capitulation, not persuasion, is the dominant two-model failure mode).
6. Convergence requires zero open blocking objections plus a final cold read: the reviewer rereads the complete amended plan fresh and confirms no new blocking objections. Cap: 4 rounds, a ceiling not a target; stop early once a round changes no positions.
7. Converged or capped, stop and present to the user before any execution: the final plan, each side's one-paragraph position on every open or disputed item, and the reviewer session id for interactive handoff. Convergence between the models is not correctness, and disagreement surviving the cap is signal for the user, not failure. Execute only on the user's go.
8. After execution, send `git diff` (plus test output when available) to the same reviewer session for a final review; relay its findings verbatim.

Diff-only mode, for work that did not go through a sparred plan: run steps 2 and 8 alone. Create the pinned session with a brief statement of the goal, then send the diff with the charter adapted to implementation review; the same objection, closure, and verdict rules apply, and findings go to the user before any fix is made.

## Reviewer charter (send verbatim in round 1)

You are the read-only reviewer in an adversarial planning loop; a different model drafted the plan. Challenge it on logic and evidence, not tone. Make each objection a single verifiable claim with a concrete failure scenario; number it, label it blocking or non-blocking, and ground it in a file, command, or document. Treat the plan's stated confidence and verification claims as claims to verify, not as evidence. Do not agree to be agreeable: withdrawing an objection requires new evidence or an amendment, stated explicitly; agreement without either counts as unresolved. If you find nothing blocking on a first read, cite the three weakest points of the plan before your verdict stands. A sound plan deserves a short confirmation; inventing objections is as much a failure as rubber-stamping. End every reply with `VERDICT: CONVERGED` or `VERDICT: OPEN <blocking> BLOCKING / <non-blocking> NON-BLOCKING`.

## Rules

- The reviewer is advisory and read-only; the implementer alone edits files, and only after the user approves the plan.
- Relay reviewer objections in substance; do not soften or reframe them.
- Disagreements the implementer cannot resolve with evidence go to the user as disputed items, never silently accepted or dropped.
- Delete the scratch plan file during completion cleanup per the shared scratch rules.
