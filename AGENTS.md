# AGENTS.md - EyrAgents

EyrAgents is a GNU Stow repository for shared Claude Code, Codex, and OpenCode configuration. Keep changes portable across Omarchy and WSL unless a host-specific scope is explicit.

## Loading and Ownership

- Claude Code loads the stowed rules, then this file through the root `CLAUDE.md` import. Codex loads `~/.codex/AGENTS.md`, a tracked symlink to shared guidance, and this file. OpenCode loads shared guidance through its global `instructions` entry and this file.
- `claude-code/.claude/rules/shared-guidance.md` is the canonical cross-tool policy. `claude-code/.claude/skills/*/SKILL.md` are the canonical skills; the Codex and OpenCode skill files are tracked symlinks to them. Order tools as Claude Code, Codex, OpenCode.
- This file owns repository invariants. `README.md` owns public scope, setup, and usage. Script headers own local constraints. `docs/maintenance.md` owns unresolved decisions, deferred work, active limitations, and dated revalidation evidence. Prose describes current behavior; Git history owns provenance.
- Root wrappers and documentation are source-only; Stow deploys package contents. Because the packages are live configuration on a stowed host, an edit to a settings file, skill, or bridge here is active for the next session of that tool before any commit; work on this repository only in a session H is watching.

## Security Boundaries

- Authentication, credentials, session state, and generated host state stay out of Git. The tracked Claude settings are the only app-managed rewrite exception; preserve and review those rewrites instead of reverting them.
- Credential stores are neither readable nor writable by agents, and the list stays aligned across Claude Code, Codex, OpenCode, the reviewer bridges, and the payload scanner: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, provider auth files, the GNOME keyring, browser profiles, shell history, `.env` and `.env.*`, `.netrc`, `.npmrc`, `.pypirc`, `secrets/`, `credentials` and `credentials.*`, `auth.json`, OpenSSH `id_*` keys, and `*.key`, `*.pem`, `*.p12`, `*.pfx`. The Codex agent has no read grant on `~/.codex/config.toml`, whose host tables may carry MCP credentials. Names that merely contain those words, such as `credentials-policy.md`, stay readable. `tests/config-contracts.py` enforces the alignment and the read-write mirror.
- Git internals change only through Git: file tools cannot write `.git/**` in any tool, Codex keeps `.git/config` and `.git/hooks` read-only, and Git configuration, remote, hook, and alias changes need H's explicit instruction, because they run code on H's next Git command and never appear in a diff.
- Trusted-repository defaults are not an isolation boundary against hostile project configuration. Use the project-disabled launches in `README.md` for untrusted checkouts.
- Primary web research follows each tool's managed policy: Claude Code and OpenCode keep web fetch and search, and Codex keeps live web search plus its desktop-app apps, browser, hooks, and plugins. These are egress and authority surfaces for a prompt-injected session, kept by H's choice. Reviewer web tools and command network remain disabled.

## Tool Configuration

- Claude Code runs in auto mode with bypass disabled and no tracked sandbox; deterministic denies cover pushes, `git clean`, repository-host mutations, privilege escalation, and credential reads and writes, while destructive Git operations, Git configuration changes, `gh` mutations, and persistence surfaces clear through the classifier only on H's explicit instruction. `/doctor` may rewrite `~/.claude.json` and local allowlists; curate durable rules instead of restoring machine state.
- Codex runs the root-denied `trusted-workspace` profile from `templates/codex/config.toml`, installed host-locally by `make stow`, with automatic approval review and command network disabled. The profile grants the mise install directory so the sandbox can execute mise-managed runtimes. Scripted `codex exec` calls use one finite prompt and never `--last`.
- OpenCode allows ordinary workspace edits and shell commands, asks for native access outside the app temp root and before destructive Git operations and Git configuration changes, and denies pushes, `git clean`, repository-host mutations, privilege escalation, remote shells and transfers, and nested agent launches. Permission order is last-match-wins; read and edit subjects are worktree-relative and external subjects are parent directories, so credential stores under `$HOME` rely on the external-directory globs and the ask default. OpenCode has no classifier or sandbox, so its Bash rules are guardrails, not containment.

## Reviewer Bridges

- Claude Code reviews with Codex through `spar-codex`. Codex reviews with Claude manually outside its strict profile. OpenCode's configured Claude path is `spar-claude`; active availability is recorded in the maintenance ledger.
- Each bridge runs one read-only, offline, subscription-authenticated, single-turn reviewer from the caller's repository root, and refuses where `git config spar.consent` is set to anything but true. Flags are hard-coded in the bridge: the reviewer reads the repository except Git internals and credential-shaped paths, has no write, web, MCP, plugin, subagent, or project-instruction surface, starts from a scrubbed environment, and runs under a hard timeout in its own process group. The Codex reviewer works through a read-only, network-off sandboxed shell and receives its charter as prompt text; the Claude reviewer has only Read, Glob, and Grep.
- `spar-payload-scan` bounds the request and artifact files, rejects credential-shaped values and sensitive diff paths, inlines the artifacts into the prompt, and rescans the reply; its `diff` mode gives the `commit` and `publish` skills a deterministic check over staged and outbound diffs. Artifacts must live under the repository or the temp root, and the reviewer runtime may not resolve inside the repository; no handoff directory, hook, or plugin grant exists.

## State and Deployment

- Stow runs with `--no-folding`, so every managed parent under `$HOME` is a real directory and only leaf files are links; generated host state therefore never reaches a package source. `make clean` removes only dangling links whose text points into this repository's packages. `make stow` and `make restow` reconcile `~/.codex/config.toml`: the template owns root keys and its tables, host-only tables are preserved verbatim, and `make verify` attests that the host file carries the template's boundaries.
- Empty package directories are not tracked; a directory appears in a package only when it holds a managed file.
- `make lint` and `make test` run after every managed change and in CI on every push; `make verify` adds deployment checks after stowing. Restart OpenCode after changing its config or skills. Record only unresolved failures or live revalidation needs in `docs/maintenance.md`.

## Skills

- `commit`: stage, review, and commit one exact atomic change with H's approval.
- `publish`: review the exact commits a push, release, or pull request would expose before presenting it as ready.
- `spar`: value-based cross-model review through a read-only reviewer bridge.
- `omarchy`: required for end-user Linux desktop, Hyprland, Omarchy, terminal, theme, and display configuration. Omarchy installs it and `diagnose-crash` as links under `~/.claude/skills` and `~/.agents/skills`; they resolve outside the packages, and `make clean` never touches them.
