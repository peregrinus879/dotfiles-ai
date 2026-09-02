# AGENTS.md - EyrAgents

EyrAgents is a GNU Stow repository for shared Claude Code, Codex, and OpenCode configuration. Keep changes portable across Omarchy and WSL unless a host-specific scope is explicit.

## Loading and Ownership

- Claude Code loads the stowed `~/.claude/CLAUDE.md` and rules, then this file through the root `CLAUDE.md` import. Codex loads `~/.codex/AGENTS.md`, a tracked symlink to shared guidance, and this file. OpenCode loads shared guidance through its global `instructions` entry and this file.
- `claude-code/.claude/rules/shared-guidance.md` is the canonical cross-tool policy. `claude-code/.claude/skills/*/SKILL.md` are the canonical skills; the Codex and OpenCode skill files are tracked symlinks to them. Order tools as Claude Code, Codex, OpenCode.
- This file owns repository invariants. `README.md` owns public scope, setup, and usage. Script headers own local constraints. `docs/maintenance.md` owns unresolved decisions, deferred work, active limitations, and dated revalidation evidence. Prose describes current behavior; Git history owns provenance.
- Root `.claude/settings.json` and `opencode.json` are inert project placeholders. Root wrappers and documentation are source-only; Stow deploys package contents.

## Security Boundaries

- Authentication, credentials, session state, and generated host state stay out of Git. The tracked Claude settings and the tracked Codex runtime config are the only app-managed rewrite exceptions; preserve and review those rewrites instead of reverting them or copying host state into the portable template.
- Credential-path denies stay aligned across Claude Code, Codex, OpenCode, the reviewer bridges, and the payload scanner: credential stores under `$HOME`, `.env` and `.env.*`, `secrets/`, credential-named files, and `*.key`, `*.pem`, `*.p12`, `*.pfx`. `~/.ssh` and `gh api` remain denied to agents; H handles exceptions in a separate terminal.
- Trusted-repository defaults are not an isolation boundary against hostile project configuration. Use the project-disabled launches in `README.md` for untrusted checkouts.
- Primary web research follows each tool's managed policy. Reviewer web tools and command network remain disabled.

## Tool Configuration

- Claude Code: `permissions.defaultMode: auto` with bypass disabled and built-in guardrails retained, the durable Fable alias at xhigh effort, a narrow automatic allowlist, deterministic denies for pushes, repository-host mutations, privilege escalation, destructive Git operations, and credential reads, and no sandbox in tracked settings. `/doctor` may rewrite `~/.claude.json` and local allowlists; curate durable rules instead of restoring machine state.
- Codex: the root-denied `trusted-workspace` profile with automatic approval review, managed runtime reads, workspace and OS-temp writes, credential denies, and command network disabled. `templates/codex/config.toml` is the portable profile; the tracked runtime config is its recursive superset, and host state stays in top-level tables. Skills live under `~/.agents/skills`. Scripted `codex exec` calls use one finite prompt and never `--last`.
- OpenCode: ordinary workspace edits and shell commands are allowed; native filesystem access outside the app temp root asks; pushes, repository-host mutations, destructive Git operations, privilege escalation, and nested agent launches are denied; sharing is disabled. Permission order is last-match-wins. `reviewed-writes.ts` validates every `apply_patch` target for workspace containment and sensitive names before native permission handling. OpenCode has no classifier or sandbox, so its Bash rules are guardrails, not containment. Automatic external skill discovery stays disabled; generated package state stays host-local beneath a real `~/.config/opencode`.
- The primaries, spawned agents, and reviewers use each vendor's current top model at maximum reasoning effort.

## Reviewer Bridges

- Claude Code reviews with Codex through `spar-codex`. Codex reviews with Claude manually outside its strict profile. OpenCode's configured Claude path is `spar-claude`; active availability is recorded in the maintenance ledger.
- Bridges hard-code read-only, offline, subscription-authenticated reviewer launches from the caller's repository root and relay scanned replies. Handoffs use one private `/var/tmp/spar-<session-id>/` directory that the bridge creates, validates, flushes, scans, and cleans; native handoff writes pass the Claude hook or OpenCode plugin.
- `spar-payload-scan` bounds and scans outbound prompts, handoff files, and replies for credential-shaped values and sensitive diff paths.

## State and Deployment

- `make clean` removes only recognized package links and keeps runtime-state parents real. `make migrate-codex-config` is an explicit transition command that converts the Codex config to host-local state. Keep GNU Stow directory folding enabled.
- `make lint` and `make test` run after every managed change; `make verify` adds deployment checks and live canaries after stowing. Restart OpenCode after changing its config, skills, or plugins. Record only unresolved failures or live revalidation needs in `docs/maintenance.md`.

## Skills

- `commit`: stage, review, and commit one exact atomic change with H's approval.
- `publish`: review the exact commits a push, release, or pull request would expose before presenting it as ready.
- `spar`: value-based cross-model review through a read-only reviewer bridge.
- `omarchy`: required for end-user Linux desktop, Hyprland, Omarchy, terminal, theme, and display configuration.
