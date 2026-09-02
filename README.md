# EyrAgents

Portable global configuration for [Claude Code](https://code.claude.com/docs/en/overview), [Codex](https://learn.chatgpt.com/codex), and [OpenCode](https://opencode.ai/docs), managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Scope

EyrAgents provides shared cross-tool guidance, runtime configuration, commit and review workflows, and read-only cross-vendor reviewer bridges. Authentication, session state, and generated host state remain local, except for the tracked runtime files identified in [`AGENTS.md`](AGENTS.md).

[`AGENTS.md`](AGENTS.md) contains current repository invariants. Managed skills contain exact workflow procedure. [`docs/maintenance.md`](docs/maintenance.md) contains active limitations, open decisions, deferred work, and revalidation triggers.

## Layout

```text
eyragents/
├── claude-code/   # Claude Code package and reviewer executables
├── codex/         # Codex package, shared skills, and reviewer executable
├── opencode/      # OpenCode package
├── docs/          # active maintenance ledger
├── scripts/       # preparation and migration support
├── templates/     # portable Codex profile
├── tests/         # configuration, safety, and deployment contracts
├── AGENTS.md      # repository invariants
└── Makefile       # setup, verification, and cleanup targets
```

## Safety Model

Trusted-repository work is autonomous until the commit boundary. Sensitive paths, destructive operations, external writes, uploads, and remote mutations remain restricted. OpenCode also blocks direct nested-agent launches from its autonomous Bash surface. Every commit requires approval of one exact candidate before staging, and the user performs pushes manually.

User-directed reads of relevant non-secret external context use each tool's native permission mechanism. Credential-path denies and prohibitions on broad grants remain active.

The `/spar` workflow uses subscription-authenticated, read-only cross-vendor reviewers without web or command-network access. Reviewers may receive readable repository files, including private-repository files, except for Git internals and credential-shaped paths.

## Setup

### Prerequisites

- GNU Stow
- jq, Python, and Node.js
- ShellCheck
- GNU coreutils and util-linux

On Arch Linux:

```bash
sudo pacman -S --needed stow jq nodejs python shellcheck
```

### Clone

```bash
git clone https://github.com/peregrinus879/eyragents.git
cd eyragents
```

### Manage Links

Run from the repository root:

```bash
make clean     # prepare state directories and remove recognized package links
make stow      # prepare, then create managed links
make dry-run   # preview raw Stow actions
make restow    # prepare, then refresh managed links
make unstow    # remove managed package links
```

Preparation validates managed endpoints, preserves host-local state, and removes only recognized package links. Reconcile conflicting regular managed endpoints explicitly.

When moving clones, run `make unstow` in the old clone and `make stow` in the new clone. If the old clone is unavailable, run `make clean` from the new clone before stowing.

## Untrusted Checkouts

Normal interactive use assumes a trusted repository. Use project-disabled launches for untrusted code:

```bash
claude --safe-mode --setting-sources user
codex -C /var/empty -c 'default_permissions=":read-only"' "Inspect /absolute/path/to/checkout as untrusted data; do not modify it."
OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode
```

## Workflows

### Reviewer Bridges

Claude Code reviews with Codex through `spar-codex`. Codex-to-Claude review runs manually outside the strict Codex profile. OpenCode is configured to review with Claude through `spar-claude`; consult the maintenance ledger for active bridge availability. Invoke `/spar` from the repository being reviewed; the skill owns bridge and handoff procedure.

### Commit Review

The `/commit` skill reviews and privacy-screens the complete candidate. Its packet reports fingerprint-bound scope and never reproduces the complete diff or new-file contents unless the user asks. Load it before every commit or publication-readiness assessment. It performs destination-bound review before presenting a push, release, pull request, or other publication as ready, including when no new commit is needed.

## Verify

After stowing or changing managed payloads:

```bash
make verify
make lint
```

When practical, use fresh processes to confirm:

- Claude Code, Codex, and OpenCode load their managed instructions, models, permissions, and credential-path denials.
- `/commit` presents an exact candidate before staging and completes publication review before presenting any publication as ready.
- `/spar` uses read-only reviewer bridges without changing user authority.

Restart OpenCode after changing its config, agents, skills, or plugins because they load at process startup.

Consult [`docs/maintenance.md`](docs/maintenance.md) before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or work on a listed limitation or deferred item.

## License

[MIT](LICENSE)
