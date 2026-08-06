# AGENTS.md - dotfiles-ai

This repo stores portable user-level AI assistant configuration for Claude Code and OpenCode, deployed to `$HOME` via GNU Stow: the stowed `claude-code/` and `opencode/` payloads, the shared cross-tool guidance file, and the commit workflow used by both tools. Auth, session state, machine-local files, and generated host-specific config stay out.

## Load Map

- Claude Code loads `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` (stowed from `claude-code/`), then this file through the root `CLAUDE.md` `@AGENTS.md` import.
- OpenCode loads `~/.config/opencode/AGENTS.md` (stowed from `opencode/`) and the shared guidance file through `instructions` in `opencode.json`, then this file.
- Skills load on invocation only. Repo-root docs are not stowed.
- Repo-root `.claude/settings.json` and `opencode.json` are per-tool project allowlists for this repo's verification make targets (`verify`, `lint`).

## Invariants

- Shared cross-tool guidance is canonical in `claude-code/.claude/rules/shared-guidance.md`; extend it for new shared guidance and keep tool-specific mechanism in each tool's wrapper (share policy, separate mechanism).
- When editing sibling dotfiles repos, use identical wording for shared concepts; only repo-specific values (scope, package lists, invariants) differ.
- Keep wrappers thin; detailed rationale goes in `README.md`.
- Read `README.md` before structural changes; consult current official Claude Code and OpenCode docs before changing file layout, naming, or config conventions. When the installed OpenCode binary and its docs disagree, prefer `/help` output and runtime behavior.
- Auth, session state, machine-local files, and generated host-specific files stay out of Git; keep the repo-root `.gitignore` aligned with the documented exclusions.
- OpenCode plugin dependencies are generated into `opencode/.config/opencode/`, kept out of Git by a nested untracked `.gitignore`, and stowed with the payload; the repo working-tree copy is canonical.
- Never weaken the sensitive-path deny rules; keep `~/.ssh` reads and `Bash(gh api *)` out of allowlists in both tools (H runs those via `!`, and only `gh search` is auto-allowed).
- Sensitive-path Edit denies mirror unambiguous credential material only; `~/.ssh/**` and `./.env.*` stay ask-gated so the explicit-instruction exception for outside-cwd edits and placeholder files like `.env.example` remain workable.
- `statusline.sh` design conventions, including its intentional strict-mode omission, live in the script's header comment.

## Post-Change Verification

- Run `make verify` and `make lint` from the repo root after changing the stowed payloads.
- After instruction or config changes, verify them in a fresh Claude Code session and a fresh OpenCode session when practical.
- The full human checklist lives in `README.md` (Verify and Maintenance).

## Known Limitations

- OpenCode shows a multi-file `apply_patch` as one approval dialog; per-file review relies on the one-file-per-patch instruction in `opencode/.config/opencode/AGENTS.md`
- OpenCode bash allow patterns match literal command text, so redirect forms of allowed read-only commands (for example `git diff * > file`) would match the allow; the trailing `* > *`, `* >> *`, and `* | tee *` ask rules re-gate those forms because rules are last-match-wins, which makes rule order in the `bash` permission map semantic: catch-all ask first, allows, then ask guards, denies last (`make verify` asserts no allow entry after the guard block); verify the re-gating in a fresh OpenCode session
- the Claude Code `Bash(* >*)` deny rule matches any command containing ` >`, including inside quoted arguments; reword over-blocked commands or run them via `!`
- ultracode is session-only in current Claude Code: `/effort ultracode` in-session, or `claude --effort ultracode` at launch from v2.1.203
- `disable-model-invocation` in skill frontmatter is Claude Code-only; the OpenCode commit skill has no equivalent gate and stays model-invocable
- `workflowSizeGuideline` is settable in settings files from v2.1.219 and overrides `/config`; the default changed from `unrestricted` to `medium`, so the tracked `settings.json` pins `unrestricted` explicitly
- Claude Code runs a built-in, non-configurable set of read-only Bash commands without prompts (`ls`, `grep`, `find`, `wc`, plain `file`, read-only `git`, and more); allow rules for those commands are redundant, and a blanket allow like `Bash(file *)` would override the built-in re-prompt on write-capable flag forms (`file -m`), so keep them out of the allowlist
- Claude Code writes app-managed state into `settings.json` through the stow symlink (its own key order plus internal keys like `skipWorkflowUsageWarning`); commit those rewrites as-is instead of reverting them

## Deferred Items

- schema-level denies for `sudo` and `git push` in both tools: blocked on whether permission rules also gate `!` bash-mode commands (undocumented); test in a fresh session with temporary deny rules (`! sudo -v`, `! git push --dry-run`), then either land the denies or record that root checks and pushes are terminal-only
- OpenCode `permission.read` sensitive-path parity map: the schema accepts pattern maps but tilde and glob semantics are unverified against the installed binary; test a throwaway deny (for example `~/read-deny-test/**`) in a fresh session first, and only record parity after the deny demonstrably fires
- `headerTimeout` under `provider.ollama.options`: add if local Ollama requests start timing out (OpenCode defaults to a 10s header timeout since 1.15.x)
- watch OpenCode PR anomalyco/opencode#23262 (per-file navigation in multi-file permission prompts); the one-file-per-patch instruction becomes optional once it ships
- Claude Code sandboxing: evaluated 2026-08-07 on the Omarchy host (bwrap and socat present, userns smoke test green), kept deferred. Auto-allow still prompts for `$VAR`, `$(...)`, and `VAR=` forms (anthropics/claude-code#43713), and it runs sandboxed in-repo writes (`sed -i`, `git commit`) without prompts, bypassing per-file review; shared enablement would also activate untested on WSL2 (leaked 0-byte files #26722, freezes #54215). Trial path when wanted: Omarchy-only via `/sandbox` (untracked `settings.local.json`) with `sandbox.credentials` denies for `~/.ssh`, `~/.aws`, `~/.gnupg` and an ask rule on `Bash(dangerouslyDisableSandbox:true)`; promote to tracked settings only after the trial and a WSL2 behavior test
- on the WSL host: verify the OpenCode generated-deps invariant; if real dep files live in `~/.config/opencode`, adopt them into the payload with `mv` plus `make restow` (done on the Omarchy host 2026-07-13) and confirm the nested `.gitignore` lists `package-lock.json`
- in the sibling repos: reword the root-allowlist description to "verification make targets (`verify`, `lint`)" and apply the same instruction-slim pass done here; audited 2026-08-07 with agreed commit plans in `~/Projects/scratch/2026-08-06-dotfiles-sibling-slim-notes.md`, execute in a fresh session per repo

## Skills

- `/commit` - commit workflow with doc sync, scratch cleanup, staging, and push hint
