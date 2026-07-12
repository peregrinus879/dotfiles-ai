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
│           └── commit/                   # commit workflow (doc sync, scratch cleanup)
└── opencode/                             # stow package -> ~/.config/opencode/
    └── .config/
        └── opencode/
            ├── AGENTS.md                 # OpenCode-specific instructions
            ├── opencode.json             # runtime config and agent overrides
            ├── tui.json                  # TUI-specific config
            ├── agents/                   # custom agent definitions
            ├── commands/                 # custom slash commands
            │   └── commit.md             # wrapper for the commit skill
            ├── plugins/                  # plugins
            ├── skills/                   # agent skills
            │   └── commit/               # commit workflow (doc sync, scratch cleanup)
            ├── themes/                   # custom themes
            └── tools/                    # custom tool definitions
```

Tracked runtime config is limited to shared behavior. Claude Code `settings.json` pins the default model `claude-fable-5` with `xhigh` effort, keeps workflows on (ultracode is session-only: `/effort ultracode`, or launch with `claude --effort ultracode` from v2.1.203), sets the custom status line (refreshed every 60 seconds) and fullscreen TUI, carries the shared allow/ask/deny permission policy with auto mode disabled, and enables the `vercel` plugin. OpenCode `opencode.json` sets the shared default model `openai/gpt-5.6-sol` with `xhigh` reasoning effort, a top-level permission policy that asks before file edits and non-read-only bash while allowing read-only web fetch and search, the local `ollama/gemma4:31b` provider definition, disabled conversation sharing, enabled autoupdate, and shared-guidance instruction loading. OpenCode `tui.json` keeps a stacked diff view that works better in narrow terminals.

Machine-local paths (`projects/`, `agent-memory/`), auth/session state, and generated or host-specific config files remain intentionally excluded. The repo root `.gitignore` tracks the documented machine-local paths so accidental local state stays out of Git.

One exception lives inside the `opencode/` package: OpenCode generates its plugin dependencies (`package.json`, `bun.lock`, `package-lock.json`, and `node_modules/`) next to its config. The package directory holds the canonical copy, kept out of Git by a nested untracked `.gitignore`, and stow links them into `~/.config/opencode` with the rest of the payload. If stow reports conflicts on these files, remove the real copies under `$HOME` and re-stow; never delete the repo-side copies.

Repo-root instruction files exist only to maintain `dotfiles-ai` itself; they are not part of the stowed payload.

The top-level OpenCode permission policy requires approval for file edits and non-read-only bash commands while allowing a narrow set of read-only shell inspections. It applies to every agent, including task-spawned subagents, and keeps read-only `webfetch` and `websearch` allowed without widening shell command permissions.

Shared guidance now lives in `claude-code/.claude/rules/shared-guidance.md`. Claude Code loads it natively from `rules/`, while OpenCode loads the same file through the `instructions` field in `opencode.json` using `$HOME`-based path expansion.

This shared file reduces drift between Claude Code and OpenCode while keeping tool-specific wrappers thin.

Sharing follows a simple rule in this repo:

- Share policy.
- Separate mechanism.

In practice, guidance is shared when the content and meaning are the same in both tools. Tool-specific config, wrappers, and schemas stay separate.

At the repo root, `AGENTS.md` is the canonical project instruction file and `CLAUDE.md` is a thin compatibility wrapper for Claude Code.

OpenCode skills are loaded by the agent, while custom slash commands live under `commands/`; this repo keeps a `/commit` wrapper and folds documentation sync and scratch file cleanup into the commit workflow instead of maintaining a separate `/update` command.

## Review Workflow

For multi-file review in Claude Code or OpenCode, use Bash mode with Git diffs:

1. Run `!git status --short` to see touched files.
2. Run `!git diff --stat` for a compact overview.
3. Run `!git diff` to review the full patch.
4. Run `!git diff -- path/to/file` to isolate one file.

Both tools support `!`-prefixed Bash commands in the interactive terminal UI.

`opencode/.config/opencode/tui.json` sets `diff_style` to `stacked`, which is easier to scan in narrow terminals.

OpenCode docs can reflect the `dev` branch before a feature reaches the latest stable release, so prefer your installed `/help` output when docs and behavior disagree.

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

After stowing the shared AI tooling config:

- Confirm core symlinks exist: run `make verify`; it compares `readlink -f` targets, so the check holds whether or not stow tree-folded a parent directory
- Start a fresh Claude Code session and confirm the shared guidance file and status line load as expected.
- Run `opencode debug config` and confirm the resolved config includes the shared guidance path and `share = disabled`.
- Confirm no stray `~/.config/opencode/opencode.jsonc` exists; OpenCode auto-creates one only when it finds no config.
- Confirm `/commit` still routes through the repo skill workflow in both tools.

## Maintenance

A repo-root `Makefile` keeps the package list in one place and wraps the routine commands. Run targets from the repo root:

- `make stow` / `make unstow` / `make dry-run` / `make restow` - the stow command sets from Setup
- `make verify` - the Verify symlink checks plus JSON validity, statusline syntax, and stray `opencode.jsonc` checks
- `make clean` - the Prepare cleanup steps
- `make lint` - ShellCheck over `statusline.sh`; `.shellcheckrc` disables the one style-level finding so new issues stand out

## References

- `README.md` - repo scope, structure, setup, and verification
- `Makefile` - stow, verification, and cleanup automation
- `AGENTS.md` - canonical repo-specific assistant context and maintainer checklist
- `CLAUDE.md` - thin Claude Code wrapper importing `AGENTS.md`
- `claude-code/.claude/rules/shared-guidance.md` - canonical shared cross-tool guidance

## Related Repos

- `~/Projects/repos/dotfiles/dotfiles-omarchy` - personal Omarchy desktop customizations
- `~/Projects/repos/dotfiles/dotfiles-wsl` - self-contained WSL Arch dotfiles for the same repo family

## License

[MIT](LICENSE)
