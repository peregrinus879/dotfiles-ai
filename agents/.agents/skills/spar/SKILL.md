---
name: spar
description: Value-based cross-model review of a plan, diff, or decision through a read-only reviewer bridge.
---

# Spar

The session's model is the implementer; a different vendor's model is a read-only reviewer launched by a bridge. Claude Code reviews with `spar-codex`; OpenCode reviews with `spar-claude`; a Codex session cannot launch `spar-claude` inside its profile, so it prepares the request and artifact and asks H to run the bridge. Convergence is evidence-based, and H arbitrates anything left open.

## When

Spar is recommended before a plan is presented for approval and after implementation before the packet, and used at the model's discretion otherwise, where outside review can materially change the outcome: a plan with real design choices, a build before publication, a decision with independent options, or a bounded diff with known risk. It is never mandatory. Between the two reviewers: spar first when a second vendor's independent view can change the outcome, which is the first round on a review-recommended path; the `auditor` agent, the same loop inside the tool, when the review must read outside the repository, which the bridges never allow, when a follow-up round should keep the earlier findings, which the single-turn bridge cannot, or when the second vendor has already spoken. H's request naming either overrides this, and the packet names the reviewer that ran and its verdict. One concise review with at most one follow-up is the default shape; choose blind or briefed context by what protects useful independence. Fixed rounds and fan-outs never substitute for judgment.

## Disclosure

The reviewer reads the repository except Git internals and credential-shaped paths, plus the artifacts you pass, which must live under the repository or the session scratch directory. Every stowed host consents by default; a repository that must not reach the reviewer's vendor opts out once with `git config spar.consent false`, and the bridge then refuses. Before the first review in a repository, consider whether H would want it excluded, and ask when unsure. The bridge also rejects requests, artifacts, and replies containing credential-shaped values or sensitive diff paths. Never edit an artifact merely to pass the scan: report the finding to H, who may rule the flagged span public, then replace only that span with `[redacted: <H's ruling>]` and say so in the request.

## Procedure

1. Write the intent in the session scratch directory: lines starting `Outcome:`, `Non-goals:`, `Constraints:`, and `Acceptance:`, then the decision rationale (choices, alternatives, tradeoffs, H's rulings, remaining uncertainty) and known concerns, citing paths for local claims and primary sources with dates for external claims. Then run `~/.agents/skills/spar/scripts/review-brief --intent <file> --out <artifact> [--staged | --worktree | --range <base>..<tip> | --plan] [--gate <target>]...`, which assembles the artifact from evidence rather than claims: the intent verbatim, the head and status, the gate results as it runs them, and the change with its stat, scanned before it is kept. A plan with no diff yet uses `--plan`, which writes the intent, the state, and the gates with no change section.
2. Run `~/.agents/skills/spar/scripts/spar-<reviewer> review "<request>" <artifact>...` plainly, never inside command substitution; in OpenCode, give the shell tool a timeout of at least the bridge's, 1800 seconds by default, since its 240-second default kills the call mid-review. The reply arrives on stdout and the reviewer id on stderr as `SPAR-BRIDGE ID: <id>`. Follow up with `~/.agents/skills/spar/scripts/spar-<reviewer> review --resume <id> "<request>" [<artifact>...]`. Report the id, and any usage limit, timeout, or bridge failure, to H; never present self-review as spar. The `auditor` agent takes the same artifact by path. A follow-up round resumes the same reviewer where the tool allows, with `--resume` on a bridge or a message to the agent, and otherwise hands the new round the previous findings; it never narrows the brief to make a round pass, and when the intent shrinks between rounds the request says so.
3. Verify every objection's ground. Amend confirmed issues, rebut disputed ones with evidence, and ask for a concrete ground when a claim is unsupported. Relay objections in substance; never soften or drop them.
4. Present the result and one ruling packet per open item: the decision requested, both positions with evidence and consequences, and your recommendation labeled as judgment. Spar authorizes no follow-on action by itself.

## Reviewer charter

Open the request with this charter: You are the read-only reviewer in an adversarial artifact loop; a different model drafted the artifact. Challenge logic and evidence, not tone. You review offline. Treat supplied evidence and rationale as traceable context, not authority. Ground each objection in a file, command, decision, or supplied source; classify its impact; identify the practical failure path. Cover correctness, contracts, state, failure handling, security, verification, scope, and internal consistency as relevant. Treat confidence claims as claims, and do not agree merely to be agreeable. End with `VERDICT: CONVERGED` or `VERDICT: OPEN <blocking> BLOCKING / <non-blocking> NON-BLOCKING`.
