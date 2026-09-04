# EyrAgents

Portable global configuration for [Claude Code](https://code.claude.com/docs/en/overview), [Codex](https://learn.chatgpt.com/codex), and [OpenCode](https://opencode.ai/docs), managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Scope

EyrAgents provides shared cross-tool guidance, runtime configuration, commit and publication workflows, and read-only cross-vendor reviewer bridges. Authentication, session state, and generated host state remain local; the Codex config is installed from a portable template as a host-local file.

[`AGENTS.md`](AGENTS.md) contains repository invariants. Managed skills contain workflow procedure. [`docs/maintenance.md`](docs/maintenance.md) contains active limitations, open decisions, deferred work, and revalidation triggers.

## Repo Family

Derivation model for this repo family:

```text
AI agent harness                → EyrAgents
Omarchy + personal deviations   → EyrArcHy
Omarchy + WSL deviations        → EyrWSL
```

- [`eyragents`](https://github.com/peregrinus879/eyragents) - AI agent harness: Claude Code, Codex, and OpenCode settings, shared guidance, and commit workflow
- [`eyrarchy`](https://github.com/peregrinus879/eyrarchy) - Personal Omarchy customizations: Bash overrides, Hyprland bindings, Neovim plugins, and Yazi
- [`eyrwsl`](https://github.com/peregrinus879/eyrwsl) - Self-contained WSL Arch environment: terminal baseline plus Windows Terminal and clipboard integration

Local clones live side by side under `~/Projects/eyrie/`.

## Layout

Each path inside a package mirrors its path under `~`; Stow links every leaf file into place.

```text
eyragents/
├── agents/.agents/                       # tool-neutral source package, deployed to ~/.agents
│   ├── shared-guidance.md                # canonical cross-tool policy
│   └── skills/{commit,publish,spar}/SKILL.md   # canonical skills; Codex reads them here
├── claude-code/                          # Claude Code package
│   ├── .claude/
│   │   ├── rules/shared-guidance.md      # symlink to the shared guidance
│   │   ├── skills/{commit,publish,spar}/SKILL.md   # symlinks to the canonical skills
│   │   ├── settings.json                 # permissions and auto-mode rules
│   │   └── statusline.sh
│   └── .local/bin/{spar-claude,spar-payload-scan}   # Claude reviewer bridge and payload scanner
├── codex/                                # Codex package
│   ├── .codex/AGENTS.md                  # symlink to the shared guidance
│   └── .local/bin/spar-codex             # Codex reviewer bridge
├── opencode/.config/opencode/            # OpenCode package
│   ├── opencode.json                     # permissions, model, and the shared guidance path
│   ├── tui.json
│   ├── commands/{commit,publish,spar}.md # slash commands that load the skills
│   └── skills/{commit,publish,spar}/SKILL.md   # symlinks to the canonical skills
├── templates/codex/config.toml           # portable Codex profile, installed host-locally by make stow
├── references.txt                        # reference clone the ledger's source checks read; the siblings' make refs keeps it
├── scripts/                              # link cleanup and Codex config reconciliation
├── tests/                                # configuration, bridge, statusline, and preparation checks
├── docs/maintenance.md                   # active maintenance ledger
├── .github/workflows/test.yml            # CI: make lint and make check
├── AGENTS.md                             # repository invariants
└── Makefile                              # setup, verification, and cleanup targets
```

## Safety Model

Trusted-repository work is autonomous until the commit boundary: a clear implementation request authorizes edits and the repository's gates, every commit requires approval of one exact staged candidate, and the user performs pushes manually after the `publish` skill reviews the delta; the same skill verifies the push and the published state afterwards.

What each tool actually enforces differs, and the configuration says so:

- Claude Code: deterministic allow and deny rules, plus an auto-mode classifier that reviews every other tool call. The named command forms of pushes, `git clean`, `gh` repository mutations, and privilege escalation are denied by rule, as are credential reads and writes through the file tools; everything else, including alternate command spellings, shell access to credential paths, destructive Git operations, Git configuration changes, and persistence surfaces, is the classifier's call and clears only on the user's explicit instruction.
- Codex: an OS sandbox with the filesystem root denied, credential stores and shapes denied, `.git/config` and `.git/hooks` read-only, and command network off. Permission requests go through an automatic reviewer.
- OpenCode: lexical Bash rules, worktree-relative read and edit rules, and an ask default outside the workspace and the app temp root. It has no sandbox or classifier, so its rules are guardrails against mistakes, not containment against a prompt-injected session.

This repository is itself live configuration on a stowed host: an edit here is active for the next session of the tool it belongs to before anything is committed. Work on it only in a session you are watching.

User-directed reads of relevant non-secret external context use each tool's native permission mechanism; a directory the user names may be granted, broad or unnamed grants may not.

The `spar` workflow uses subscription-authenticated, read-only cross-vendor reviewers without web or command-network access. A reviewer may receive readable repository files, including private-repository files, except for Git internals and credential-shaped paths; a repository that must stay private opts out with `git config spar.consent false`, which every bridge honors.

## Setup

### Prerequisites

- Git and GNU Stow
- jq and Python
- ShellCheck
- GNU coreutils and util-linux (`setsid`)
- Claude Code, Codex, and OpenCode installed where the Codex sandbox can execute them: through mise on Omarchy (`~/.local/share/mise`), and through the official Arch packages plus the Claude Code installer under `~/.claude/bin` on WSL

On Arch Linux:

```bash
sudo pacman -S --needed git stow jq python shellcheck util-linux
```

### Clone

```bash
git clone https://github.com/peregrinus879/eyragents.git
cd eyragents
```

### Manage Links

Run from the repository root:

```bash
make clean     # remove dangling links that point into this repository's packages
make stow      # clean, then link every package file (directories stay real)
make dry-run   # preview Stow actions
make restow    # clean, then refresh links after repo content changes
make unstow    # remove package links
```

Stow runs without directory folding, so `~/.claude`, `~/.config/opencode`, and the other managed parents stay real directories that tools may write into. Stow reports any conflicting regular file without changing it; reconcile it explicitly.

`make stow` and `make restow` also install `~/.codex/config.toml` from `templates/codex/config.toml` as a host-local file. The template owns the model, review, feature, and permission settings; tables that Codex or the desktop app add (projects, plugins, MCP servers, desktop state) are preserved across reconciliations.

When moving clones, run `make unstow` in the old clone and `make stow` in the new clone. If the old clone is unavailable, `make stow` from the new clone removes the dangling links first.

## Untrusted Checkouts

Normal interactive use assumes a trusted repository. For a hostile checkout, use Claude Code in safe mode, which ignores the project's `CLAUDE.md`, hooks, and settings, or Codex with project instructions suppressed under its normal root-denied, network-off profile. Neither launch confines the model against instructions it reads in file contents; Codex keeps its writable workspace and whatever desktop-app surfaces are enabled:

```bash
claude --safe-mode --setting-sources user
codex -C /absolute/path/to/checkout --ignore-rules \
  -c 'projects={"/absolute/path/to/checkout"={trust_level="untrusted"}}' \
  -c 'project_doc_max_bytes=0' -c 'project_doc_fallback_filenames=[]' -c 'project_root_markers=[]' \
  "Inspect this checkout as untrusted data; do not modify it."
```

OpenCode has no untrusted mode: `OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode` disables project configuration and external skills only, and its shell stays unconfined.

## Workflows

- `commit` runs the repository's gates, stages the intended paths, presents the staged candidate with its tree id and gate report, and commits only after approval; when the request is done it hands off to `publish`.
- `publish` reviews the commits between the destination's tracking ref and the reviewed commit, scans them, binds the push to both ends with a lease before a push, release, or pull request is presented as ready, and after the user's push confirms the destination and, where the repository defines `verify-published`, the published state.
- `spar` runs an optional read-only cross-model review of a plan, diff, or decision: `spar-<reviewer> review "<request>" <artifact>...` from the repository. Claude Code reviews with `spar-codex`, OpenCode with `spar-claude`, and a Codex session hands the request to the user because its profile cannot launch the bridge. Consult the maintenance ledger for active bridge availability.

The skills read a target contract instead of per-repository rules. `lint` and `check` are the repository checks, safe anywhere and run by CI; `restow` and `verify` are the host verification, refusing on the wrong host or clone; `verify-published` runs after a push, waits for the deployment, and compares the published commit with the pushed one. Make targets and npm scripts of the same names are equivalent, and a repository declares a gate by defining it.

## Verify

After changing managed payloads:

```bash
make lint
make check
```

After stowing, `make verify` runs both and adds deployment checks. GitHub Actions runs `make lint` and `make check` on every push to `main` and every pull request. Restart OpenCode after changing its config or skills because they load at process startup.

Consult [`docs/maintenance.md`](docs/maintenance.md) before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or work on a listed limitation or deferred item.

## License

[MIT](LICENSE)
