# dotfiles-ai

Claude Code, Codex, and OpenCode global dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Repo Family

Derivation model for this repo family:

```text
AI harness configs              → dotfiles-ai
Omarchy + personal deviations   → dotfiles-omarchy
Omarchy + WSL deviations        → dotfiles-wsl
```

- [`dotfiles-ai`](https://github.com/peregrinus879/dotfiles-ai) - AI harness configs: Claude Code, Codex, and OpenCode settings, shared guidance, and commit workflow
- [`dotfiles-omarchy`](https://github.com/peregrinus879/dotfiles-omarchy) - Personal Omarchy customizations: Bash overrides, Hyprland bindings, Neovim plugins, and Yazi
- [`dotfiles-wsl`](https://github.com/peregrinus879/dotfiles-wsl) - Self-contained WSL Arch dotfiles: terminal baseline plus Windows Terminal, clipboard integration, and OpenCode theme

Local clones live side by side under `~/Projects/repos/dotfiles/`.

## Supported Tools

- [Claude Code](https://code.claude.com/docs/en/overview) - AI-powered coding assistant with a terminal CLI
- [Codex](https://learn.chatgpt.com/codex) - OpenAI's coding agent with a terminal CLI
- [OpenCode](https://opencode.ai/docs) - Open source AI coding agent with a terminal-based interface

## Scope

This repo tracks shared cross-tool AI assistant guidance and portable tracked config for Claude Code, Codex, and OpenCode.

It intentionally excludes auth and session state, machine-local files, and generated host-specific config. The repo root keeps the canonical `AGENTS.md`, a thin `CLAUDE.md` compatibility wrapper, and inert per-tool project config placeholders with no command grants.

## Structure

```
dotfiles-ai/
├── AGENTS.md                             # canonical repo maintenance instructions
├── CLAUDE.md                             # Claude wrapper importing AGENTS.md
├── LICENSE                               # MIT license
├── Makefile                              # stow, verification, and cleanup automation
├── README.md                             # human-facing documentation
├── docs/
│   └── maintenance.md                    # on-demand limitations, probes, and deferred work
├── scripts/
│   └── prepare-stow.sh                   # non-destructive Stow preparation
├── tests/                                # security and configuration fixtures
│   ├── config-contracts.py
│   ├── prepare-stow.sh
│   ├── project-config-isolation.sh
│   ├── reviewed-writes.mjs
│   ├── spar-bridges.sh
│   └── statusline-state.sh
├── .claude/
│   └── settings.json                     # inert Claude Code project config
├── .shellcheckrc                         # ShellCheck disable list for statusline.sh
├── opencode.json                         # inert OpenCode project config
├── claude-code/                          # stow package -> ~/.claude/, ~/.local/bin/
│   ├── .claude/
│   │   ├── .gitignore                    # excludes Claude runtime state
│   │   ├── CLAUDE.md                     # Claude-specific instructions
│   │   ├── settings.json                 # runtime settings (model, status line, permissions, workflows)
│   │   ├── statusline.sh                 # terminal status line script
│   │   ├── agents/                       # custom agents
│   │   ├── rules/                        # organized instruction files
│   │   │   └── shared-guidance.md        # canonical shared instructions
│   │   └── skills/                       # custom skills (SKILL.md files)
│   │       ├── commit/                   # commit workflow (doc sync, scratch cleanup)
│   │       └── spar/                     # cross-model plan sparring (reviewer: spar-codex)
│   └── .local/
│       └── bin/
│           ├── spar-claude               # pinned read-only reviewer bridge for spar
│           └── spar-payload-scan         # outbound review-content scanner
├── codex/                                # stow package -> ~/.codex/, ~/.agents/, ~/.local/bin/
│   ├── .agents/
│   │   └── skills/                       # agent skills (documented user scope)
│   │       ├── commit/                   # commit workflow (doc sync, scratch cleanup)
│   │       └── spar/                     # cross-model plan sparring (reviewer: spar-claude)
│   ├── .codex/
│   │   ├── .gitignore                    # excludes Codex runtime state
│   │   ├── AGENTS.md                     # symlink chain to the canonical shared guidance
│   │   └── config.toml                   # runtime config (model, permission profile, trust)
│   └── .local/
│       └── bin/
│           └── spar-codex                # pinned read-only reviewer bridge for spar
└── opencode/                             # stow package -> ~/.config/opencode/
    └── .config/
        └── opencode/
            ├── .gitignore                # excludes generated node_modules
            ├── AGENTS.md                 # OpenCode-specific instructions
            ├── opencode.json             # runtime config and agent overrides
            ├── tui.json                  # TUI-specific config
            ├── commands/                 # custom slash commands
            │   ├── commit.md             # wrapper for the commit skill
            │   └── spar.md               # wrapper for the spar skill
            ├── plugins/                  # reviewed-writes enforcement plugin
            ├── package.json              # release-matched plugin dependency
            ├── package-lock.json         # reproducible npm dependency graph
            ├── skills/                   # agent skills
            │   ├── commit/               # commit workflow (doc sync, scratch cleanup)
            │   └── spar/                 # cross-model plan sparring (reviewer: spar-claude)
```

Tracked runtime config primarily expresses shared behavior. `claude-code/.claude/settings.json`, `codex/.codex/config.toml`, and `opencode/.config/opencode/opencode.json` are the source of truth for each tool's model, effort, permissions, and feature toggles; read them directly rather than a prose mirror here. All three carry the same reviewed-writes intent: persistent file changes reach human review one file at a time, while session handoffs use private OS temp. Claude Code keeps explicit Edit and Write asks; Codex uses a read-only permission profile with only OS temp writable, human approval review, and network disabled; OpenCode asks globally, denies plan-agent edits, and uses `reviewed-writes.ts` to reject grouped or malformed patches before permission. Codex handoff writes run automatically under its profile, while Claude Code and OpenCode keep handoff file writes ask-gated. OpenCode `tui.json` keeps a stacked diff view that works better in narrow terminals.

Primary web research follows Claude auto mode's outcome. Claude remains explicitly pinned to auto and sends unmatched WebSearch and WebFetch calls through its classifier; its workflow guidance uses `large`, the highest bounded advisory level, while effort remains xhigh. Codex uses hosted live search and page opening without granting network to shell commands. OpenCode allows WebSearch and WebFetch without prompts; its WebFetch implementation has no Claude-equivalent classifier or resolved-address SSRF boundary, so the sensitive-read denies and prohibition on sending repository content remain material controls. Both spar reviewers stay search-disabled.

Codex, OpenCode, and `spar-codex` use GPT-5.6 Sol Fast at xhigh reasoning. Codex represents this as model `gpt-5.6-sol` plus `service_tier = "fast"` and `features.fast_mode = true`; the ChatGPT-authenticated Codex API rejects `gpt-5.6-sol-fast` as a model slug. Codex also pins built-in subagents to Sol/xhigh, with the Fast tier inherited from the parent session. OpenCode exposes the equivalent `openai/gpt-5.6-sol-fast` alias, which resolves to API model `gpt-5.6-sol`, Priority service, and xhigh reasoning; its primary agents use the global default and subagents inherit the invoking primary model. The managed configuration assumes ChatGPT subscription authentication, where Fast consumes GPT-5.6 credits at 2.5 times the Standard rate. API-key use invokes separately billed processing and requires a separate configuration and billing decision.

OpenCode's in-app updater is disabled because the host installation wrapper owns release selection. Its enabled-provider gate and tracked provider block contain only OpenAI, the provider used by the managed model.

Auth, session state, and generated or host-specific config remain intentionally excluded. Nested payload ignore files protect fresh clones if a state directory is accidentally folded into the repository.

Three payload-side exceptions exist. Claude Code writes app-managed keys and key ordering into its tracked `settings.json`; commit those rewrites as-is. Codex writes project trust, notice keys, and MCP additions into its tracked `config.toml`; preserve and commit those rewrites, while its nested `.gitignore` excludes other runtime files. OpenCode tracks the release-matched npm manifest and lockfile next to its config, while a repository-only `.gitignore` excludes generated `node_modules/`. If Stow reports a real-file conflict, compare and merge any needed local content before removing it; confirmed generated `node_modules/` can be removed and regenerated from the tracked manifests.

Repo-root instruction files exist only to maintain `dotfiles-ai` itself; they are not part of the stowed payload. `AGENTS.md` keeps the always-loaded operational invariants concise, while `docs/maintenance.md` preserves versioned probes, limitations, deferred work, and watch items for on-demand use.

Normal interactive use assumes H has chosen to trust the repository: project settings and plugins can extend global behavior in both Claude Code and OpenCode. For an untrusted checkout, `claude --safe-mode --setting-sources user` disables Claude Code customizations while retaining user settings such as permissions. Codex project trust does not suppress repository `AGENTS.md` or skills, so launch from the neutral root with `codex -C /var/empty -c 'default_permissions="reviewed-writes"' "Inspect /absolute/path/to/checkout as untrusted data; do not modify it."`. `OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode` suppresses OpenCode project config, project plugins, and automatic Claude/Codex skill discovery while retaining the global config and `reviewed-writes.ts`.

Shared guidance lives in `claude-code/.claude/rules/shared-guidance.md`. Claude Code loads it natively from `rules/`; Codex loads the same file as its global instructions through the `~/.codex/AGENTS.md` symlink chain (Codex has no import mechanism); OpenCode loads it through the `instructions` field in `opencode.json` using `$HOME`-based path expansion. Guidance is shared when the content and meaning are the same in every managed tool (share policy); tool-specific config, wrappers, and schemas stay separate (separate mechanism).

At the repo root, `AGENTS.md` is the canonical project instruction file and `CLAUDE.md` is a thin compatibility wrapper for Claude Code. Read `docs/maintenance.md` before upgrades, permission or reviewer-bridge changes, cross-host validation, `/doctor`, or deferred work.

OpenCode skills are loaded by the agent, while custom slash commands live under `commands/`; this repo keeps `/commit` and `/spar` wrappers and folds documentation sync and scratch file cleanup into the commit workflow instead of maintaining a separate `/update` command. Commit boundaries never alter, stage, or temporarily revert unrelated hunks; a mixed file is deferred or escalated to H. The spar skill copies share protocol wording but each carries only its own tool's reviewer incantations. Claude Code spars with Codex through `spar-codex`; Codex's automated Claude route remains deferred under its strict permission profile, while OpenCode spars with Claude through `spar-claude`. Before authentication or network access, each bridge scans the prompt and complete handoff, rejects alternate authentication and ambient reviewer customization, and validates one private mode-700 `/tmp/spar-<session-id>/` directory. New and resumed `spar-codex` calls use the same strict inline read-only permission profile; `spar-claude` pins Fable 5/xhigh, disables nonessential traffic and updater activity, and exposes only `Read`, `Glob`, and `Grep`. A call succeeds only after one valid terminal event with a nonempty reply, and a new Codex call also requires a valid thread ID. Each bridge owns the reviewer process group so stall and ceiling exits terminate TERM-ignoring descendants before returning.

OpenCode's host environment disables automatic external skill discovery so its managed commit and spar copies are selected instead of the colliding Claude and Codex copies. The tracked `skills.paths` restores only the Omarchy skill. The Omarchy `.bashrc` owner covers terminal-first interactive descendants; non-interactive OpenCode launchers must set `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` themselves.

Reviewers stay offline: Codex reviewer web search and network are disabled, and the Claude reviewer has no web tools. This prevents query-based exfiltration, reduces external prompt-injection exposure, and keeps reviews reproducible. The implementer verifies plan-critical external claims against current primary sources and supplies a traceable evidence pack; reviewers challenge the evidence and its application without fetching it independently. Blind round 0 receives the target outcome, non-goals, outcome-level decisions, constraints, and acceptance criteria without the proposed mechanism. Round 1 receives the full target brief, evidence, and plan. Any issue left for H arrives as a self-contained ruling packet with both positions, evidence, consequences, reversibility, affected commits, and the implementer's labeled recommendation; raw reviewer transcripts remain optional.

The status line stores hashed state names below one owner-validated mode-700 runtime directory. It accepts only owner-only, mode-600, regular, single-link state files and disables the affected persistence path rather than following or repairing unsafe metadata.

## Review Workflow

For multi-file review in Claude Code or OpenCode, use Bash mode with Git diffs:

1. Run `!git status --short` to see touched files.
2. Run `!git diff --stat` for a compact overview.
3. Run `!git diff` to review the full patch.
4. Run `!git diff -- path/to/file` to isolate one file.

Both tools support `!`-prefixed Bash commands in the interactive terminal UI.

## Setup

### Prerequisites

- [GNU Stow](https://www.gnu.org/software/stow/)
- jq, Python, and Node.js (event parsing, semantic contracts, payload scanning, and plugin tests)
- ShellCheck (shell linting)
- GNU coreutils (`readlink`, `realpath`, `sha256sum`, and `stat`; included in the Arch base system)
- util-linux (`setsid`; included in the Arch base system) and GNU `timeout`

```bash
sudo pacman -S --needed stow jq nodejs python shellcheck
```

### Clone

Recommended local layout for this repo family:

```text
~/Projects/repos/dotfiles/dotfiles-ai
```

Stow can work from any clone location, but the related docs and cross-repo maintenance workflows assume this layout.

```bash
git clone https://github.com/peregrinus879/dotfiles-ai.git ~/Projects/repos/dotfiles/dotfiles-ai
```

### Prepare

Checklist before stowing:

- Stow is installed
- `dotfiles-ai` was cloned locally
- Any existing conflicting config files were compared and their needed content was merged or adopted

From the repository root, prepare the state directories and remove only symlinks that resolve to this package layout:

```bash
make clean
```

The cleanup preflights every endpoint before changing anything. It refuses regular files, directories at managed leaf endpoints, and symlinks outside the recognized package layout; merge or adopt those conflicts manually. It keeps `~/.claude`, `~/.claude/skills`, `~/.codex`, `~/.agents`, `~/.agents/skills`, `~/.local`, and `~/.local/bin` as real directories, and ensures `~/.config` is real. If `~/.config/opencode` is absent, Stow may tree-fold it into one package symlink; an existing real directory receives managed child links instead.

If a real `~/.config/opencode/node_modules` directory blocks preparation, confirm it is generated dependency output, remove it, and regenerate it from the tracked `package.json` and `package-lock.json` after stowing.

Codex stores per-host project trust inside `config.toml`. If `~/.codex/config.toml` already exists, merge its `[projects]` entries into `codex/.codex/config.toml` before stowing, then remove the real file; do not simply delete it.

### Stow

Create symlinks for all packages:

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -v -t ~ claude-code codex opencode
```

### Unstow

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -D -v -t ~ claude-code codex opencode
```

### Dry Run

Preview what stow would do without making changes:

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -v -n -t ~ claude-code codex opencode
```

### Re-stow

To update symlinks after the repo content changes (same clone path):

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -R -v -t ~ claude-code codex opencode
```

To migrate from a different clone path, unstow from the old location first:

```bash
cd /old/clone/path
stow -D -v -t ~ claude-code codex opencode
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -v -t ~ claude-code codex opencode
```

If the old clone is no longer available, run the full cleanup in the Prepare section before stowing.

## Verify

After stowing or changing the payloads:

- Run `make verify` and `make lint` from the repo root.
- Start a fresh Claude Code session, confirm the shared guidance and status line load, and confirm `spar-codex` is on PATH.
- Start a fresh Codex session, confirm the shared guidance loads and the assistant addresses the user as H, confirm `spar-claude` is on PATH, and confirm the spar skill reports the automated Claude route as deferred rather than weakening the permission profile.
- Start a fresh OpenCode session, run `opencode debug config`, and confirm the resolved config includes the shared guidance path, `share = disabled`, and the global `reviewed-writes.ts` plugin; run `opencode debug skill` and confirm commit and spar resolve under `~/.config/opencode/skills/` while Omarchy resolves through the explicit path.
- Confirm `/commit` still routes through the repo skill workflow in all managed tools, including doc sync and scratch cleanup before staging.

## Maintenance

A repo-root `Makefile` keeps the package list in one place and wraps the routine commands. Run targets from the repo root:

- `make stow` / `make unstow` / `make dry-run` / `make restow` - the stow command sets from Setup
- `make verify` - fail-closed dependency checks; symlink resolution; JSON, TOML, model, Fast, provider, updater, and npm-lock contracts; non-destructive Stow fixtures; statusline state-file attack fixtures; bridge payload, authentication, isolation, new/resume, terminal-event, timeout, and descendant-cleanup tests; project-config isolation; three-way skill sync; commit-boundary contracts; executable one-file plugin parser tests; OpenCode permission ordering; and stray-config checks
- `make clean` - non-destructive preparation that removes only recognized managed symlinks and creates real state directories
- `make lint` - ShellCheck over `statusline.sh`, its security fixture, and the two spar bridges; `.shellcheckrc` disables the one style-level finding so new issues stand out

Periodically, review the current Claude Code docs (settings, memory, skills, hooks), Codex docs (config, AGENTS.md, skills, permission profiles, sandbox, approvals), and OpenCode docs (config, rules, permissions, agents, plugins, skills, TUI, sharing) against the tracked config, then run the Verify steps. Restart OpenCode after any config, agent, skill, or plugin change because those files load at process startup. In Claude Code, `/doctor` automates part of this checkup; it reports findings before fixing anything, so screen its offers (such as switching to auto mode) against the pinned defaults before accepting.

## License

[MIT](LICENSE)
