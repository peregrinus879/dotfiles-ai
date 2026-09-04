# Maintenance Ledger

Unresolved decisions, deferred work, active limitations, and the dated evidence behind them. Durable rules live in `AGENTS.md`, shared guidance, a skill, a script header, or a test; remove an item here once its rule has moved there.

## Active Limitations

- OpenCode permissions (source-checked 2026-09-02 on 1.18.26: `permission/index.ts`, `tool/shell.ts`, `tool/read.ts`, `tool/edit.ts`, `tool/external-directory.ts`, `tool/apply_patch.ts`, `core/src/util/wildcard.ts`): no classifier or OS sandbox; read and edit subjects are worktree-relative, external subjects are parent directories, and `apply_patch` asserts each target before writing. Live-checked 2026-09-03: destructive Git and remote changes prompt, and `.git` edits, `~/.ssh` reads, and pushes are refused. Recheck the `AGENTS.md` invariants when those sources change.
- OpenCode WebFetch (source-checked 2026-08-15 on 1.18.18, `tool/webfetch.ts`) has no SSRF boundary; sensitive reads and shell network stay separately restricted. Recheck when that source changes.
- The payload scanner recognizes a finite set of credential shapes; repository consent, not the scanner, is the disclosure decision.
- Codex sandbox (observed 2026-09-03 on 0.152.1): a literal denied workspace path creates an empty placeholder file wherever the path is absent, and a home-wide glob that matches inside an already denied directory or a runtime tree (`~/**/id_ed25519`, `~/**/.npmrc`) aborts or stalls startup. Profiles use `**/` globs in the workspace and deny directories, not their contents, under `$HOME`; recheck when the sandbox changes.
- OpenCode TUI (observed 2026-09-01 on 1.18.25): a selected model variant persists across restarts and overrides the configured effort; confirm xhigh in the selector when it matters.
- OpenCode-to-Claude spar last failed live on 2026-09-02 because the reviewer could not read its handoff directory, a path the bridge no longer uses. One live `spar-claude review` from OpenCode with an artifact closes this item.
- Claude Code status line (source-checked 2026-09-03 on 2.1.259, the newest release): the `rate_limits` payload carries only `five_hour`, `seven_day`, and the gateway `spend_limit`. The per-model Fable weekly window, tracked internally as `seven_day_overage_included` and shown by `/usage` as "Current week (Fable)", is not exposed, and the only client-side route to it calls the usage API with the token in the credential store, which the security boundaries forbid. Add a `fable:` segment after `7d:` when a release exposes that window; recheck when the status line docs or a changelog entry mention `rate_limits`.

## Open Decisions

- Whether an Omarchy-only Claude Code sandbox trial justifies tracked promotion. The untracked trial denies `~/.ssh`, `~/.aws`, and `~/.gnupg`, asks before `dangerouslyDisableSandbox`, checks command classification and repository writes, and needs a separate WSL behavior test. Upstream: anthropics/claude-code#43713, #26722, #54215.
- Whether Claude settings should define `fallbackModel`; current judgment is no, because a silent downgrade conflicts with the durable Fable alias.
- `features.js_repl = false` in the Codex template has no recorded reason; revisit when a task would benefit from the REPL.

## Deferred Work

- WSL host pass, for the agent to run in a session opened in the WSL clone, stopping at the first mismatch:
  - Confirm the host: `/proc/version` names Microsoft, and `readlink -f ~/.claude/settings.json` resolves into this clone.
  - `git status --short` and `git diff --stat`; if `codex/.codex/config.toml` carries local edits, show H the hunks and obtain a ruling before anything is discarded, keeping config content out of chat and logs.
  - `git pull --ff-only`. The pull retires `codex/.agents`, so the links `~/.agents/skills/{commit,publish,spar}/SKILL.md` dangle and `make clean` cannot recognize them: confirm each link's text ends in `codex/.agents/skills/<name>/SKILL.md`, remove those three links, then `make restow`: report the dangling links it removed, confirm the managed parents are real directories, expect the `agents` package to deploy `~/.agents/shared-guidance.md` and the three skills, and expect the Codex config to be installed from the template as a mode-600 file carrying the `~/.agents/shared-guidance.md` read grant, after which H re-enables desktop-app plugins locally. Restart OpenCode, whose `instructions` path moved to `~/.agents/shared-guidance.md`.
  - `make verify`; confirm `codex --version` runs from the official `openai-codex` package, that the Codex sandbox can start `/usr/bin/codex`, and that `spar-claude` resolves `~/.claude/bin/claude` outside the repository and the temp roots; confirm OpenCode's temp root is `/tmp/opencode`.
  - One live `spar-codex review` from Claude Code and one live `spar-claude review` from OpenCode, each with a small artifact; close the OpenCode-to-Claude limitation if the second reads its artifact.
  - In the eyrwsl clone, `make restow` and `make verify`: the first run of its host and clone guards and of `verify` folding in `lint` and `check`.
  - Report `claude --version`, `codex --version`, and `stat -c '%a %h' ~/.codex/config.toml`, then remove this item.
- Rename the skills with an `eyr` prefix so they cannot collide with built-in or plugin commands; the form is undecided, H preferring the joined `eyrcommit` over `eyr-commit`. The rename touches the skill directories in the `agents` package and their Claude Code and OpenCode symlinks, the OpenCode command wrappers, the Codex template read grants, the `tests/prepare-stow.sh` fixture, and every cross-reference; deploy with `make clean`, `make restow`, and `make verify`, then remove the emptied skill directories under `$HOME`.
- Give omasecboot a `check` target that runs `test`, so the gate contract covers it; wait until H's current work there is done.
- Move the remaining shared executables to the neutral home the way the gate moved: `spar-payload-scan` and the two bridges live in the Claude Code and Codex packages but serve every tool, so they belong in the `agents` package; decide with that whether executables stay in `~/.local/bin`, which is on PATH, or `~/.agents/bin` joins PATH through the sibling shells.
- Run `/fewer-permission-prompts` against accumulated host transcripts and promote only durable read-only rules; keep `gh api` excluded.
- Run fresh primary external-read canaries for Claude Code and Codex when each tool is next started.
- Revisit native cross-model review when a managed tool offers a read-only cross-vendor path under subscription authentication.
- Keep Codex-to-Claude review manual outside the strict Codex profile until its root-denied permissions can grant the Claude runtime and state without weakening the primary sandbox.

## Revalidation Triggers

- When a Claude Code release reads `AGENTS.md` or `~/.agents/skills` natively (announced by Anthropic in late August 2026 as "more hackable", without a date): run `/context` and `/skills` for a guidance file loaded twice or duplicate skill entries, then remove the root `CLAUDE.md` import shim or the `claude-code/.claude/skills` symlinks accordingly.
- In the first Codex session and the first OpenCode session on each host after the commit gate landed: ask the tool to run a plain `git commit` and expect the denial. The fixture test proves the hook command, payload, and plugin call, not the vendor's own dispatch of them; record the result here and remove this item.
- Routine client releases need no ledger update; revalidate when a dependent interface, permission rule, temp root, matcher, model catalog, or observed behavior changes. Evidence uses `claude --version` and `mise ls --current` so stateful wrappers are not invoked.
- Re-run `make check` after changing a bridge, the scanner, a permission profile, or their runtime dependencies; re-run one live review per bridge after changing reviewer flags or when `claude -p` or `codex exec` behavior changes.
- Re-run the Codex root-deny, workspace, network, plugin-isolation, and resumed-session checks after changing its permission profile or runtime boundaries.
- Re-run the OpenCode project-isolation, app-temp, and permission-subject checks after a relevant OpenCode change; the project-disabled launch in `README.md` depends on `OPENCODE_DISABLE_PROJECT_CONFIG` and `OPENCODE_DISABLE_EXTERNAL_SKILLS` continuing to exist.
