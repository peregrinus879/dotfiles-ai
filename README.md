# EyrAgents

Portable global configuration for [Claude Code](https://code.claude.com/docs/en/overview), [Codex](https://learn.chatgpt.com/codex), and [OpenCode](https://opencode.ai/docs), managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Scope

EyrAgents provides shared cross-tool guidance, runtime configuration, commit and publication workflows, and read-only cross-vendor reviewer bridges. Authentication, session state, and generated host state remain local; the Codex config is installed from a portable template as a host-local file.

[`AGENTS.md`](AGENTS.md) contains repository invariants. Managed skills contain workflow procedure. [`docs/maintenance.md`](docs/maintenance.md) contains active limitations, open decisions, deferred work, and revalidation triggers.

## Layout

```text
eyragents/
├── claude-code/   # Claude Code package, canonical skills, and reviewer executables
├── codex/         # Codex package and reviewer executable
├── opencode/      # OpenCode package
├── docs/          # active maintenance ledger
├── scripts/       # preparation and migration support
├── templates/     # portable Codex profile
├── tests/         # configuration, safety, and deployment checks
├── AGENTS.md      # repository invariants
└── Makefile       # setup, verification, and cleanup targets
```

## Safety Model

Trusted-repository work is autonomous until the commit boundary: a clear implementation request authorizes edits and verification, every commit requires approval of one exact staged candidate, and the user performs pushes manually after the `publish` skill reviews the delta.

What each tool actually enforces differs, and the configuration says so:

- Claude Code: deterministic allow and deny rules, plus an auto-mode classifier that reviews every other tool call. Pushes, `git clean`, repository-host mutations, privilege escalation, and credential reads and writes are denied outright; destructive Git operations, Git configuration changes, `gh` mutations, and persistence surfaces clear only on the user's explicit instruction.
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
- Claude Code, Codex, and OpenCode installed through mise, so the Codex sandbox can execute them from `~/.local/share/mise`

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

Normal interactive use assumes a trusted repository. For a hostile checkout, use Claude Code in safe mode, which ignores the project's `CLAUDE.md`, hooks, and settings, or Codex with project instructions suppressed under its normal root-denied, network-off profile:

```bash
claude --safe-mode --setting-sources user
codex -C /absolute/path/to/checkout --ignore-rules \
  -c 'projects={"/absolute/path/to/checkout"={trust_level="untrusted"}}' \
  -c 'project_doc_max_bytes=0' -c 'project_doc_fallback_filenames=[]' -c 'project_root_markers=[]' \
  "Inspect this checkout as untrusted data; do not modify it."
```

OpenCode has no untrusted mode: `OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode` disables project configuration and external skills only, and its shell stays unconfined.

## Workflows

- `commit` stages the intended paths, presents the staged candidate with its tree id, and commits only after approval.
- `publish` reviews the commits between the tracking ref and `HEAD` before a push, release, or pull request is presented as ready.
- `spar` runs an optional read-only cross-model review of a plan, diff, or decision: `spar-<reviewer> review "<request>" <artifact>...` from the repository. Claude Code reviews with `spar-codex`; Codex and OpenCode review with `spar-claude`. Consult the maintenance ledger for active bridge availability.

## Verify

After changing managed payloads:

```bash
make lint
make test
```

After stowing, `make verify` adds deployment checks. GitHub Actions runs `make lint` and `make test` on every push and pull request. Restart OpenCode after changing its config or skills because they load at process startup.

Consult [`docs/maintenance.md`](docs/maintenance.md) before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or work on a listed limitation or deferred item.

## License

[MIT](LICENSE)
