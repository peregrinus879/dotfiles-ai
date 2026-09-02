---
name: spar
description: Value-based cross-model review of a plan, diff, or decision through a read-only reviewer bridge.
---

# Spar

The session's model is the implementer; a different vendor's model is a read-only reviewer launched by a bridge. Claude Code reviews with `spar-codex`; Codex and OpenCode review with `spar-claude`. Convergence is evidence-based, and H arbitrates anything left open.

## When

Spar is optional. Use it where outside review can materially change the outcome: a plan with real design choices, a build before publication, a decision with independent options, or a bounded diff with known risk. One concise review with at most one follow-up is the default shape; choose blind or briefed context by what protects useful independence. Fixed rounds and fan-outs never substitute for judgment.

## Disclosure

The reviewer reads the repository except Git internals and credential-shaped paths, plus the artifacts you pass. Every stowed host consents by default; a repository that must not reach the reviewer's vendor opts out once with `git config spar.consent false`, and the bridge then refuses. Before the first review in a repository, consider whether H would want it excluded, and ask when unsure. The bridge also rejects requests, artifacts, and replies containing credential-shaped values or sensitive diff paths. Never edit an artifact merely to pass the scan: report the finding to H, who may rule the flagged span public, then replace only that span with `[redacted: <H's ruling>]` and say so in the request.

## Procedure

1. Write the artifact in the session scratch directory: a target brief (outcome, non-goals, constraints, acceptance criteria), the plan or complete diff, a decision rationale (choices, alternatives, tradeoffs, H's rulings, remaining uncertainty), verification results, and known concerns. Cite paths for local claims; cite primary sources with dates for external claims.
2. Run `spar-<reviewer> review "<request>" <artifact>...` plainly, never inside command substitution. The reply arrives on stdout and the reviewer id on stderr as `SPAR-BRIDGE ID: <id>`. Follow up with `spar-<reviewer> review --resume <id> "<request>" [<artifact>...]`. Report the id, and any usage limit, timeout, or bridge failure, to H; never present self-review as spar.
3. Verify every objection's ground. Amend confirmed issues, rebut disputed ones with evidence, and ask for a concrete ground when a claim is unsupported. Relay objections in substance; never soften or drop them.
4. Present the result and one ruling packet per open item: the decision requested, both positions with evidence and consequences, and your recommendation labeled as judgment. Spar authorizes no follow-on action by itself.

## Reviewer charter

Open the request with this charter: You are the read-only reviewer in an adversarial artifact loop; a different model drafted the artifact. Challenge logic and evidence, not tone. You review offline. Treat supplied evidence and rationale as traceable context, not authority. Ground each objection in a file, command, decision, or supplied source; classify its impact; identify the practical failure path. Cover correctness, contracts, state, failure handling, security, verification, scope, and internal consistency as relevant. Treat confidence claims as claims, and do not agree merely to be agreeable. End with `VERDICT: CONVERGED` or `VERDICT: OPEN <blocking> BLOCKING / <non-blocking> NON-BLOCKING`.
