---
name: spar
description: Value-based cross-model brainstorming, plan, build, and diff review with evidence-based convergence.
allowed-tools: Bash(spar-codex *)
---

# Spar - Cross-Model Sparring

Adversarial review between the session's tool and its cross-vendor counterpart: the session running this skill is the implementer; the counterpart model is a read-only reviewer in a bridge-controlled headless session. Convergence is evidence-based, and the user arbitrates anything left open.

## Reviewer incantations

Requires: the `codex` CLI and the directly stowed `spar-codex` bridge (this repo, codex/.local/bin). The bridge rejects Git-control variables, repository hard-linked files outside denied directories, nested repository mounts, and entries beyond its deny-glob depth; binds every handoff and resumable primary thread to the caller's canonical Git root; then launches from that root with runtime-minimal reads plus read-only repository and handoff grants. Later OS permission rules deny Git internals, credential-shaped repository paths, the handoff's `reviewer-id`, root and temporary paths outside the grants, writes, and command network. It ignores user config and rules, marks the active project untrusted, sets project instruction bytes to zero with an empty fallback list, and disables MCP, apps, plugins, hooks, web search, multi-agent, skills, shell snapshots, summaries, and caller-controlled state or routing. Exact ChatGPT-subscription and effective empty-plugin preflights run only after the bounded outbound prompt and handoff scan. The scanner also gates bounded replies and diagnostics, while the bridge validates ordered terminal events against the requested thread, owns the reviewer process group, reports failed-new thread ids, and never uses `--last`. Repository files outside the named sensitive paths may be sent to the subscription reviewer, including files in private repositories. Tracked permissions auto-approve `Bash(spar-codex *)`.

Filesystem-root repositories fail before grant construction, and plugin preflight accepts only a structurally empty `installed` array.

Repository path preflight validates every canonical-root component's spelling and every contained name without reading file contents. It rejects nested `.git` directories, sensitive directories without exact subtree denies, sensitive-named symlinks, symlinks below nested `secrets` trees whose deny depends on glob expansion, case variants of sensitive names, non-UTF-8 names, and control-, quote-, or backslash-bearing names while preserving ordinary public symlinks. The scanner parses LF-delimited Git records, preserves significant path whitespace, rejects decoded NUL, and strictly decodes C-quoted paths before applying the sensitive-name grammar to every path component shared with reviewer policies and native handoff-write gates.

The reviewer is Codex (model pinned inside the bridge; update it there when the preferred model changes):

- Handoff: run `spar-codex init`, record its output as `HANDOFF`, and use only that exact path for the run. Recovery discovery: `spar-codex status` lists validated handoffs with task title, mtime, and reviewer manifest.
- New review: run `spar-codex new "$HANDOFF" "<prompt>"` plainly, never via command substitution (allow rules do not match `$(...)` forms); the reply text arrives on stderr and the thread id on stdout. The bridge appends six-field timestamp, bridge, role, state (`started`, `completed`), id, and canonical repository-root records to its reserved `reviewer-id` manifest; state the literal thread id in the user presentation. If the fresh thread starts but the call later fails, the manifest and the `SPAR-BRIDGE THREAD` stderr line preserve the id. A deliberately independent one-pass review may use the trailing role argument `cold` and is never resumable.
- Follow-up review: `spar-codex resume <id> "$HANDOFF" "<pointer prompt>"`; the reply is stdout, and the bridge accepts only a `primary` id recorded for Codex in that handoff and the same canonical repository.
- Bridge exit codes: 2 preflight, 3 usage limit, 4 stall, 5 reviewer error, 124 ceiling; all follow the bridge-failure and limit rules.
- Interactive handoff for the user: `codex resume <id>`.

## Modes and Reviews

**Review judgment:** Plan and build are the primary spar checkpoints, not mandatory gates. The implementer decides whether, when, and how to spar from expected value, risk, uncertainty, independence, and cost, and may invoke spar at any other point where outside review can materially improve the outcome. Choose blind or fully briefed, fresh or resumed, single or iterative review as the work warrants; fixed calls, rounds, fan-outs, and review depth never substitute for judgment.

**Plan review:** Consider spar after research and analysis and before presenting the final plan. Use `spar-plan.md` to brief the reviewer on the outcome, constraints, proposed approach, evidence, Decision Rationale, risks, and open questions. H approves the resulting plan; only H's approval of each exact candidate authorizes a commit.

**Build review:** Consider spar after all approved commits and before push. Use `spar-diff.md` with artifact kind `build review` and include the latest approved plan and Decision Rationale, H's rulings and authorized changes, starting base, commit list, complete `git diff --binary <base>..HEAD`, worktree status, aggregate verification, warnings and omissions, and a diff hash. Ask whether the implementation matches the current authorized direction and whether cross-unit defects or plan drift remain. Findings may return as a proposed fix-forward unit while leaving the worktree intact; reviewer convergence never authorizes a commit or push.

**Brainstorming:** Use `spar-brainstorm.md` when independent option generation or challenge would improve a decision. Give the reviewer the outcome, constraints, knowns, unknowns, decision criteria, and relevant evidence; choose the review shape that best protects useful independence. The result is decision-ready input, not option approval.

**Diff-only:** Use `spar-diff.md` for focused review of work without a sparred plan or whenever a bounded artifact review adds value. Include the goal, relevant rationale, complete diff, verification, and known concerns.

## Protocol

1. Use the reviewer bridge's `init` mode to create one private `/var/tmp/spar-<session-id>/` directory and state its path; never create or substitute it manually. Begin the artifact with a target brief covering the requested outcome, desired end state, non-goals, constraints, acceptance criteria, and artifact kind. Add a `Decision Rationale` that explains material choices, supporting research, alternatives considered, tradeoffs, H's rulings, authorized changes, and remaining uncertainty so the reviewer can assess the reasoning without repeating completed research. Include an `Evidence Pack` for material changeable external claims with primary-source URLs, retrieval dates, applicable versions, supporting excerpts or observations, and dependent decisions. Local claims cite paths; command claims include literal captured output when the reviewer cannot execute them.
2. Pass the exact handoff to every call. When follow-up review is useful, track objections and dispositions in `spar-objections.md` without erasing the original claims. After every native file-tool write, run the bridge's `flush` mode before any other action; the bridge also flushes before calls. The bridge's `status` mode supports re-entry, and its `clean` mode owns final cleanup.
3. Select reviewer context deliberately. Blind or fresh review protects independence; fully briefed or resumed review preserves accumulated rationale. Use `primary` sessions for resumable work and the `cold` role for deliberately independent one-pass review.
4. Verify every objection's ground before responding. Amend confirmed issues, rebut disputed ones with evidence, and ask for a concrete ground when a claim is unsupported. Re-fetch disputed external evidence; if it is unavailable or contradictory, mark the dependent decision unverified or escalate it.
5. Continue, change review shape, or stop according to whether further review is likely to add material information. A review converges when its verdict is well formed and no unresolved blocking objection remains. An unresolved evidence, value, or scope decision requiring user judgment goes to H.
6. Present the resulting artifact and one self-contained ruling packet per open or disputed item: exact decision requested; facts and uncertainty; both positions, evidence, consequences, and reversibility; affected work; implementer recommendation labeled judgment; and reviewer ids. Raw reviewer transcripts are never required. Spar authorizes no follow-on action by itself.

## Reviewer charter

You are the read-only reviewer in an adversarial artifact loop; a different model drafted the artifact. Challenge logic and evidence, not tone. You review offline: web search, web fetch, and general network access remain disabled. Treat supplied external evidence and the Decision Rationale as traceable context, not authority. Focus challenges to supported decisions on a concrete evidence defect, omitted constraint, invalid inference, material unaddressed consequence, or implementation drift rather than reopening them solely because another approach exists. Identify the affected rationale and practical failure path. Make each objection verifiable, classify its impact, and ground it in a file, command, decision, or supplied source. Review the classes relevant to the artifact, including correctness, contracts, state, failure handling, security, verification, procedure, internal consistency, scope, and actionability. Treat confidence claims as claims, not evidence, and do not agree merely to be agreeable. End with `VERDICT: CONVERGED` or `VERDICT: OPEN <blocking> BLOCKING / <non-blocking> NON-BLOCKING`.

## Rules

- The reviewer is advisory and read-only; the implementer alone edits files, and the bridge appends only the reviewer-id manifest. H's plan and commit authorization boundaries remain unchanged.
- The implementer owns current external verification and gives the reviewer the target, Decision Rationale, evidence, and relevant rulings.
- Relay reviewer objections in substance; do not soften, silently accept, or drop them. Disagreements the implementer cannot resolve with evidence go to H as disputed items.
- If the reviewer bridge fails, report the failure and never represent self-review as cross-model spar. Surface reviewer usage limits immediately and do not retry into a limit.
- Report reviewer ids and any material usage-limit, stall, or ceiling event.
- Handoff content files are written with the native file tools only; shell write channels into the handoff stay gated. Never create or edit `reviewer-id`; it is bridge-owned.
- If scanning rejects a known-safe prose draft, correct it in place with native tools; if it rejects a complete diff or verification artifact, never alter or exempt that artifact merely to pass. Stop for H if no safe complete representation exists.
- Re-entry after interruption: run the bridge's `status` mode, select the handoff by task title, and resume a valid `primary` manifest entry for that bridge or start a fresh review seeded from the handoff. Unrecorded and `cold` ids always start fresh. If no valid handoff survives, run fresh `init` and re-draft.
- Use the reviewer bridge's `clean` mode to delete this session's validated `/var/tmp/spar-<session-id>/` directory during completion cleanup.
