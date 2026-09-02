# Maintenance Ledger

This ledger contains unresolved decisions, deferred work, active limitations, and dated revalidation evidence tied to those items. Remove closed items after folding any lasting constraint into `AGENTS.md`, shared guidance, a skill, a script header, or a test.

## Active Limitations

- Source-checked 2026-09-02 on OpenCode 1.18.26 in `packages/opencode/src/permission/index.ts` and `packages/opencode/src/tool/shell.ts`: OpenCode has no classifier or OS sandbox. Native `grep` and `glob` subjects, the finite Bash path scanner, unrecognized readers, dynamic arguments, wrappers, and scripts leave instruction-governed residuals. Recheck when either source changes.
- Source-checked 2026-09-02 on OpenCode 1.18.26 in `packages/opencode/src/tool/read.ts`, `packages/opencode/src/tool/edit.ts`, `packages/opencode/src/tool/external-directory.ts`, and `packages/core/src/util/wildcard.ts`: read and edit subjects are worktree-relative, while external subjects name parent directories. `~`-keyed read/edit entries and file-level external entries do not match, so the relative `../*tmp/opencode*` deny forms remain required. Recheck before relying on those pins.
- Source-checked 2026-08-15 on OpenCode 1.18.18 in `packages/opencode/src/tool/webfetch.ts`: WebFetch had no equivalent to Claude Code's classifier, hostname canonicalization, resolved-address check, or redirect-aware SSRF boundary. Keep sensitive reads and shell network separately restricted; recheck when that source changes.
- Source-checked 2026-09-01 on OpenCode 1.18.25: upstream `packages/opencode/src/tool/apply_patch.ts` applies accepted operations sequentially after `reviewed-writes.ts` validates them, so same-user path replacement between validation and write remains a TOCTOU residual. Recheck both when either changes.
- The spar payload scanner recognizes a finite set of credential formats, and the reviewer reads repository files directly. Repository consent, not the scanner, is the disclosure decision.
- Observed 2026-09-01 on OpenCode 1.18.25: an explicitly selected TUI model variant persisted across restarts and overrode configured base effort. Confirm xhigh in the selector when effective effort matters.
- OpenCode-to-Claude spar last failed live on 2026-09-02 (Claude Code 2.1.258) because the reviewer could not read its handoff directory. The bridge now inlines artifacts into the prompt, which removes that path; run one live `spar-claude review` from OpenCode with an artifact before treating the route as available.

## Open Decisions

- Decide whether an Omarchy-only Claude Code sandbox trial justifies tracked promotion. The untracked trial denies `~/.ssh`, `~/.aws`, and `~/.gnupg`, asks before `dangerouslyDisableSandbox`, checks command classification and repository writes, and requires a separate WSL behavior test. Relevant upstream issues: anthropics/claude-code#43713, #26722, and #54215.
- Decide ownership of host-created `diagnose-crash` and `omarchy` links under `~/.agents/skills` before managing or removing them.
- Decide whether Claude settings should define `fallbackModel`; the current judgment is no, because a silent downgrade conflicts with the durable Fable alias.

## Deferred Work

- Complete the WSL host pass: inspect status and diff before pulling, and obtain H's approval before discarding any local edits to the retired `codex/.codex/config.toml`; keep config content out of chat and logs; run `make migrate-codex-config`, which seeds the host-local Codex config from the template because the old managed link dangles, then re-enable any desktop-app plugins locally; run `make restow` from the supplying clone, which unfolds the old directory links and removes dangling managed links; run `make verify`; add a WSL-compatible Codex installation; confirm OpenCode's app-temp root.
- Run `/fewer-permission-prompts` against accumulated host transcripts and promote only durable read-only rules. Keep `gh api` excluded.
- Run fresh primary external-read canaries for Claude Code and Codex when each tool is next started.
- Revisit native cross-model review when a managed tool provides a suitable read-only cross-vendor path under subscription authentication.
- Keep Codex-to-Claude review manual outside the strict Codex profile until its root-denied permissions can grant the required Claude runtime and state without weakening the primary sandbox.

## Revalidation Triggers

- Routine client releases require no ledger update. Revalidate when a dependent interface, permission rule, temp root, matcher, model catalog, or observed behavior changes.
- Re-run `make test` after changing a bridge, the scanner, a permission profile, or their runtime dependencies; re-run one live review per bridge after changing reviewer flags or when `claude -p` or `codex exec` behavior changes.
- Re-run Codex root-deny, workspace, network, plugin-isolation, and resumed-session checks after changing its permission profile or runtime boundaries.
- Re-run OpenCode project-isolation, plugin, package-state, app-temp, grouped-patch, and permission-subject checks after a relevant OpenCode or plugin API change.
- Use `claude --version` for Claude Code evidence and `mise ls --current` for Codex and OpenCode evidence so stateful wrappers are not invoked.
