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
- [Codex](https://learn.chatgpt.com/docs/codex) - OpenAI's coding agent with a terminal CLI
- [OpenCode](https://opencode.ai/docs) - Open source AI coding agent with a terminal-based interface

## Scope

This repo tracks shared cross-tool AI assistant guidance and portable tracked config for Claude Code, Codex, and OpenCode.

It intentionally excludes auth and session state, machine-local files, and generated host-specific config. The repo root keeps a minimal `AGENTS.md`, a thin `CLAUDE.md` compatibility wrapper, and per-tool project allowlists for the repo's verification make targets, so the repo can be maintained natively in the managed tools.

## Structure

```
dotfiles-ai/
├── AGENTS.md                             # canonical repo maintenance instructions
├── CLAUDE.md                             # Claude wrapper importing AGENTS.md
├── LICENSE                               # MIT license
├── Makefile                              # stow, verification, and cleanup automation
├── README.md                             # human-facing documentation
├── .claude/
│   └── settings.json                     # Claude Code project allowlist for read-only make targets
├── .shellcheckrc                         # ShellCheck disable list for statusline.sh
├── opencode.json                         # OpenCode project allowlist for the same targets
├── claude-code/                          # stow package -> ~/.claude/, ~/.local/bin/
│   ├── .claude/
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
│           └── spar-claude               # pinned read-only reviewer bridge for spar
├── codex/                                # stow package -> ~/.codex/, ~/.agents/, ~/.local/bin/
│   ├── .agents/
│   │   └── skills/                       # agent skills (documented user scope)
│   │       ├── commit/                   # commit workflow (doc sync, scratch cleanup)
│   │       └── spar/                     # cross-model plan sparring (reviewer: spar-claude)
│   ├── .codex/
│   │   ├── AGENTS.md                     # symlink chain to the canonical shared guidance
│   │   └── config.toml                   # runtime config (model, sandbox, approvals, trust)
│   └── .local/
│       └── bin/
│           └── spar-codex       # pinned read-only reviewer bridge for spar
└── opencode/                             # stow package -> ~/.config/opencode/
    └── .config/
        └── opencode/
            ├── AGENTS.md                 # OpenCode-specific instructions
            ├── opencode.json             # runtime config and agent overrides
            ├── tui.json                  # TUI-specific config
            ├── agents/                   # custom agent definitions
            ├── commands/                 # custom slash commands
            │   ├── commit.md             # wrapper for the commit skill
            │   └── spar.md               # wrapper for the spar skill
            ├── plugins/                  # reviewed-writes enforcement plugin
            ├── skills/                   # agent skills
            │   ├── commit/               # commit workflow (doc sync, scratch cleanup)
            │   └── spar/                 # cross-model plan sparring (reviewer: spar-claude)
            ├── themes/                   # custom themes
            └── tools/                    # custom tool definitions
```

Tracked runtime config is limited to shared behavior. `claude-code/.claude/settings.json`, `codex/.codex/config.toml`, and `opencode/.config/opencode/opencode.json` are the source of truth for each tool's model, effort, permissions, and feature toggles; read them directly rather than a prose mirror here. All three carry the same reviewed-writes intent: persistent file changes reach human review one file at a time, while session handoffs use private OS temp. Claude Code keeps explicit Edit and Write asks; Codex uses a read-only permission profile with only OS temp writable, human approval review, and network disabled; OpenCode asks globally, denies plan-agent edits, and uses `reviewed-writes.ts` to reject grouped or malformed patches before permission. Codex handoff writes run automatically under its profile, while Claude Code and OpenCode keep handoff file writes ask-gated. OpenCode `tui.json` keeps a stacked diff view that works better in narrow terminals.

Auth, session state, and generated or host-specific config remain intentionally excluded. Nested payload ignore files protect fresh clones if a state directory is accidentally folded into the repository.

Two payload-side exceptions exist. Inside `codex/`, Codex writes runtime state into `config.toml` itself (project trust entries, notice keys, MCP additions); those rewrites flow through the stow symlink into the repo working tree and are committed as-is, while a tracked nested `.gitignore` keeps every other runtime file Codex drops next to the stowed links out of Git (tracked deliberately, unlike OpenCode's generated one, so fresh clones reproduce the defense). Inside `opencode/`, OpenCode generates its plugin dependencies next to its config; the package directory holds the canonical copy, kept out of Git by a nested untracked `.gitignore`, and stow links them into `~/.config/opencode` with the rest of the payload. If stow reports conflicts on these files, remove the real copies under `$HOME` and re-stow; never delete the repo-side copies.

Repo-root instruction files exist only to maintain `dotfiles-ai` itself; they are not part of the stowed payload.

Normal interactive use assumes H has chosen to trust the repository: project settings and plugins can extend global behavior in both Claude Code and OpenCode. For an untrusted checkout, start Claude Code with `claude --safe-mode --setting-sources user` or OpenCode with `OPENCODE_DISABLE_PROJECT_CONFIG=1 opencode`; these preserve the global controls while suppressing project configuration and plugins.

Shared guidance lives in `claude-code/.claude/rules/shared-guidance.md`. Claude Code loads it natively from `rules/`; Codex loads the same file as its global instructions through the `~/.codex/AGENTS.md` symlink chain (Codex has no import mechanism); OpenCode loads it through the `instructions` field in `opencode.json` using `$HOME`-based path expansion. Guidance is shared when the content and meaning are the same in every managed tool (share policy); tool-specific config, wrappers, and schemas stay separate (separate mechanism).

At the repo root, `AGENTS.md` is the canonical project instruction file and `CLAUDE.md` is a thin compatibility wrapper for Claude Code.

OpenCode skills are loaded by the agent, while custom slash commands live under `commands/`; this repo keeps `/commit` and `/spar` wrappers and folds documentation sync and scratch file cleanup into the commit workflow instead of maintaining a separate `/update` command. The spar skill's copies share their protocol wording but each carries only its own tool's reviewer incantations, so a session can never invoke its own model as the reviewer. The reviewer matrix is cross-vendor: Claude Code spars with Codex through the pinned `spar-codex` bridge, and Codex and OpenCode spar with Claude through the pinned `spar-claude` bridge. Codex replaced OpenCode as the Claude-side reviewer for its OS-enforced read-only sandbox, clean session resume, and fail-fast limit reporting. Each bridge creates one mode-700 `/tmp/spar-<session-id>/` handoff, revalidates the directory and its direct files before every review call, and validates it again before cleanup. The reviewers can read that handoff under their pinned read-only controls without gaining write access.

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
- jq and Python (verification and reviewer-event parsing)
- ShellCheck (shell linting)
- GNU coreutils (`readlink`, `realpath`, and `stat`; included in the Arch base system)

```bash
sudo pacman -S --needed stow jq python shellcheck
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
- Any existing conflicting config files were removed

Prepare the state directories and remove only symlinks that resolve to this package layout:

```bash
make clean
```

The cleanup preflights every endpoint before changing anything. It refuses regular files, directories at managed leaf endpoints, and symlinks outside the recognized package layout; merge or adopt those conflicts manually. It keeps `~/.claude`, `~/.codex`, `~/.agents/skills`, and `~/.local/bin` as real directories so runtime state cannot land in the repository. OpenCode's config payload may still use Stow's normal per-entry folding convention.

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
- Start a fresh Claude Code session and confirm the shared guidance file and status line load as expected.
- Start a fresh Codex session and confirm the shared guidance loads (the assistant addresses the user as H) and `spar-codex` is on PATH.
- Run `opencode debug config` and confirm the resolved config includes the shared guidance path and `share = disabled`.
- Confirm `/commit` still routes through the repo skill workflow in all managed tools, including doc sync and scratch cleanup before staging.

## Maintenance

A repo-root `Makefile` keeps the package list in one place and wraps the routine commands. Run targets from the repo root:

- `make stow` / `make unstow` / `make dry-run` / `make restow` - the stow command sets from Setup
- `make verify` - symlink resolution (via `readlink -f`, so tree-folding does not false-negative) plus JSON and TOML validity, statusline syntax, reviewer-bridge executable, handoff-validation, and tool-whitelist checks, three-way skill sync, reviewed-writes profiles and agent maps, one-file plugin markers, OpenCode permission-rule order, and stray `opencode.jsonc` checks
- `make clean` - non-destructive preparation that removes only recognized managed symlinks and creates real state directories
- `make lint` - ShellCheck over `statusline.sh` and the two spar bridges; `.shellcheckrc` disables the one style-level finding so new issues stand out

Periodically, review the current Claude Code docs (settings, memory, skills, hooks), Codex docs (config, AGENTS.md, skills, permission profiles, sandbox, approvals), and OpenCode docs (config, rules, permissions, agents, plugins, skills, TUI, sharing) against the tracked config, then run the Verify steps. Restart OpenCode after any config, agent, skill, or plugin change because those files load at process startup. In Claude Code, `/doctor` automates part of this checkup; it reports findings before fixing anything, so screen its offers (such as switching to auto mode) against the pinned defaults before accepting.

## License

[MIT](LICENSE)
