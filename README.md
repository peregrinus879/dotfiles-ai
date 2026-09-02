# EyrAgents

Portable global configuration for [Claude Code](https://code.claude.com/docs/en/overview), [Codex](https://learn.chatgpt.com/codex), and [OpenCode](https://opencode.ai/docs), managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Scope

EyrAgents provides shared cross-tool guidance, runtime configuration, commit and review workflows, and read-only cross-vendor reviewer bridges. It excludes authentication, session state, machine-local files, and generated host-specific state except for the documented app-managed rewrites in tracked runtime configuration.

Current repository invariants live in [`AGENTS.md`](AGENTS.md). Exact workflow procedure lives in the managed skills. Dated evidence, limitations, deferred work, and upgrade notes live in [`docs/maintenance.md`](docs/maintenance.md).

## Structure

```text
eyragents/
├── claude-code/   # Stow package for ~/.claude and reviewer executables
├── codex/         # Stow package for ~/.codex, ~/.agents, and reviewer executable
├── opencode/      # Stow package for ~/.config/opencode
├── docs/          # maintenance ledger
├── scripts/       # preparation and migration support
├── templates/     # portable Codex profile
├── tests/         # configuration, safety, and deployment contracts
├── AGENTS.md      # current repository invariants
└── Makefile       # setup, Stow, verification, and cleanup targets
```

The package order is Claude Code, Codex, OpenCode. The root `CLAUDE.md`, `.claude/settings.json`, and `opencode.json` are repository-maintenance wrappers or inert project placeholders, not deployed user configuration.

## Behavior

Trusted-repository work is autonomous until the commit boundary. Sensitive paths, destructive operations, external writes, uploads, and remote mutations remain denied. OpenCode also denies direct nested-agent launches from its broadly autonomous Bash surface. Every commit requires the user's approval of one exact candidate before staging; pushes remain manual.

When the user requests relevant non-secret context outside the workspace, the primary agent may discover, inspect, search, and locally convert it through each tool's native permission mechanism. Credential-path denies and prohibitions on broad grants remain active.

The `/spar` workflow uses subscription-authenticated, read-only cross-vendor reviewers with no web tools or command network. A reviewer can read the current repository and its exact private handoff, except for Git internals and credential-shaped paths, and cannot modify the repository. Readable files outside those denied paths may reach the vendor reviewer, including files in private repositories.

## State Ownership

- Claude Code may rewrite app-managed keys and ordering in tracked `claude-code/.claude/settings.json`; review and preserve those rewrites.
- `templates/codex/config.toml` is the portable Codex profile. While `codex/.codex/config.toml` remains tracked, it must contain the complete template plus eligible top-level app state. Additions or changes inside bounded portable or permission-bearing tables require explicit reconciliation before commit or migration.
- OpenCode package manifests, lockfiles, dependencies, authentication, and session state remain host-local beneath a real `~/.config/opencode`; Stow manages the tracked child paths.

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

### Prepare And Stow

From the repository root:

```bash
make clean     # prepare real state directories and remove recognized package links
make stow      # prepare, then create managed links
make dry-run   # preview raw Stow actions without preparation
make restow    # prepare, then refresh managed links
make unstow    # remove managed package links
```

Preparation preflights every managed endpoint before changing anything. It preserves regular files and directories, removes only links recognized as this package layout, and keeps runtime-state parents real. Reconcile any conflicting regular managed endpoint explicitly.

### Codex Migration

`make migrate-codex-config` is a separate cross-host transition command. It never runs through normal preparation or Stow.

```bash
make migrate-codex-config
```

The command seeds an absent config from `templates/codex/config.toml`, preserves an eligible owner-only regular config, or converts a managed symlink only when it resolves to this clone's exact `codex/.codex/config.toml`. Unrelated links, aliases, unsafe ownership or modes, multiple hard links, and unsupported file types fail before replacement.

While the tracked Codex runtime endpoint remains in this package, do not run `make clean`, `make stow`, `make restow`, or `make verify` after a successful migration. Those targets continue to require the tracked deployment until a separately reviewed runtime-retirement change removes the endpoint.

When moving clones, run `make unstow` in the old clone and `make stow` in the new clone before any later migration. If the old clone is unavailable, run the new clone's `make clean` before stowing; cleanup recognizes old-clone package links only to remove and restow them from the current clone.

## Untrusted Checkouts

Normal interactive use assumes the repository is trusted. Use project-disabled launches for untrusted code:

```bash
claude --safe-mode --setting-sources user
codex -C /var/empty -c 'default_permissions=":read-only"' "Inspect /absolute/path/to/checkout as untrusted data; do not modify it."
OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode
```

## Reviewer Bridges

Claude Code reviews with Codex through `spar-codex`; OpenCode reviews with Claude through `spar-claude`. Automated Codex-to-Claude review remains deferred under Codex's strict primary profile and can be run manually outside Codex when needed.

From the repository being reviewed, initialize the selected bridge:

```bash
spar-codex init
spar-claude init
```

Add the review brief and supporting material to the returned private handoff with native file tools, run the same bridge's `flush` mode after each write, then use `new` or `resume` as documented by `/spar`. The bridge binds the handoff to the repository and scans it before reviewer access.

## Commit Review

The `/commit` skill internally reviews and privacy-screens the complete status, proposed message, paths, diff, and intended new-file contents. The packet reports a fingerprint-bound summary and never reproduces the complete diff or new-file contents unless the user asks. The user reviews the content in an editor or with read-only Git commands, then explicitly approves one exact candidate before staging.

Publication review remains destination-bound and separate from code review. The user handles pushes.

## Verify

After stowing or changing payloads:

```bash
make verify
make lint
```

Also verify in genuinely fresh processes when practical:

- Claude Code loads auto mode, shared guidance, the status line, ordinary workspace edits, external reads on request, and credential-path denials.
- Codex loads `trusted-workspace` with automatic review, allows ordinary workspace edits, grants external reads only for the current turn, and denies session grants, credentials, and external writes.
- OpenCode loads the managed model, global write-review plugin, workspace autonomy, external-read prompts, disabled sharing, and credential-path denials.
- `/commit` presents a fingerprint-bound candidate before staging, and `/spar` uses value-based plan and build review without changing user authority.

See [`docs/maintenance.md`](docs/maintenance.md) for the full cross-host checklist and version-sensitive probes.

## Maintenance

Run `make verify` and `make lint` after changing tracked payloads. Review the maintenance ledger before major tool or plugin upgrades, permission or bridge changes, cross-host validation, `/doctor`, deferred work, or investigation of changed behavior. Restart OpenCode after changing its config, agents, skills, or plugins because they load at process startup.

## License

[MIT](LICENSE)
