# AGENTS.md - dotfiles-ai

This repo stores portable user-level AI assistant configuration for Claude Code and OpenCode, deployed to `$HOME` via GNU Stow.

## Scope

This repo carries shared cross-tool guidance and portable tracked config for Claude Code and OpenCode.

It owns:

- stowed `claude-code/` and `opencode/` payloads that mirror files into `$HOME`
- the shared guidance file and commit workflow docs used by both tools
- portable runtime config that should follow the user across machines

It does not own:

- auth and session state
- machine-local files, generated host-specific config, or local project memories

## Environment

- Tools: Claude Code, OpenCode
- Deployment: GNU Stow to `$HOME`
- Context: terminal-first user-level configuration

## Key Files

- `README.md` - structure, setup, and verification
- `Makefile` - stow, verification, and cleanup automation; single source of the package list
- `.claude/settings.json` and `opencode.json` (repo root) - per-tool project allowlists for this repo's verification make targets (`verify`, `lint`)
- `CLAUDE.md` - thin Claude Code wrapper importing `AGENTS.md`
- `claude-code/.claude/rules/shared-guidance.md` - canonical shared cross-tool guidance file
- `claude-code/.claude/settings.json` - Claude Code runtime settings
- `opencode/.config/opencode/opencode.json` - OpenCode runtime config and instruction loading
- `opencode/.config/opencode/commands/commit.md` - OpenCode wrapper for the commit workflow

## Setup Invariants

- `claude-code/` and `opencode/` are the stowed payloads; repo-root docs are not stowed
- shared cross-tool guidance lives in `claude-code/.claude/rules/shared-guidance.md`
- OpenCode should reference shared user-level instruction files with `$HOME`-based paths
- tracked runtime config stays portable; auth, session state, machine-local files, and generated host-specific files stay out of Git
- OpenCode plugin dependencies (`package.json`, `bun.lock`, `package-lock.json`, `node_modules/`) are generated into `opencode/.config/opencode/`, stay out of Git via a nested untracked `.gitignore`, and are stowed into `$HOME`; the repo working-tree copy is canonical
- keep the repo-root `.gitignore` aligned with the documented excluded local state
- keep `~/.ssh` reads and `Bash(gh api *)` out of allowlists; the user runs those via `!` commands, and only `gh search` is auto-allowed

## Known Limitations

- OpenCode shows a multi-file `apply_patch` as one approval dialog; per-file review relies on the one-file-per-patch instruction in `opencode/.config/opencode/AGENTS.md`
- OpenCode bash allow patterns match literal command text, so redirect forms of allowed read-only commands (for example `git diff * > file`) skip the ask default
- the Claude Code `Bash(* >*)` deny rule matches any command containing ` >`, including inside quoted arguments; reword over-blocked commands or run them via `!`
- ultracode is session-only in current Claude Code: `/effort ultracode` in-session, or `claude --effort ultracode` at launch from v2.1.203
- `disable-model-invocation` in skill frontmatter is Claude Code-only; the OpenCode commit skill has no equivalent gate and stays model-invocable
- `workflowSizeGuideline` is `/config`-managed; the settings-file validator rejects it as a `settings.json` field (verified on 2.1.207), and its default `unrestricted` already matches the intended value
- Claude Code writes app-managed state into `settings.json` through the stow symlink (its own key order plus internal keys like `skipWorkflowUsageWarning`); commit those rewrites as-is instead of reverting them

## Deferred Items

- `headerTimeout` under `provider.ollama.options`: add if local Ollama requests start timing out
- watch OpenCode PR sst/opencode#23262 (per-file navigation in multi-file permission prompts); the one-file-per-patch instruction becomes optional once it ships
- evaluate Claude Code sandboxing (`sandbox.enabled`, `autoAllowBashIfSandboxed`) so compound read-only bash runs without prompts; needs bubblewrap and behavior testing first
- on the WSL host: verify the OpenCode generated-deps invariant; if real dep files live in `~/.config/opencode`, adopt them into the payload with `mv` plus `make restow` (done on the Omarchy host 2026-07-13) and confirm the nested `.gitignore` lists `package-lock.json`
- in the sibling repos: reword the root-allowlist description to "verification make targets (`verify`, `lint`)" to match this repo's wording

## Statusline Conventions

- Every segment must earn its place. No burn rate ($/hr); show extra-usage spend only, cumulative. No duration segment.
- No redundant indicators when the tool already surfaces the information natively.
- Consistent `label:value` pattern (e.g., `5h:35%`, `5h:52m`, `7d:24h 0m`).
- Space separators between segments, not special characters.
- When iterating on `statusline.sh`, make only the requested change. Do not bundle formatting, naming, or structural changes unless explicitly asked.
- `statusline.sh` intentionally omits Bash strict mode and uses `[ ]` guards so parse failures degrade to blank segments instead of killing the status line.

## Reference Sources

- Claude Code official docs for overview, settings, memory, skills, and hooks
- OpenCode official docs for rules, config, permissions, agents, skills, and TUI behavior
- installed OpenCode `/help` output and actual runtime behavior when the stable binary and docs disagree

## Skills

- `/commit` - commit workflow with doc sync, scratch cleanup, staging, and push hint

## Workflow

- Read `README.md` before structural changes, doc rewrites, or config-layout changes.
- Consult current official Claude Code and OpenCode docs before changing file layout, naming, or config conventions.
- Keep shared cross-tool guidance canonical in `claude-code/.claude/rules/shared-guidance.md`.
- Extend `shared-guidance.md` for new shared guidance; add a separate rules file only for large or truly tool-specific content.
- Share policy, separate mechanism: share content only when the meaning is the same in both tools; keep tool-specific config, wrappers, schemas, and UI settings separate.
- When editing sibling dotfiles repos, use identical wording for shared concepts. Only repo-specific values (scope, package lists, invariants) should differ.
- Prefer native integration points for each tool: `.claude/rules/` and `@imports` for Claude Code, `AGENTS.md`, `instructions`, `permission`, and `tui.json` for OpenCode.
- Prefer plural OpenCode directory names (`agents/`, `commands/`, `skills/`, `tools/`, `themes/`, `plugins/`); singular names are backward-compatibility fallbacks.
- Keep wrappers thin. If detailed rationale is needed, put it in `README.md`, not here.
- After instruction or config changes, verify them in a fresh Claude Code session and a fresh OpenCode session when practical.

## Maintainer Checklist

1. Review the current Claude Code docs for overview, settings, memory, skills, and hooks.
2. Review the current OpenCode docs for config, rules, permissions, agents, skills, TUI, and sharing.
3. Run `opencode debug config` and confirm the resolved config still matches the tracked intent.
4. Start a fresh session in both tools and verify the shared guidance file is loaded.
5. Verify Claude Code status line behavior still matches `claude-code/.claude/settings.json` and `statusline.sh`.
6. Verify OpenCode diff review remains usable in narrow terminals and that sharing stays disabled unless intentionally changed.
7. Verify `/commit` still performs doc sync and scratch cleanup before staging.
8. Run `make verify` and `make lint` from the repo root after changing the stowed payloads.
