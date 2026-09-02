# AGENTS.md - EyrAgents

EyrAgents is a GNU Stow repository for shared Claude Code, Codex, and OpenCode configuration. Keep changes portable across Omarchy and WSL unless a host-specific scope is explicit.

## Loading and Ownership

- Claude Code loads the stowed `~/.claude/CLAUDE.md` and rules, then this file through the root `CLAUDE.md` import. Codex loads `~/.codex/AGENTS.md`, a tracked symlink to shared guidance, and this file. OpenCode loads shared guidance through its global `instructions` entry and this file.
- `claude-code/.claude/rules/shared-guidance.md` is the canonical cross-tool policy. `claude-code/.claude/skills/*/SKILL.md` are the canonical skills; the Codex and OpenCode skill files are tracked symlinks to them. Order tools as Claude Code, Codex, OpenCode.
- This file owns repository invariants. `README.md` owns public scope, setup, and usage. Script headers own local constraints. `docs/maintenance.md` owns unresolved decisions, deferred work, active limitations, and dated revalidation evidence. Prose describes current behavior; Git history owns provenance.
- Root `.claude/settings.json` and `opencode.json` are inert project placeholders. Root wrappers and documentation are source-only; Stow deploys package contents.

## Security Boundaries

- Authentication, credentials, session state, and generated host state stay out of Git. The tracked Claude settings are the only app-managed rewrite exception; preserve and review those rewrites instead of reverting them.
- Credential-path denies stay aligned across Claude Code, Codex, OpenCode, the reviewer bridges, and the payload scanner: credential stores under `$HOME`, `.env` and `.env.*`, `secrets/`, `credentials` and `credentials.*`, and `*.key`, `*.pem`, `*.p12`, `*.pfx`. Names that merely contain those words, such as `credentials-policy.md`, stay readable. `~/.ssh` and `gh api` remain denied to agents; H handles exceptions in a separate terminal.
- Trusted-repository defaults are not an isolation boundary against hostile project configuration. Use the project-disabled launches in `README.md` for untrusted checkouts.
- Primary web research follows each tool's managed policy. Reviewer web tools and command network remain disabled.

## Tool Configuration

- Claude Code runs in auto mode with bypass disabled and no tracked sandbox; deterministic denies cover pushes, repository-host mutations, privilege escalation, destructive Git operations, and credential reads. `/doctor` may rewrite `~/.claude.json` and local allowlists; curate durable rules instead of restoring machine state.
- Codex runs the root-denied `trusted-workspace` profile from `templates/codex/config.toml`, installed host-locally by `make migrate-codex-config`, with automatic approval review and command network disabled. Scripted `codex exec` calls use one finite prompt and never `--last`.
- OpenCode allows ordinary workspace edits and shell commands, asks for native access outside the app temp root, and denies pushes, repository-host mutations, destructive Git operations, privilege escalation, remote shells and transfers, and nested agent launches. Permission order is last-match-wins; read and edit subjects are worktree-relative and external subjects are parent directories, so credential stores under `$HOME` rely on the external-directory globs and the ask default. OpenCode has no classifier or sandbox, so its Bash rules are guardrails, not containment.

## Reviewer Bridges

- Claude Code reviews with Codex through `spar-codex`. Codex reviews with Claude manually outside its strict profile. OpenCode's configured Claude path is `spar-claude`; active availability is recorded in the maintenance ledger.
- Each bridge runs one read-only, offline, subscription-authenticated, single-turn reviewer from the caller's repository root and only when `git config spar.consent` is true there. Flags are hard-coded in the bridge: the reviewer reads the repository except Git internals and credential-shaped paths, has no write, shell, web, MCP, plugin, subagent, or project-instruction surface, and runs under a hard timeout in its own process group.
- `spar-payload-scan` bounds the request and artifact files, rejects credential-shaped values and sensitive diff paths, inlines the artifacts into the prompt, and rescans the reply. Artifacts live in the session scratch directory; no handoff directory, hook, or plugin grant exists.

## State and Deployment

- Stow runs with `--no-folding`, so every managed parent under `$HOME` is a real directory and only leaf files are links; generated host state therefore never reaches a package source. `make clean` removes only dangling links whose text points into this repository's packages. `make migrate-codex-config` makes `~/.codex/config.toml` a host-local owner-only file.
- Empty package directories are not tracked; a directory appears in a package only when it holds a managed file.
- `make lint` and `make test` run after every managed change; `make verify` adds deployment checks after stowing. Restart OpenCode after changing its config or skills. Record only unresolved failures or live revalidation needs in `docs/maintenance.md`.

## Skills

- `commit`: stage, review, and commit one exact atomic change with H's approval.
- `publish`: review the exact commits a push, release, or pull request would expose before presenting it as ready.
- `spar`: value-based cross-model review through a read-only reviewer bridge.
- `omarchy`: required for end-user Linux desktop, Hyprland, Omarchy, terminal, theme, and display configuration.
