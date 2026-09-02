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

Trusted-repository work is autonomous until the commit boundary: a clear implementation request authorizes edits and verification, every commit requires approval of one exact staged candidate, and the user performs pushes manually after the `publish` skill reviews the delta. Pushes, repository-host mutations, privilege escalation, destructive Git operations, and credential-path reads are denied deterministically in every tool; OpenCode also blocks direct nested-agent launches from its autonomous Bash surface.

User-directed reads of relevant non-secret external context use each tool's native permission mechanism. Broad working-root grants remain prohibited.

The `spar` workflow uses subscription-authenticated, read-only cross-vendor reviewers without web or command-network access. A reviewer may receive readable repository files, including private-repository files, except for Git internals and credential-shaped paths, so each bridge runs only in repositories where `git config spar.consent` is `true`.

## Setup

### Prerequisites

- GNU Stow
- jq and Python
- ShellCheck
- GNU coreutils

On Arch Linux:

```bash
sudo pacman -S --needed stow jq python shellcheck
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

When moving clones, run `make unstow` in the old clone and `make stow` in the new clone. If the old clone is unavailable, `make stow` from the new clone removes the dangling links first.

## Untrusted Checkouts

Normal interactive use assumes a trusted repository. Use project-disabled launches for untrusted code:

```bash
claude --safe-mode --setting-sources user
codex -C /var/empty -c 'default_permissions=":read-only"' "Inspect /absolute/path/to/checkout as untrusted data; do not modify it."
OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode
```

## Workflows

- `commit` stages the intended paths, presents the staged candidate with its tree id, and commits only after approval.
- `publish` reviews the commits between the tracking ref and `HEAD` before a push, release, or pull request is presented as ready.
- `spar` runs an optional read-only cross-model review of a plan, diff, or decision: `spar-<reviewer> review "<request>" <artifact>...` from the repository, after `git config spar.consent true`. Claude Code reviews with `spar-codex`; Codex and OpenCode review with `spar-claude`. Consult the maintenance ledger for active bridge availability.

## Verify

After changing managed payloads:

```bash
make lint
make test
```

After stowing, `make verify` adds deployment checks. Restart OpenCode after changing its config or skills because they load at process startup.

Consult [`docs/maintenance.md`](docs/maintenance.md) before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or work on a listed limitation or deferred item.

## License

[MIT](LICENSE)
