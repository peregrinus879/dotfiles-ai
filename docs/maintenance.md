# Maintenance Ledger

This ledger contains unresolved decisions, deferred work, active limitations, and dated revalidation evidence tied to those items. Remove closed items after folding any lasting constraint into `AGENTS.md`, shared guidance, a skill, a script header, or a test.

## Active Limitations

- Source-checked 2026-09-02 on OpenCode 1.18.26 in `packages/opencode/src/permission/index.ts` and `packages/opencode/src/tool/shell.ts`: OpenCode has no classifier or OS sandbox. Native `grep` and `glob` subjects, the finite Bash path scanner, unrecognized readers, dynamic arguments, wrappers, and scripts leave instruction-governed residuals. Recheck when either source changes.
- Source-checked 2026-09-02 on OpenCode 1.18.26 in `packages/opencode/src/tool/read.ts`, `packages/opencode/src/tool/edit.ts`, `packages/opencode/src/tool/external-directory.ts`, and `packages/core/src/util/wildcard.ts`, and 2026-09-03 in `packages/opencode/src/tool/apply_patch.ts`: read and edit subjects are worktree-relative, external subjects name parent directories, and `apply_patch` runs the external-directory assertion per target before writing. Recheck the permission-subject invariant in `AGENTS.md` when any of those sources changes.
- Source-checked 2026-08-15 on OpenCode 1.18.18 in `packages/opencode/src/tool/webfetch.ts`: WebFetch had no equivalent to Claude Code's classifier, hostname canonicalization, resolved-address check, or redirect-aware SSRF boundary. Keep sensitive reads and shell network separately restricted; recheck when that source changes.
- The spar payload scanner recognizes a finite set of credential formats, and the reviewer reads repository files directly. Repository consent, not the scanner, is the disclosure decision.
- Observed 2026-09-01 on OpenCode 1.18.25: an explicitly selected TUI model variant persisted across restarts and overrode configured base effort. Confirm xhigh in the selector when effective effort matters.
- OpenCode-to-Claude spar last failed live on 2026-09-02 (Claude Code 2.1.258) because the reviewer could not read its handoff directory. The bridge now inlines artifacts into the prompt, which removes that path; run one live `spar-claude review` from OpenCode with an artifact before treating the route as available.

## Open Decisions

- Decide whether an Omarchy-only Claude Code sandbox trial justifies tracked promotion. The untracked trial denies `~/.ssh`, `~/.aws`, and `~/.gnupg`, asks before `dangerouslyDisableSandbox`, checks command classification and repository writes, and requires a separate WSL behavior test. Relevant upstream issues: anthropics/claude-code#43713, #26722, and #54215.
- Decide ownership of host-created `diagnose-crash` and `omarchy` links under `~/.agents/skills` before managing or removing them.
- Decide whether Claude settings should define `fallbackModel`; the current judgment is no, because a silent downgrade conflicts with the durable Fable alias.

## Deferred Work

- WSL host pass, for the agent to run in a session opened in the WSL clone, stopping at the first mismatch:
  - Confirm the host: `/proc/version` names Microsoft, and `readlink -f ~/.claude/settings.json` resolves into this clone.
  - Run `git status --short` and `git diff --stat`. If `codex/.codex/config.toml` carries local edits, show H the hunks and obtain a ruling before anything is discarded; keep config content out of chat and logs.
  - `git pull --ff-only`.
  - `make restow`; report the dangling links it removed and confirm `~/.claude`, `~/.claude/rules`, `~/.claude/skills/*`, `~/.agents/skills/*`, and `~/.config/opencode` are real directories. The old managed Codex link dangles, so expect `installed host-local Codex config from the template` and a mode-600 regular file; H then re-enables desktop-app plugins locally.
  - `make verify`.
  - Confirm `codex --version` runs; if Codex is not installed, add it through the same manager as Omarchy (`mise ls --current`) and record the version.
  - Confirm OpenCode's default temp root is `/tmp/opencode`, which the `external_directory` allow depends on.
  - One live `spar-codex review` from Claude Code and one live `spar-claude review` from OpenCode, each with a small artifact in this repository; record the result here and close the OpenCode-to-Claude limitation above if the second one reads its artifact.
  - Report `claude --version`, `mise ls --current`, and `stat -c '%a %h' ~/.codex/config.toml` as the evidence, then remove this item.
- Run `/fewer-permission-prompts` against accumulated host transcripts and promote only durable read-only rules. Keep `gh api` excluded.
- Run fresh primary external-read canaries for Claude Code and Codex when each tool is next started.
- Revisit native cross-model review when a managed tool provides a suitable read-only cross-vendor path under subscription authentication.
- Keep Codex-to-Claude review manual outside the strict Codex profile until its root-denied permissions can grant the required Claude runtime and state without weakening the primary sandbox.

## Revalidation Triggers

- Routine client releases require no ledger update. Revalidate when a dependent interface, permission rule, temp root, matcher, model catalog, or observed behavior changes.
- Re-run `make test` after changing a bridge, the scanner, a permission profile, or their runtime dependencies; re-run one live review per bridge after changing reviewer flags or when `claude -p` or `codex exec` behavior changes.
- Re-run Codex root-deny, workspace, network, plugin-isolation, and resumed-session checks after changing its permission profile or runtime boundaries.
- Re-run OpenCode project-isolation, app-temp, and permission-subject checks after a relevant OpenCode change; the project-disabled launch in `README.md` depends on `OPENCODE_DISABLE_PROJECT_CONFIG` and `OPENCODE_DISABLE_EXTERNAL_SKILLS` continuing to exist.
- Use `claude --version` for Claude Code evidence and `mise ls --current` for Codex and OpenCode evidence so stateful wrappers are not invoked.
