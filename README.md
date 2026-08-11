# dotfiles-ai

Claude Code and OpenCode global dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Repo Family

Derivation model for this repo family:

```text
AI harness configs              → dotfiles-ai
Omarchy + personal deviations   → dotfiles-omarchy
Omarchy + WSL deviations        → dotfiles-wsl
```

- [`dotfiles-ai`](https://github.com/peregrinus879/dotfiles-ai) - AI harness configs: Claude Code and OpenCode settings, shared guidance, and commit workflow
- [`dotfiles-omarchy`](https://github.com/peregrinus879/dotfiles-omarchy) - Personal Omarchy customizations: Bash overrides, Hyprland bindings, Neovim plugins, and Yazi
- [`dotfiles-wsl`](https://github.com/peregrinus879/dotfiles-wsl) - Self-contained WSL Arch dotfiles: terminal baseline plus Windows Terminal, clipboard integration, and OpenCode theme

Local clones live side by side under `~/Projects/repos/dotfiles/`.

## Supported Tools

- [Claude Code](https://code.claude.com/docs/en/overview) - AI-powered coding assistant with a terminal CLI
- [OpenCode](https://opencode.ai/docs) - Open source AI coding agent with a terminal-based interface

## Scope

This repo tracks shared cross-tool AI assistant guidance and portable tracked config for Claude Code and OpenCode.

It intentionally excludes auth and session state, machine-local files, and generated host-specific config. The repo root keeps a minimal `AGENTS.md`, a thin `CLAUDE.md` compatibility wrapper, and per-tool project allowlists for the repo's verification make targets, so the repo can be maintained natively in both tools.

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
├── .gitignore                            # documented machine-local exclusions
├── .shellcheckrc                         # ShellCheck disable list for statusline.sh
├── opencode.json                         # OpenCode project allowlist for the same targets
├── claude-code/                          # stow package -> ~/.claude/
│   └── .claude/
│       ├── CLAUDE.md                     # Claude-specific instructions
│       ├── settings.json                 # runtime settings (model, status line, permissions, workflows)
│       ├── statusline.sh                 # terminal status line script
│       ├── agents/                       # custom agents
│       ├── rules/                        # organized instruction files
│       │   └── shared-guidance.md        # canonical shared instructions
│       └── skills/                       # custom skills (SKILL.md files)
│           ├── commit/                   # commit workflow (doc sync, scratch cleanup)
│           └── spar/                     # cross-model plan sparring (reviewer: opencode run)
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
            ├── plugins/                  # plugins
            ├── skills/                   # agent skills
            │   ├── commit/               # commit workflow (doc sync, scratch cleanup)
            │   └── spar/                 # cross-model plan sparring (reviewer: claude -p)
            ├── themes/                   # custom themes
            └── tools/                    # custom tool definitions
```

Tracked runtime config is limited to shared behavior. `claude-code/.claude/settings.json` and `opencode/.config/opencode/opencode.json` are the source of truth for each tool's model, effort, permissions, and feature toggles; read them directly rather than a prose mirror here. Both carry the same intent: ask before file edits and non-read-only bash, allow a narrow set of read-only inspections, keep sharing off. The OpenCode permission policy applies to every agent, including task-spawned subagents. OpenCode `tui.json` keeps a stacked diff view that works better in narrow terminals.

Machine-local paths (`projects/`, `agent-memory/`), auth/session state, and generated or host-specific config files remain intentionally excluded. The repo root `.gitignore` tracks the documented machine-local paths so accidental local state stays out of Git.

One exception lives inside the `opencode/` package: OpenCode generates its plugin dependencies next to its config. The package directory holds the canonical copy, kept out of Git by a nested untracked `.gitignore`, and stow links them into `~/.config/opencode` with the rest of the payload. If stow reports conflicts on these files, remove the real copies under `$HOME` and re-stow; never delete the repo-side copies.

Repo-root instruction files exist only to maintain `dotfiles-ai` itself; they are not part of the stowed payload.

Shared guidance lives in `claude-code/.claude/rules/shared-guidance.md`. Claude Code loads it natively from `rules/`, while OpenCode loads the same file through the `instructions` field in `opencode.json` using `$HOME`-based path expansion. Guidance is shared when the content and meaning are the same in both tools (share policy); tool-specific config, wrappers, and schemas stay separate (separate mechanism).

At the repo root, `AGENTS.md` is the canonical project instruction file and `CLAUDE.md` is a thin compatibility wrapper for Claude Code.

OpenCode skills are loaded by the agent, while custom slash commands live under `commands/`; this repo keeps `/commit` and `/spar` wrappers and folds documentation sync and scratch file cleanup into the commit workflow instead of maintaining a separate `/update` command. The spar skill's copies share their protocol wording but each carries only its own tool's reviewer incantations, so a session can never invoke its own model as the reviewer.

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

```bash
sudo pacman -S --needed stow
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

Remove existing files that would conflict with stow. The first block removes tree-folded directory symlinks left by a previous stow (harmless on a fresh machine). The second block removes the one file Claude Code auto-creates that would conflict on a fresh install:

```bash
# Tree-folded directory symlinks (from a previous stow)
rm -f ~/.claude/agents ~/.claude/rules ~/.claude/skills
rm -f ~/.config/opencode ~/.config/opencode/agents ~/.config/opencode/commands \
  ~/.config/opencode/modes ~/.config/opencode/plugins ~/.config/opencode/skills \
  ~/.config/opencode/themes ~/.config/opencode/tools

# Individual config files
rm -f ~/.claude/settings.json
```

### Stow

Create symlinks for all packages:

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -v -t ~ claude-code opencode
```

### Unstow

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -D -v -t ~ claude-code opencode
```

### Dry Run

Preview what stow would do without making changes:

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -v -n -t ~ claude-code opencode
```

### Re-stow

To update symlinks after the repo content changes (same clone path):

```bash
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -R -v -t ~ claude-code opencode
```

To migrate from a different clone path, unstow from the old location first:

```bash
cd /old/clone/path
stow -D -v -t ~ claude-code opencode
cd ~/Projects/repos/dotfiles/dotfiles-ai
stow -v -t ~ claude-code opencode
```

If the old clone is no longer available, run the full cleanup in the Prepare section before stowing.

## Verify

After stowing or changing the payloads:

- Run `make verify` and `make lint` from the repo root.
- Start a fresh Claude Code session and confirm the shared guidance file and status line load as expected.
- Run `opencode debug config` and confirm the resolved config includes the shared guidance path and `share = disabled`.
- Confirm `/commit` still routes through the repo skill workflow in both tools, including doc sync and scratch cleanup before staging.

## Maintenance

A repo-root `Makefile` keeps the package list in one place and wraps the routine commands. Run targets from the repo root:

- `make stow` / `make unstow` / `make dry-run` / `make restow` - the stow command sets from Setup
- `make verify` - symlink resolution (via `readlink -f`, so tree-folding does not false-negative) plus JSON validity, statusline syntax, commit-skill sync, OpenCode permission-rule order, and stray `opencode.jsonc` checks
- `make clean` - the Prepare cleanup steps
- `make lint` - ShellCheck over `statusline.sh`; `.shellcheckrc` disables the one style-level finding so new issues stand out

Periodically, review the current Claude Code docs (settings, memory, skills, hooks) and OpenCode docs (config, rules, permissions, agents, skills, TUI, sharing) against the tracked config, then run the Verify steps. In Claude Code, `/doctor` automates part of this checkup; it reports findings before fixing anything, so screen its offers (such as switching to auto mode) against the pinned defaults before accepting.

## License

[MIT](LICENSE)
