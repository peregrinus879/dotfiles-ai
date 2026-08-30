# EyrAgents

Claude Code, Codex, and OpenCode global dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Eyrie is the shared project habitat, reflected locally in `~/Projects/eyrie/`. `Eyr` is its shortened family prefix, used by EyrAgents, EyrArcHy, and EyrWSL.

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
            ├── .gitignore                # excludes generated node_modules
            ├── opencode.json             # runtime config and agent overrides
            ├── tui.json                  # TUI-specific config
            ├── commands/                 # custom slash commands
            │   ├── commit.md             # wrapper for the commit skill
            │   └── spar.md               # wrapper for the spar skill
            ├── plugins/                  # one-file patch and handoff safety plugin
            ├── package.json              # compatible-major plugin dependency
            ├── package-lock.json         # reproducible npm dependency graph
            ├── skills/                   # agent skills
            │   ├── commit/               # candidate and publication review workflow
            │   └── spar/                 # cross-model sparring and reviews (reviewer: spar-claude)
```

Tracked `.gitkeep` placeholders (claude-code agents; opencode agents, themes, and tools) are omitted from the tree.

Tracked runtime config primarily expresses shared behavior. `claude-code/.claude/settings.json`, `codex/.codex/config.toml`, and `opencode/.config/opencode/opencode.json` are the source of truth for each tool's model, effort, permissions, and feature toggles; read them directly rather than a prose mirror here. Trusted-repository work is autonomous until the commit boundary: Claude Code uses auto mode, Codex uses a write-capable workspace profile plus automatic approval review, and OpenCode allows workspace edits and shell commands behind explicit sensitive, external, destructive, privileged, upload, and remote-mutation denials. OpenCode has no classifier or OS sandbox, so wrappers and scripts remain a documented residual. Every commit requires H's editor review and approval of the exact candidate before staging. Session handoffs use private disk-backed OS temp (`/var/tmp/spar-<session-id>/`) so an in-flight review survives reboots; the Claude hook and OpenCode plugin validate handoff writes without reintroducing ordinary per-file prompts. OpenCode `tui.json` keeps a stacked diff view that works better in narrow terminals.

The three reviewer executables are ordinary Stow-managed payloads. Each bridge scans the prompt and handoff and validates repository path names before authentication; rejects Git-control variables, repository hard-linked files outside denied directories, nested repository mounts, and path shapes that its read-deny policy cannot cover; launches its subscription reviewer from the caller's canonical Git root; and grants read-only access to that repository plus the exact handoff. Later native permission rules deny Git internals, credential-shaped paths, and the bridge-owned `reviewer-id`; repository files outside those denies may reach the reviewer, including private-repository files.

Primary web research follows Claude auto mode's outcome. Claude remains explicitly pinned to auto and sends unmatched WebSearch and WebFetch calls through its classifier. Codex uses hosted live search and page opening without granting network to shell commands. OpenCode allows WebSearch and WebFetch without prompts; its WebFetch implementation has no Claude-equivalent classifier or resolved-address SSRF boundary, so the sensitive-read denies and prohibition on sending repository content remain material controls. Both spar reviewers stay search-disabled.

Codex, OpenCode, and `spar-codex` use GPT-5.6 Sol Fast. Codex represents this as model `gpt-5.6-sol` plus `service_tier = "fast"` and `features.fast_mode = true`; the ChatGPT-authenticated Codex API rejects `gpt-5.6-sol-fast` as a model slug. Its primary uses Ultra reasoning and automatic summaries, while built-in subagents default to Sol/Max and inherit Fast from the parent session. OpenCode exposes the equivalent `openai/gpt-5.6-sol-fast` alias, whose tracked definition resolves to API model `gpt-5.6-sol`, Priority service, and base options for Max reasoning and automatic summaries. An explicitly selected TUI variant persists and takes precedence over those base options; primary agents use the global default and subagents inherit the invoking primary model. The single-agent `spar-codex` reviewer uses Max and suppresses summaries because its bridge discards them. The managed configuration assumes ChatGPT subscription authentication, where Fast consumes GPT-5.6 credits at 2.5 times the Standard rate. ChatGPT Pro raises included Codex limits but does not enable Responses API Pro reasoning mode; API-key use invokes separately billed processing and requires a separate configuration and billing decision.

Claude Code requests Fable 5 with maximum effort through `CLAUDE_CODE_EFFORT_LEVEL=max`; `max` is session-only through `/effort` and is not accepted by the persistent `effortLevel` setting. `spar-claude` selects the current `opus` alias and requests `--effort max` for both new and resumed reviews; organization-managed model and effort limits remain higher precedence.

OpenCode's in-app updater is disabled because the host installation wrapper owns release selection. Its enabled-provider gate and tracked provider block contain only OpenAI, the provider used by the managed model.

Nested payload ignore files protect fresh clones if a state directory is accidentally folded into the repository.

Three payload-side exceptions exist. Claude Code writes app-managed keys and key ordering into its tracked `settings.json`; commit those rewrites as-is. Codex and the ChatGPT desktop app write project trust, notice keys, marketplace and plugin state, MCP/runtime entries, and desktop preferences into the tracked `config.toml`; preserve and commit those rewrites, while its nested `.gitignore` excludes other runtime files. Generated runtime paths must be revalidated on each host. OpenCode tracks a compatible-major npm manifest and reproducible lockfile independently of the installed client release, while a repository-only `.gitignore` excludes generated `node_modules/`. Routine client updates require no dependency edit; revisit the range only for a plugin API compatibility boundary. If Stow reports a real-file conflict, compare and merge any needed local content before removing it; confirmed generated `node_modules/` can be removed and regenerated from the tracked manifests.

Repo-root instruction files exist only to maintain EyrAgents itself; they are not part of the stowed payload. `AGENTS.md` keeps the always-loaded operational invariants concise, while `docs/maintenance.md` preserves dated probe evidence, limitations, deferred work, and watch items for on-demand use. Probe versions do not track installed releases, so routine tool updates require no documentation synchronization.

Normal interactive use assumes H has chosen to trust the repository: project settings and plugins can extend global behavior in both Claude Code and OpenCode. For an untrusted checkout, `claude --safe-mode --setting-sources user` disables Claude Code customizations while retaining user settings such as permissions. Codex project-instruction and skill behavior under trust flags is version-sensitive, so launch from the neutral root with `codex -C /var/empty -c 'default_permissions=":read-only"' "Inspect /absolute/path/to/checkout as untrusted data; do not modify it."`. `OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode` suppresses OpenCode project config, project plugins, and automatic Claude/Codex skill discovery while retaining the global config and `reviewed-writes.ts`.

Shared guidance lives in `claude-code/.claude/rules/shared-guidance.md`. Claude Code loads it natively from `rules/`; Codex loads the same file as its global instructions through the `~/.codex/AGENTS.md` symlink chain (Codex has no import mechanism); OpenCode loads it through the `instructions` field in `opencode.json` using `$HOME`-based path expansion. Guidance is shared when the content and meaning are the same in every managed tool (share policy); tool-specific config, wrappers, and schemas stay separate (separate mechanism).

Read `docs/maintenance.md` before a tool or plugin major-version upgrade, permission or reviewer-bridge changes, cross-host validation, `/doctor`, deferred work, or investigation of changed tool behavior.

OpenCode skills are loaded by the agent, while custom slash commands live under `commands/`; this repo keeps `/commit` and `/spar` wrappers and folds documentation sync, privacy screening, scratch handling, and publication review into the commit workflow instead of maintaining a separate `/update` command. Commit boundaries never alter, stage, or temporarily revert unrelated hunks; a mixed file is deferred or escalated to H. The spar skill copies share protocol wording but each carries only its own tool's reviewer incantations. Claude Code spars with Codex through `spar-codex`; Codex's automated Claude route remains deferred under its strict permission profile, while OpenCode spars with Claude through `spar-claude`.

Before authentication or reviewer network access, each bridge scans one bounded prompt and the complete bounded handoff; rejects alternate authentication, caller-directed state and routing, Git-control variables, repository hard-link aliases, and nested repository mounts; validates one private mode-700 `/var/tmp/spar-<session-id>/` directory; canonicalizes the caller's Git root; and resolves the reviewer executable once before changing directories. The bridge writes six-field timestamp, bridge, role, state, id, and repository-root records to `reviewer-id`; prior manifest shapes and cross-repository resumes fail closed, and cold sessions never resume. `spar-codex` ignores user config and rules, marks the active project untrusted, sets project-instruction bytes to zero with no fallback filenames, suppresses skill catalogs, disables plugins, and preflights an empty effective plugin inventory. Its inline OS profile denies root and temp, grants runtime-minimal paths plus the repository and handoff read-only, narrows those grants with Git, credential-path, and manifest denies, rejects repository entries beyond the 64-level deny-glob bound, and disables command network. `spar-claude` selects the current `opus` alias, adds the handoff to the repository launch, uses safe mode with no user, project, or local setting sources or extension tools, combines `dontAsk` with explicit repository and handoff read allows plus later sensitive-path denies, exposes only `Read`, `Glob`, and `Grep`, validates every served-model key as Opus-family, and disables nonessential traffic and updater activity; higher-precedence managed policy remains in force. A call succeeds only after one valid terminal event for the requested session or thread with a nonempty locally rescanned reply. Bounded Codex diagnostics use the reply scanner before relay. Each bridge owns the reviewer process group so repeated signals, stalls, ceilings, and normal exits terminate remaining descendants before returning.

Filesystem-root repositories fail before any read grant. Claude authentication preflight uses the review's safe-mode setting-source isolation and rejects ambient third-party provider, endpoint, and auth-skip controls; absolute account-home credential denies remain later than any overlapping repository allow. Codex accepts its disabled-plugin preflight only when `installed` is structurally an empty array. Failure cleanup removes private diagnostic work before best-effort identifier reporting.

Repository path preflight validates every canonical-root component's spelling and every repository entry name it enumerates without reading file contents. It prunes the repository-root `.git` and exact repository-root `secrets` subtrees and does not follow directory symlinks. It rejects nested `.git` directories, sensitive directory names that lack an exact subtree deny, sensitive-named symlinks, symlinks below nested `secrets` trees whose deny depends on glob expansion, case variants of sensitive names, non-UTF-8 names, and names containing control characters, quotes, or backslashes. Ordinary public symlinks remain reviewable. Hard-link validation prunes only the root Git metadata subtree and exact lowercase `secrets` directories. The scanner parses LF-delimited Git records and strictly decodes C-quoted paths before applying the same sensitive-name grammar to every path component used by the reviewer policies and native handoff-write gates.

OpenCode's host environment disables automatic external skill discovery so its managed commit and spar copies are selected instead of the colliding Claude and Codex copies. The tracked `skills.paths` restores only the Omarchy skill. The Omarchy `.bashrc` owner covers terminal-first interactive descendants; non-interactive OpenCode launchers must set `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` themselves.

Reviewers stay offline: Codex reviewer web search and network are disabled, and the Claude reviewer has no web tools. This prevents query-based exfiltration, reduces external prompt-injection exposure, and keeps reviews reproducible. The implementer verifies material current external claims against primary sources and gives every substantive review the target, evidence, and a Decision Rationale covering the research, alternatives, tradeoffs, H's rulings, authorized changes, and remaining uncertainty. The reviewer challenges concrete defects in that reasoning or its implementation rather than repeating settled research merely because another approach exists. The implementer chooses blind or fully briefed, fresh or resumed, single or iterative review according to expected value. Any issue left for H arrives as a self-contained ruling packet with both positions, evidence, consequences, reversibility, affected work, and the implementer's labeled recommendation; raw reviewer transcripts remain optional.

The spar workflow supports brainstorming, plan, build, and diff-only review. Plan and build are the primary checkpoints, not mandatory gates: plan review fits after research and analysis and before the final plan is presented, while build review fits after approved commits and compares the starting-base-to-HEAD result with the latest approved plan and Decision Rationale. The implementer may spar at any other point and chooses the review shape and depth from expected value, risk, uncertainty, independence, and cost. Atomic implementation units retain the exact human commit boundary without automatic per-unit reviewer gates. Reviewer convergence never authorizes a commit or push; unresolved evidence, scope, or value judgments return to H without discarding the worktree.

Status line state-file conventions live in the `statusline.sh` header and the AGENTS.md invariant.

## Review Workflow

Before every commit, the assistant repeats this complete compact cheat sheet. Open a separate terminal pane at the repository root and review the candidate in the installed Omarchy LazyVim:

1. `nvim .`, then `<Space>gd`: open the tracked diff picker.
2. `<M-w>`: cycle the input, hunk list, and preview panes. `<C-n>`/`<C-p>` or arrows: move between hunks; the highlight updates the preview.
3. `<M-p>`: toggle the preview. `<M-m>`: maximize or restore the active picker pane.
4. `<Enter>`: open the selected file and close the picker. `<Space>sR`: resume after opening a file. `<Esc>`: close without opening.
5. `<Space>gs`: open Git Status for intended untracked files. Highlight a file for its preview; use `<Enter>` only when it must be opened, then `<Space>sR` to resume.
6. Avoid `<Tab>`, which stages, and `<C-r>`, which restores, in both Git pickers.

The assistant first screens the proposed message, paths, complete diff, and intended new-file contents against the intended audience, defaulting to world-readable publication. Its selector offers `Approve, commit, continue (Recommended)`, `Approve, commit, discuss`, `Revise`, and `Reject`; the built-in custom answer is the comment path. Either approve choice authorizes staging and one commit of the exact packet. Continue proceeds only with remaining work already covered by H's active request or approved plan; discuss pauses after commit verification and status. Revise and any replacement after rejection require a refreshed packet, while a custom comment changes nothing and repeats the unchanged candidate after the answer.

After all approved units, the managed `/commit` workflow withholds any publication-ready claim or push hint until it reviews the exact history and artifacts the destination, audience, ref set, and effective operation would expose. Destination state narrows the review only when confirmed current and enforced as an execution-time expected value; otherwise the complete history of the published refs is reviewed. Coverage includes commit and annotated-tag metadata, path names, intermediate or later-deleted planning, review, and documentation versions, referenced Git LFS objects, every action-metadata field and value, every action body and asset digest, configured push options, and active client-side hooks. Paths are inventoried before content, Safety-barred or opaque artifacts remain unread, and every record reconciles to reviewed content, an exact H ruling, or a blocker. H inspects an unreadable artifact in a separate terminal pane, never through `!` or pasted session content. The result reports its credential-free logical destination, immutable source IDs and asset digests, exact operation, destination-state freshness, coverage, rulings, and omissions; endpoint credentials and transient authenticated transfer URLs never enter the descriptor. Any bound-value change, unresolved implicit behavior, or incomplete coverage invalidates it. Code review and secret scanning remain separate checks.

Read-only terminal fallback: `git status --short` lists the candidate, `git diff --stat HEAD` summarizes it, `git diff HEAD` shows the complete tracked diff, and `git diff HEAD -- path/to/file` isolates one path.

## Setup

### Prerequisites

- [GNU Stow](https://www.gnu.org/software/stow/)
- jq, Python, and Node.js (event parsing, semantic contracts, payload scanning, and plugin tests)
- ShellCheck (shell linting)
- GNU coreutils (`readlink`, `realpath`, `sha256sum`, and `stat`; included in the Arch base system)
- util-linux (`setsid` and `findmnt`; included in the Arch base system) and GNU `timeout`

```bash
sudo pacman -S --needed stow jq nodejs python shellcheck
```

### Clone

Recommended local layout for this repo family:

```text
~/Projects/eyrie/eyragents
```

Stow can work from any clone location, but the related docs and cross-repo maintenance workflows assume this layout.

```bash
git clone https://github.com/peregrinus879/eyragents.git ~/Projects/eyrie/eyragents
```

### Prepare

Checklist before stowing:

- Stow is installed
- EyrAgents was cloned locally
- Any existing conflicting config files were compared and their needed content was merged or adopted

From the repository root, prepare the state directories and remove only symlinks that resolve to this package layout:

```bash
make clean
```

The cleanup preflights every endpoint before changing anything. It refuses regular files, directories at managed leaf endpoints, and symlinks outside the recognized package layout. It keeps `~/.claude`, `~/.claude/skills`, `~/.codex`, `~/.agents`, `~/.agents/skills`, `~/.local`, and `~/.local/bin` as real directories, and ensures `~/.config` is real. If `~/.config/opencode` is absent, Stow may tree-fold it into one package symlink; an existing real directory receives managed child links instead.

If a real `~/.config/opencode/node_modules` directory blocks preparation, confirm it is generated dependency output, remove it, and regenerate it from the tracked `package.json` and `package-lock.json` after stowing.

Codex stores per-host project trust inside `config.toml`. If `~/.codex/config.toml` already exists, merge its `[projects]` entries into `codex/.codex/config.toml` before stowing, then remove the real file; do not simply delete it.

### Stow

The Makefile owns the package list and the stow command sets; run the targets from the repo root:

```bash
make stow      # create symlinks for all packages
make unstow    # remove all package symlinks
make dry-run   # preview stow actions without making changes
make restow    # update symlinks after repo content changes
```

Each target uses the ordinary package invocation:

```bash
stow -v -t ~ claude-code codex opencode
```

The three `~/.local/bin/spar-*` endpoints resolve directly to their package files, whether Stow creates leaf links or folds a parent directory.

### Reviewer Bridges

Run `spar-claude init` or `spar-codex init` from the repository that will be reviewed. The returned handoff is bound to that canonical Git root immediately. Git-control environment variables, repository hard-linked files outside denied directories, nested repository mounts, unsupported repository path spellings or sensitive directories without an exact subtree deny, unrepresentable permission-pattern roots, and Codex repository entries deeper than its deny-glob bound fail closed. Add the exact target and supporting material with native file tools, run the same bridge's `flush` mode after every write, then use `new` or `resume` as documented by the `/spar` skill. The reviewer receives the repository and handoff read-only but cannot read `reviewer-id`, Git internals, or the configured credential-shaped paths.

The scanner permits at most a 256 KiB prompt, 128 handoff entries, 512 KiB per handoff file, 1 MiB across the prompt and visible handoff files, and eight detailed rejection findings. Outbound scans decode Git C-quoted paths and reject sensitive filenames, reviewer-instruction filenames, sensitive Git diff paths, malformed path encodings, binary or non-UTF-8 content, unsafe links, and credential-value shapes. Embedded public exceptions identify only exact synthetic finding spans by detector schema, rule, and digest; a changed span rejects. Rejection diagnostics expose the label, line, and rule but no matched span or span-derived digest. The reply and diagnostic channel rejects credential values while allowing discussion of names such as `.env`.

To migrate from a different clone path, run `make unstow` in the old clone first, then `make stow` in the new one. If the old clone is no longer available, run the full cleanup in the Prepare section before stowing.

## Verify

After stowing or changing the payloads:

- Run `make verify` and `make lint` from the repo root.
- Start a fresh Claude Code session, confirm auto mode and the shared guidance load, confirm ordinary edits do not hit a per-file prompt, confirm the status line loads, and confirm `spar-codex` is on PATH.
- Start a fresh Codex session, confirm the shared guidance loads, `trusted-workspace` is active with automatic review, ordinary workspace edits succeed, and `spar-claude` remains deferred rather than escalating through the primary profile.
- Start a fresh OpenCode session, run `opencode debug config`, and confirm workspace edits and Bash default to allow while external paths and pinned safety operations deny; confirm `share = disabled` and the global `reviewed-writes.ts` plugin remain active.
- Confirm `/commit` routes through the repo skill workflow in all managed tools and presents the exact candidate, LazyVim instructions, and approval selector before staging.
- Confirm `/spar` treats plan and build as primary value-based checkpoints, supports discretionary review elsewhere, and requires evidence-backed Decision Rationale without changing H's plan or commit authority.

## Maintenance

A repo-root `Makefile` keeps the package list in one place and wraps the routine commands. Run targets from the repo root:

- `make stow` / `make unstow` / `make dry-run` / `make restow` - the stow command sets
- `make verify` - exhaustive intended-file deployment; bounded scanner and repository-bound bridge fixtures; fail-closed dependency checks; JSON, TOML, model, Fast, provider, updater, and npm-lock contracts; non-destructive Stow fixtures; statusline state-file attack fixtures; bridge payload, authentication, repository isolation, new/resume, terminal-event, signal, timeout, and descendant-cleanup tests; project-config isolation; three-way skill sync and value-based review contracts; commit and reviewer-confinement boundaries; executable one-file plugin parser tests; OpenCode permission ordering; and stray-config checks
- `make clean` - non-destructive preparation that removes only recognized managed symlinks and creates real state directories
- `make lint` - ShellCheck over `statusline.sh`, the directly stowed spar bridges, and every script and shell test; `.shellcheckrc` disables the one style-level finding so new issues stand out

When a tool or plugin crosses a major version, an upstream release note identifies a relevant interface or behavior change, or dependent configuration is being changed, review the current Claude Code docs (settings, memory, skills, hooks), Codex docs (config, AGENTS.md, skills, permission profiles, sandbox, approvals), and OpenCode docs (config, rules, permissions, agents, plugins, skills, TUI, sharing), then run the Verify steps. Restart OpenCode after any config, agent, skill, or plugin change because those files load at process startup. In Claude Code, `/doctor` automates part of this checkup; it reports findings before fixing anything, so screen its offers (such as switching to auto mode) against the pinned defaults before accepting.

## License

[MIT](LICENSE)
