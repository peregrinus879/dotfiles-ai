# EyrAgents

Claude Code, Codex, and OpenCode global dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Supported Tools

- [Claude Code](https://code.claude.com/docs/en/overview) - AI-powered coding assistant with a terminal CLI
- [Codex](https://learn.chatgpt.com/codex) - OpenAI's coding agent with a terminal CLI
- [OpenCode](https://opencode.ai/docs) - Open source AI coding agent with a terminal-based interface

## Scope

This repo tracks shared cross-tool AI assistant guidance and portable tracked config for Claude Code, Codex, and OpenCode.

It intentionally excludes auth and session state, machine-local files, and generated host-specific config except for the documented app-managed rewrites inside tracked runtime config. The repo root keeps the canonical `AGENTS.md`, a thin `CLAUDE.md` compatibility wrapper, and inert per-tool project config placeholders with no command grants.

## Structure

```
eyragents/
├── AGENTS.md                             # canonical repo maintenance instructions
├── CLAUDE.md                             # Claude wrapper importing AGENTS.md
├── LICENSE                               # MIT license
├── Makefile                              # stow, verification, and cleanup automation
├── README.md                             # human-facing documentation
├── docs/
│   └── maintenance.md                    # on-demand limitations, probes, and deferred work
├── scripts/
│   └── prepare-stow.sh                   # non-destructive Stow preparation
├── templates/
│   └── codex/
│       └── config.toml                   # frozen portable Codex profile
├── tests/                                # security and configuration fixtures
│   ├── config-contracts.py
│   ├── prepare-stow.sh
│   ├── project-config-isolation.sh
│   ├── reviewed-writes.mjs
│   ├── spar-bridges.sh
│   └── statusline-state.sh
├── .claude/
│   └── settings.json                     # inert Claude Code project config
├── .shellcheckrc                         # ShellCheck disable list for managed Bash scripts
├── opencode.json                         # inert OpenCode project config
├── claude-code/                          # stow package -> ~/.claude/, ~/.local/bin/
│   ├── .claude/
│   │   ├── .gitignore                    # excludes Claude runtime state
│   │   ├── CLAUDE.md                     # Claude-specific instructions
│   │   ├── settings.json                 # runtime settings (model, status line, permissions, workflows)
│   │   ├── statusline.sh                 # terminal status line script
│   │   ├── hooks/
│   │   │   └── spar-handoff-approve.sh   # validated spar handoff write exception
│   │   ├── rules/                        # organized instruction files
│   │   │   └── shared-guidance.md        # canonical shared instructions
│   │   └── skills/                       # custom skills (SKILL.md files)
│   │       ├── commit/                   # candidate and publication review workflow
│   │       └── spar/                     # cross-model sparring and reviews (reviewer: spar-codex)
│   └── .local/
│       └── bin/
│           ├── spar-claude               # latest-Opus read-only reviewer bridge for spar
│           └── spar-payload-scan         # bounded outbound and inbound content scanner
├── codex/                                # stow package -> ~/.codex/, ~/.agents/, ~/.local/bin/
│   ├── .agents/
│   │   └── skills/                       # agent skills (documented user scope)
│   │       ├── commit/                   # candidate and publication review workflow
│   │       └── spar/                     # cross-model sparring and reviews (reviewer: spar-claude)
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
            ├── .gitignore                # excludes host-local package state
            ├── opencode.json             # runtime config and agent overrides
            ├── tui.json                  # TUI-specific config
            ├── commands/                 # custom slash commands
            │   ├── commit.md             # wrapper for the commit skill
            │   └── spar.md               # wrapper for the spar skill
            ├── plugins/                  # all-target patch and handoff safety plugin
            │   ├── package.json          # private ESM marker
            │   └── reviewed-writes.ts    # write-review plugin
            ├── skills/                   # agent skills
            │   ├── commit/               # candidate and publication review workflow
            │   └── spar/                 # cross-model sparring and reviews (reviewer: spar-claude)
```

Tracked `.gitkeep` placeholders (claude-code agents; opencode agents, themes, and tools) are omitted from the tree.

Tracked runtime config primarily expresses shared behavior. `claude-code/.claude/settings.json` and `opencode/.config/opencode/opencode.json` are their tools' managed sources of truth. `templates/codex/config.toml` freezes the portable Codex profile; while `codex/.codex/config.toml` remains tracked, verification requires that runtime config to contain the complete template plus its app-managed host state. Trusted-repository work is autonomous until the commit boundary: Claude Code uses auto mode, Codex uses a write-capable workspace profile plus automatic approval review, and OpenCode allows workspace edits and shell commands while asking before native external-directory access and denying sensitive paths plus direct destructive, privileged, upload, and remote-mutation commands. OpenCode has no classifier or OS sandbox; its external-directory guard covers only Bash commands recognized by the upstream path scanner, so unrecognized direct readers, dynamic path arguments, wrappers, and scripts remain instruction-governed residuals. Every commit requires H's editor review and approval of the exact candidate before staging. Session handoffs use private disk-backed OS temp (`/var/tmp/spar-<session-id>/`) so an in-flight review survives reboots; the Claude hook and OpenCode plugin validate handoff writes without reintroducing ordinary per-file prompts. OpenCode `tui.json` keeps a stacked diff view that works better in narrow terminals.

When H asks to inspect or search non-secret context outside the workspace, the primary agent may use suitable read-only local tools for the relevant files and directories, including path discovery and local format conversion. Claude Code handles those reads through native auto-mode permissions, Codex keeps filesystem root denied and uses turn-scoped `request_permissions`, and OpenCode uses native `external_directory` asks. Credential-path denies remain active in all three tools. Ordinary personal information and document formats are not credentials; broad working-root grants, external writes, session grants, subagents, reviewers, and secret or credential access remain prohibited.

OpenCode's write-review plugin validates every `apply_patch` source and move destination for workspace containment, sensitive path shapes, symlink aliases, existing hard links, and stricter handoff constraints before grouped operations reach native permission handling.

The three reviewer executables are ordinary Stow-managed payloads. Each bridge scans the prompt and handoff and validates repository path names before authentication; rejects Git-control variables, repository hard-linked files outside denied directories, nested repository mounts, and path shapes that its read-deny policy cannot cover; launches its subscription reviewer from the caller's canonical Git root; and grants read-only access to that repository plus the exact handoff. Later native permission rules deny Git internals, credential-shaped paths, and the bridge-owned `reviewer-id`; repository files outside those denies may reach the reviewer, including private-repository files.

Primary web research follows Claude auto mode's outcome. Claude remains explicitly pinned to auto and sends unmatched WebSearch and WebFetch calls through its classifier. Codex uses hosted live search and page opening without granting network to shell commands. OpenCode allows WebSearch and WebFetch without prompts; its WebFetch implementation has no Claude-equivalent classifier or resolved-address SSRF boundary, so the sensitive-read denies and prohibition on sending repository content remain material controls. Both spar reviewers stay search-disabled.

Codex, OpenCode, and `spar-codex` use GPT-5.6 Sol Fast with xhigh reasoning. Codex represents Fast as model `gpt-5.6-sol` plus `service_tier = "fast"` and `features.fast_mode = true`; the ChatGPT-authenticated Codex API rejects `gpt-5.6-sol-fast` as a model slug. Its primary and built-in subagents use xhigh, and the primary retains automatic summaries. OpenCode directly selects its catalog's `openai/gpt-5.6-sol-fast` mode, which resolves to API model `gpt-5.6-sol` with Priority service; the tracked overlay sets only the xhigh base effort because OpenCode generates the automatic-summary options. An explicitly selected TUI variant persists and takes precedence over that base option; primary agents use the global default and subagents inherit the invoking primary model. The single-agent `spar-codex` reviewer uses xhigh and suppresses summaries because its bridge discards them. The managed configuration assumes ChatGPT subscription authentication, where Fast consumes GPT-5.6 credits at 2.5 times the Standard rate. ChatGPT Pro raises included Codex limits but does not enable Responses API Pro reasoning mode; API-key use invokes separately billed processing and requires a separate configuration and billing decision.

Claude Code selects Fable 5 through the durable `fable` alias and requests xhigh through `CLAUDE_CODE_EFFORT_LEVEL=xhigh`, which also keeps ultracode orchestration inactive. `spar-claude` clears any inherited effort setting, selects the current `opus` alias, and requests `--effort xhigh` for new and resumed reviews; organization-managed model and effort limits remain higher precedence.

OpenCode's in-app updater is disabled because the host installation wrapper owns release selection. Its enabled-provider gate and tracked provider block contain only OpenAI, the provider used by the managed model.

Nested payload ignore files protect fresh clones if a state directory is accidentally folded into the repository.

Three payload-side exceptions exist. Claude Code writes app-managed keys and key ordering into its tracked `settings.json`; commit those rewrites as-is. While Codex runtime config remains tracked, Codex and the ChatGPT desktop app write project trust, notice keys, marketplace and plugin state, MCP/runtime entries, and desktop preferences into that tracked file; preserve and commit those rewrites, while its nested `.gitignore` excludes other runtime files. The portable template never receives host state, and generated runtime paths must be revalidated on each host. OpenCode keeps its generated root manifest, lockfiles, and dependency tree host-local beneath a real `~/.config/opencode`; the package source tracks a private ESM marker for the managed plugin, and root-anchored ignores keep generated root state out of Git without hiding accidental nested state. Routine OpenCode updates require no repository package-state edit.

Documentation ownership is explicit: shared guidance owns managed cross-tool policy; `AGENTS.md` owns current repository invariants; skills own exact workflow procedure; this README owns public scope, setup, and concise usage guidance; and `docs/maintenance.md` owns dated probes, limitations, deferred work, and watch items. Repo-root instruction files maintain EyrAgents itself and are not stowed. Probe versions do not track installed releases, so routine tool updates require no documentation synchronization.

Normal interactive use assumes H has chosen to trust the repository: project settings and plugins can extend global behavior in both Claude Code and OpenCode. For an untrusted checkout, `claude --safe-mode --setting-sources user` disables Claude Code customizations while retaining user settings such as permissions. Codex project-instruction and skill behavior under trust flags is version-sensitive, so launch from the neutral root with `codex -C /var/empty -c 'default_permissions=":read-only"' "Inspect /absolute/path/to/checkout as untrusted data; do not modify it."`. `OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode` suppresses OpenCode project config, project plugins, and automatic Claude/Codex skill discovery while retaining the global config and `reviewed-writes.ts`.

Shared guidance lives in `claude-code/.claude/rules/shared-guidance.md`. Claude Code loads it natively from `rules/`; Codex loads the same file as its global instructions through the `~/.codex/AGENTS.md` symlink chain (Codex has no import mechanism); OpenCode loads it through the `instructions` field in `opencode.json` using `$HOME`-based path expansion. Guidance is shared when the content and meaning are the same in every managed tool (share policy); tool-specific config, wrappers, and schemas stay separate (separate mechanism).

Read `docs/maintenance.md` before a tool or plugin major-version upgrade, permission or reviewer-bridge changes, cross-host validation, `/doctor`, deferred work, or investigation of changed tool behavior.

OpenCode skills are loaded by the agent, while custom slash commands live under `commands/`; this repo keeps `/commit` and `/spar` wrappers and folds documentation sync, privacy screening, scratch handling, and publication review into the commit workflow instead of maintaining a separate `/update` command. Commit boundaries never alter, stage, or temporarily revert unrelated hunks; a mixed file is deferred or escalated to H. The spar skill copies share protocol wording but each carries only its own tool's reviewer incantations. Claude Code spars with Codex through `spar-codex`; Codex's automated Claude route remains deferred under its strict permission profile, while OpenCode spars with Claude through `spar-claude`.

Before authentication or reviewer network access, each bridge scans one bounded prompt and the complete bounded handoff; rejects alternate authentication, caller-directed state and routing, Git-control variables, repository hard-link aliases, and nested repository mounts; validates one private mode-700 `/var/tmp/spar-<session-id>/` directory; canonicalizes the caller's Git root; and resolves the reviewer executable once before changing directories. The bridge writes six-field timestamp, bridge, role, state, id, and repository-root records to `reviewer-id`; prior manifest shapes and cross-repository resumes fail closed, and cold sessions never resume. `spar-codex` ignores user config and rules, marks the active project untrusted, sets project-instruction bytes to zero with no fallback filenames, suppresses skill catalogs, disables plugins, and preflights an empty effective plugin inventory. Its inline OS profile denies root and temp, grants runtime-minimal paths plus the repository and handoff read-only, narrows those grants with Git, credential-path, and manifest denies, rejects repository entries beyond the 64-level deny-glob bound, and disables command network. `spar-claude` selects the current `opus` alias, adds the handoff to the repository launch, uses safe mode with no user, project, or local setting sources or extension tools, combines `dontAsk` with explicit repository and handoff read allows plus later sensitive-path denies, exposes only `Read`, `Glob`, and `Grep`, validates every served-model key as Opus-family, and disables nonessential traffic and updater activity; higher-precedence managed policy remains in force. A call succeeds only after one valid terminal event for the requested session or thread with a nonempty locally rescanned reply. Bounded Codex diagnostics use the reply scanner before relay. Each bridge owns the reviewer process group so repeated signals, stalls, ceilings, and normal exits terminate remaining descendants before returning.

Filesystem-root repositories fail before any read grant. Claude authentication preflight uses the review's safe-mode setting-source isolation and rejects ambient third-party provider, endpoint, and auth-skip controls; absolute account-home credential denies remain later than any overlapping repository allow. Codex accepts its disabled-plugin preflight only when `installed` is structurally an empty array. Failure cleanup removes private diagnostic work before best-effort identifier reporting.

Repository path preflight validates every canonical-root component's spelling and every repository entry name it enumerates without reading file contents. It prunes the repository-root `.git` and exact repository-root `secrets` subtrees and does not follow directory symlinks. It rejects nested `.git` directories, sensitive directory names that lack an exact subtree deny, sensitive-named symlinks, symlinks below nested `secrets` trees whose deny depends on glob expansion, case variants of sensitive names, non-UTF-8 names, and names containing control characters, quotes, or backslashes. Ordinary public symlinks remain reviewable. Hard-link validation prunes only the root Git metadata subtree and exact lowercase `secrets` directories. The scanner parses LF-delimited Git records and strictly decodes C-quoted paths before applying the same sensitive-name grammar to every path component used by the reviewer policies and native handoff-write gates.

OpenCode's host environment disables automatic external skill discovery so its managed commit and spar copies are selected instead of the colliding Claude and Codex copies. The optional Omarchy integration is the only tracked `skills.paths` entry and is ignored when absent. When installed, its `.bashrc` owner covers terminal-first interactive descendants; non-interactive OpenCode launchers must set `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` themselves.

Reviewers stay offline: Codex reviewer web search and network are disabled, and the Claude reviewer has no web tools. This prevents query-based exfiltration, reduces external prompt-injection exposure, and keeps reviews reproducible. The implementer verifies material current external claims against primary sources and gives every substantive review the target, evidence, and a Decision Rationale covering the research, alternatives, tradeoffs, H's rulings, authorized changes, and remaining uncertainty. The reviewer challenges concrete defects in that reasoning or its implementation rather than repeating settled research merely because another approach exists. The implementer chooses blind or fully briefed, fresh or resumed, single or iterative review according to expected value. Any issue left for H arrives as a self-contained ruling packet with both positions, evidence, consequences, reversibility, affected work, and the implementer's labeled recommendation; raw reviewer transcripts remain optional.

The spar workflow supports brainstorming, plan, build, and diff-only review. Plan and build are the primary checkpoints, not mandatory gates: plan review fits after research and analysis and before the final plan is presented, while build review fits after approved commits and compares the starting-base-to-HEAD result with the latest approved plan and Decision Rationale. The implementer may spar at any other point and chooses the review shape and depth from expected value, risk, uncertainty, independence, and cost. Atomic implementation units retain the exact human commit boundary without automatic per-unit reviewer gates. Reviewer convergence never authorizes a commit or push; unresolved evidence, scope, or value judgments return to H without discarding the worktree.

Status line state-file conventions live in the `statusline.sh` header and the AGENTS.md invariant.

## Review Workflow

The `/commit` skill owns the exact editor and terminal review procedure and repeats the current instructions in every candidate packet. The assistant internally inventories and privacy-screens the complete status, proposed message, paths, diff, and intended new-file contents against the intended audience, defaulting to world-readable publication. The packet reports a fingerprint-bound summary and never reproduces the complete diff or new-file contents unless H asks; H reviews content in Neovim or with the listed read-only Git commands. Its only explicit selector choices are `Commit and resume` and `Commit and pause`; the built-in custom answer handles questions, revision requests, rejection, and other instructions. Custom input never authorizes staging or commit. Either explicit choice authorizes staging and one commit of the exact packet. Resume proceeds only with remaining work already covered by H's active request or approved plan; pause stops after commit verification and status. A revision requires a refreshed packet. Rejection preserves the candidate and worktree unless H explicitly requests disposal, while custom input that changes nothing repeats the unchanged candidate after the answer.

After all approved units, the managed `/commit` workflow withholds any publication-ready claim or push hint until it reviews the exact history and artifacts the destination, audience, ref set, and effective operation would expose. Destination state narrows the review only when confirmed current and enforced as an execution-time expected value; otherwise the complete history of the published refs is reviewed. Coverage includes commit and annotated-tag metadata, path names, intermediate or later-deleted planning, review, and documentation versions, referenced Git LFS objects, every action-metadata field and value, every action body and asset digest, configured push options, and active client-side hooks. Paths are inventoried before content, Safety-barred or opaque artifacts remain unread, and every record reconciles to reviewed content, an exact H ruling, or a blocker. H inspects an unreadable artifact in a separate terminal pane, never through `!` or pasted session content. The result reports its credential-free logical destination, immutable source IDs and asset digests, exact operation, destination-state freshness, coverage, rulings, and omissions; endpoint credentials and transient authenticated transfer URLs never enter the descriptor. Any bound-value change, unresolved implicit behavior, or incomplete coverage invalidates it. Code review and secret scanning remain separate checks.

## Setup

### Prerequisites

- [GNU Stow](https://www.gnu.org/software/stow/)
- jq, Python, and Node.js (event parsing, semantic contracts, payload scanning, and plugin tests)
- ShellCheck (shell linting)
- GNU coreutils (`readlink`, `realpath`, `sha256sum`, and `stat`; included in the Arch base system)
- util-linux (`setsid` and `findmnt`; included in the Arch base system) and GNU `timeout`

On Arch Linux, for example:

```bash
sudo pacman -S --needed stow jq nodejs python shellcheck
```

### Clone

```bash
git clone https://github.com/peregrinus879/eyragents.git
cd eyragents
```

### Prepare

Checklist before stowing:

- Stow is installed
- EyrAgents was cloned locally
- Any existing conflicting config files were identified and retained for explicit reconciliation

From the repository root, prepare the state directories and remove only symlinks that resolve to this package layout:

```bash
make clean
```

The cleanup preflights every endpoint before changing anything. It refuses regular files and directories at managed leaf endpoints and symlinks outside the recognized package layout. It keeps `~/.claude`, `~/.claude/skills`, `~/.codex`, `~/.agents`, `~/.agents/skills`, `~/.local`, `~/.local/bin`, `~/.config`, and `~/.config/opencode` as real directories. OpenCode generated package files and `node_modules/` remain host-local when they are regular files/directories; recognized legacy package links, including dangling links to an old clone, are removed, while unmanaged generated-state links abort the complete preflight before mutation.

`make stow` and `make restow` invoke the same preparation automatically before creating managed child links. OpenCode may then reconcile its host-local package state without writing generated files into the repository. Normal preparation still treats `~/.codex/config.toml` as a managed Stow endpoint while the tracked runtime file exists.

The explicit `make migrate-codex-config` target prepares Codex runtime ownership without running ordinary cleanup or Stow. It requires `HOME` and `~/.codex` to be real, current-user-owned directories that are not writable by another user. An absent config is atomically seeded from `templates/codex/config.toml`; a managed leaf is converted only when its canonical target is this clone's exact `codex/.codex/config.toml`; an existing single-link regular file with owner-only, non-executable mode 400 or 600 is preserved without rewriting. Dangling or unrelated links, filesystem aliases, unsafe ownership or modes, multiple hard links, and unsupported file types fail before replacement. The same-directory temporary file is mode 600, flushed and byte-compared before rename, and removed on failure without deleting similarly named files.

Migration is an explicit cross-host transition step and never runs from `make clean`, `make stow`, or `make restow`. This tooling does not migrate the current host automatically. While the tracked runtime endpoint remains in the Codex Stow package, do not run `make clean`, `make stow`, `make restow`, or `make verify` after a successful migration; the first three intentionally refuse the host-local regular config, and verification continues to require the tracked deployment until the separately reviewed runtime-retirement step removes that endpoint.

### Stow

The Makefile owns the package list and the stow command sets; run the targets from the repo root:

```bash
make stow      # create symlinks for all packages
make unstow    # remove all package symlinks
make dry-run   # preview raw Stow actions without preparation
make restow    # update symlinks after repo content changes
make migrate-codex-config  # explicitly prepare host-local Codex runtime ownership
```

Each target uses the ordinary package invocation:

```bash
stow -v -t ~ claude-code codex opencode
```

The three `~/.local/bin/spar-*` endpoints resolve directly to their package files, whether Stow creates leaf links or folds a parent directory.

### Reviewer Bridges

Run `spar-claude init` or `spar-codex init` from the repository that will be reviewed. The returned handoff is bound to that canonical Git root immediately. Git-control environment variables, repository hard-linked files outside denied directories, nested repository mounts, unsupported repository path spellings or sensitive directories without an exact subtree deny, unrepresentable permission-pattern roots, and Codex repository entries deeper than its deny-glob bound fail closed. Add the exact target and supporting material with native file tools, run the same bridge's `flush` mode after every write, then use `new` or `resume` as documented by the `/spar` skill. The reviewer receives the repository and handoff read-only but cannot read `reviewer-id`, Git internals, or the configured credential-shaped paths.

The scanner permits at most a 256 KiB prompt, 128 handoff entries, 512 KiB per handoff file, 1 MiB across the prompt and visible handoff files, and eight detailed rejection findings. Outbound scans decode Git C-quoted paths and reject sensitive filenames, reviewer-instruction filenames, sensitive Git diff paths, malformed path encodings, binary or non-UTF-8 content, unsafe links, and credential-value shapes. Embedded public exceptions identify only exact synthetic finding spans by detector schema, rule, and digest; a changed span rejects. Rejection diagnostics expose the label, line, and rule but no matched span or span-derived digest. The reply and diagnostic channel rejects credential values while allowing discussion of names such as `.env`.

Migration accepts a managed symlink only when it resolves to the tracked runtime in the clone running the command. When moving clones, run `make unstow` in the old clone, then `make stow` in the new one; any later `make migrate-codex-config` must run from that same clone. If the old clone is unavailable, run the new clone's full cleanup before stowing; normal cleanup recognizes old-clone package links only so they can be removed and restowed from the current clone.

## Verify

After stowing or changing the payloads:

- Run `make verify` and `make lint` from the repo root.
- Start a fresh Claude Code session, confirm auto mode and the shared guidance load, ordinary edits do not hit a per-file prompt, the status line loads, and `spar-codex` is on PATH. Ask it to inspect a harmless external directory and convert one non-text document locally, then confirm synthetic `.env` and `secrets/` paths remain denied.
- Start a fresh Codex session, confirm `trusted-workspace` is active with automatic review, ordinary workspace edits succeed, and `spar-claude` remains deferred rather than escalating through the primary profile. Ask it to inspect a harmless external directory and convert one non-text document locally, approve only turn-scoped filesystem reads, and confirm synthetic `.env` and `secrets/` paths, session scope, writes, and credential access remain unavailable.
- Quit and restart OpenCode, select the xhigh model variant, run `opencode debug config`, and confirm workspace edits and Bash default to allow while native external paths ask and pinned safety operations deny; confirm `share = disabled`, the global `reviewed-writes.ts` plugin remains active, a harmless external directory and non-text document are readable after approval, and native reads of synthetic `.env`, `auth.json`, and `secrets/` paths remain denied.
- Confirm `/commit` routes through the repo skill workflow in all managed tools and presents the fingerprint-bound candidate summary, current skill-owned review instructions, and approval selector before staging without reproducing the diff.
- Confirm `/spar` treats plan and build as primary value-based checkpoints, supports discretionary review elsewhere, and requires evidence-backed Decision Rationale without changing H's plan or commit authority.

## Maintenance

A repo-root `Makefile` keeps the package list in one place and wraps the routine commands. Run targets from the repo root:

- `make stow` / `make unstow` / `make dry-run` / `make restow` - the Stow command sets; `dry-run` previews raw Stow behavior without the non-destructive preparation used by `stow` and `restow`
- `make verify` - exhaustive intended-file deployment; generic external-read policy, scanner, and repository-bound bridge fixtures; fail-closed dependency checks; JSON, TOML, model, Fast, provider, updater, plugin, and host-local package-state contracts; non-destructive Stow fixtures; statusline state-file attack fixtures; bridge payload, authentication, repository isolation, new/resume, terminal-event, signal, timeout, and descendant-cleanup tests; project-config isolation; three-way skill sync and value-based review contracts; commit and reviewer-confinement boundaries; executable all-target plugin parser tests; OpenCode permission ordering; and stray-config checks
- `make clean` - non-destructive preparation that removes only recognized managed symlinks and creates real state directories
- `make lint` - ShellCheck over `statusline.sh`, the directly stowed spar bridges, and every script and shell test; `.shellcheckrc` disables the one style-level finding so new issues stand out

When a tool or plugin crosses a major version, an upstream release note identifies a relevant interface or behavior change, or dependent configuration is being changed, review the current Claude Code docs (settings, memory, skills, hooks), Codex docs (config, AGENTS.md, skills, permission profiles, sandbox, approvals), and OpenCode docs (config, rules, permissions, agents, plugins, skills, TUI, sharing), then run the Verify steps. Restart OpenCode after any config, agent, skill, or plugin change because those files load at process startup. In Claude Code, `/doctor` automates part of this checkup; it reports findings before fixing anything, so screen its offers (such as switching to auto mode) against the pinned defaults before accepting.

## License

[MIT](LICENSE)
