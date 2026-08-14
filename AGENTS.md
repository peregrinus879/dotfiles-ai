# AGENTS.md - dotfiles-ai

This repo stores portable user-level AI assistant configuration for Claude Code, Codex, and OpenCode, deployed to `$HOME` via GNU Stow: the stowed `claude-code/`, `codex/`, and `opencode/` payloads, the shared cross-tool guidance file, and the commit workflow used by all managed tools. Auth, session state, machine-local files, and generated host-specific config stay out.

## Load Map

- Claude Code loads `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` (stowed from `claude-code/`), then this file through the root `CLAUDE.md` `@AGENTS.md` import.
- Codex loads `~/.codex/AGENTS.md` (stowed from `codex/`, a symlink chain to the shared guidance file), then this file natively as the repo-root `AGENTS.md`.
- OpenCode loads `~/.config/opencode/AGENTS.md` (stowed from `opencode/`) and the shared guidance file through `instructions` in `opencode.json`, then this file.
- Skills load on invocation only. Repo-root docs are not stowed; `docs/maintenance.md` is an on-demand ledger, not session instructions.
- Repo-root `.claude/settings.json` and `opencode.json` are inert per-tool project config placeholders with no command grants.

## Invariants

- Shared cross-tool guidance is canonical in `claude-code/.claude/rules/shared-guidance.md`; extend it for new shared guidance and keep tool-specific mechanism in each tool's wrapper (share policy, separate mechanism). Codex consumes it through the `codex/.codex/AGENTS.md` symlink chain, never a copy.
- Sequence rule: every repo list, tree, and doc orders the tools Claude Code, Codex, OpenCode.
- Reviewer matrix (cross-vendor, subscription auth only): Claude Code spars with Codex via the stowed `spar-codex` bridge; Codex and OpenCode spar with Claude via the stowed `spar-claude` bridge; both bridges hard-code their safety flags, reject higher-precedence non-subscription auth, isolate reviewer customization, preflight subscription auth fail-closed, validate their timeout knobs (zero or malformed values abort), and own the private handoff lifecycle. `spar-codex` supplies one strict inline read-only profile to new and resumed calls; `spar-claude` exposes only `Read`, `Glob`, and `Grep`, with plan mode and the write-tool deny remaining defense in depth.
- Spar reviewers remain offline and read-only. The implementer supplies an outcome-level blind brief, a full target brief, and traceable evidence for current external claims; every user escalation is a self-contained ruling packet with both positions, consequences, and an implementer recommendation.
- When editing sibling dotfiles repos, use identical wording for shared concepts; only repo-specific values (scope, package lists, invariants) differ.
- Keep wrappers thin; detailed rationale goes in `README.md`.
- Versioned probes, limitations, deferred work, and watch items live in `docs/maintenance.md`. Read it before tool upgrades, permission or bridge changes, cross-host validation, `/doctor`, or deferred work; re-fetch doc-derivable facts at change time.
- Commit boundaries never alter, stage, or temporarily revert unrelated hunks. A mixed file is deferred or escalated to H for a split decision.
- Phased-work approval authorizes the plan's listed commits unless H explicitly excludes commits; execution completes and commits one verified unit before starting the next. A tracked commit outside an approved plan requires H's explicit commit authorization.
- Invoking the managed commit or spar skill never authorizes a tracked commit or reviewer run; explicit instruction or approved phased work remains required.
- Claude Code pins `permissions.defaultMode` `"auto"` deliberately. Native `Edit`, `Write`, and `NotebookEdit` asks remain deterministic; text shell guards are incomplete and operator-based guards do not match in auto mode, so shell write channels also rely on the recorded classifier backstop. OpenCode keeps the prompt-based `permission` map as its default and `--auto` stays a deliberate per-session choice, never a default, because it bypasses ask rules including `permission.edit`. The `autoMode` guardrails harden auto sessions and keep `"$defaults"` first in every list they set so the built-in rules survive.
- Do not add Claude Code allow rules for built-in auto-run read-only Bash commands; blanket rules can suppress built-in re-prompts on write-capable flag forms.
- Claude Code writes app-managed state and key ordering into tracked `settings.json`; Codex writes project trust, notices, and MCP additions into tracked `config.toml`. Commit those rewrites as-is instead of reverting them.
- Codex uses the beta `reviewed-writes` permission profile: workspace read-only, only OS temp writable, network disabled, and `approvals_reviewer = "user"`. Persistent writes and network therefore cross the interactive approval boundary; `spar-codex` ignores ambient config and independently supplies a stricter read-only reviewer profile with handoff reads and sensitive-path denies.
- Every scripted `codex exec` uses `</dev/null`, never uses concurrency-unsafe `--last`, and selects the same strict reviewer profile for new and resumed calls. Codex skills live under `~/.agents/skills`, never the app-managed `~/.codex/skills` tree.
- Codex, OpenCode, and `spar-codex` pin GPT-5.6 Sol Fast while retaining xhigh reasoning. Codex uses the base `gpt-5.6-sol` slug plus the Fast service tier because ChatGPT auth rejects a `gpt-5.6-sol-fast` slug, and its subagent defaults pin Sol/xhigh while inheriting the parent tier. OpenCode uses its catalog's `openai/gpt-5.6-sol-fast` alias; primary agents use the global default and subagents inherit it from the invoking primary. The managed configuration assumes ChatGPT subscription auth, where Fast consumes GPT-5.6 credits at 2.5 times Standard; API-key use is separately billed and requires a separate configuration decision.
- Claude Code pins `workflowSizeGuideline: unrestricted` deliberately; the app default is more restrictive.
- Read `README.md` before structural changes; when the installed OpenCode binary and its docs disagree, prefer `/help` output and runtime behavior.
- Auth, session state, machine-local files, and generated host-specific files stay out of Git; keep the tracked nested payload ignore files aligned with the documented exclusions.
- Spar handoffs use one private mode-700 `/tmp/spar-<session-id>/` directory per session; both pinned read-only reviewers can read that exact directory under their existing sandboxes. The selected reviewer bridge creates the directory, revalidates ownership, mode, containment, symlinks, and link counts before every review call, and validates it again before cleanup.
- Every spar bridge call passes its prompt and complete handoff through the pinned `spar-payload-scan` before authentication or network access. The scanner rejects sensitive paths and common credential shapes; policy text that only names protected paths remains reviewable, and unrecognized secret formats remain a residual prose-gate risk.
- Both reviewer bridges require one valid terminal success event with a nonempty reply and own the reviewer process group. Stall and ceiling exits terminate TERM-ignoring descendants before the bridge returns.
- Global permissions are the trusted-repository default, not a boundary against project settings or plugins. Use the README's project-disabled launch commands for untrusted checkouts; verification proves those launches retain the global OpenCode write-review plugin.
- Claude Code skill `allowed-tools` frontmatter pre-approves named tools for the invoking turn rather than restricting the skill; OpenCode keeps command prompts, and verification permits that tool-specific difference.
- OpenCode applies one file per `apply_patch`: shared guidance sets the policy and `reviewed-writes.ts` rejects grouped or malformed patches before permission.
- OpenCode `bash` permission order is semantic and last-match-wins: catch-all ask first, allows next, write-channel ask guards after allows, and denies last. Verification rejects an allow after the guard block.
- OpenCode plugin dependencies are pinned in the tracked npm manifest and lockfile at the installed OpenCode release; only generated `node_modules/` stays ignored.
- OpenCode in-app updates stay disabled because the external installation wrapper owns version selection; the tracked provider block contains only providers used by a managed model.
- Stow tree-folds directories that do not pre-exist at stow time into directory symlinks pointing at the repo. `make clean` keeps runtime-state parents (`~/.claude`, `~/.claude/skills`, `~/.codex`, `~/.agents`, `~/.agents/skills`, `~/.local`, `~/.local/bin`, and `~/.config`) real before stowing; absent `~/.config/opencode` may fold wholesale, while an existing real root receives managed child links (do not add `--no-folding`).
- Never weaken the sensitive-path deny rules; keep `~/.ssh` reads and `Bash(gh api *)` out of allowlists in both tools (H runs those via `!`).
- H approved the narrower Claude automatic shell allowlist during implementation review; do not restore `Bash(gh search *)`, `Bash(jq *)`, or `Bash(opencode debug *)` without a new decision.
- Sensitive-path Edit denies mirror unambiguous credential material only; `~/.ssh/**` and `./.env.*` stay ask-gated for the explicit-instruction exception, but deterministic `.env.*` read denies make agent editing impractical. Use `example.env` for editable placeholder templates.
- `statusline.sh` design conventions, including its intentional strict-mode omission, live in the script's header comment.
- `statusline.sh` persists hashed state names under one owner-validated mode-700 runtime directory and accepts only owner-only, regular, single-link state files. Unsafe root metadata disables all persistence; an unsafe state file disables only that entry, and neither is followed, repaired, or replaced.
- `/doctor` may delete machine-local accumulated allowlists and rewrite app-managed state; review its findings first, then curate durable read-only rules instead of restoring local allowlists wholesale.

## Post-Change Verification

- Run `make verify` and `make lint` from the repo root after changing the stowed payloads.
- After instruction or config changes, verify them in fresh Claude Code, Codex, and OpenCode sessions when practical.
- The full human checklist lives in `README.md` (Verify and Maintenance).

## Skills

- `/commit` - commit workflow with doc sync, scratch cleanup, staging, and push hint
- `/spar` - cross-model plan sparring: adversarial review rounds to evidence-based convergence, then execution and diff review; the counterpart tool is the read-only reviewer in a pinned headless session
