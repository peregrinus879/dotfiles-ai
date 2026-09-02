# Maintenance Ledger

This ledger contains unresolved decisions, deferred work, active limitations, and dated revalidation evidence tied to those items. Remove closed items after folding any lasting constraint into `AGENTS.md`, shared guidance, a skill, a script header, or a test.

## Active Limitations

- Source-checked 2026-09-02 on OpenCode 1.18.26 in `packages/opencode/src/permission/index.ts` and `packages/opencode/src/tool/shell.ts`: OpenCode has no classifier or OS sandbox. Native `grep` and `glob` subjects, the finite Bash path scanner, unrecognized readers, dynamic arguments, wrappers, and scripts leave instruction-governed residuals. Recheck when either source changes.
- Source-checked 2026-09-02 on OpenCode 1.18.26 in `packages/opencode/src/tool/read.ts`, `packages/opencode/src/tool/edit.ts`, `packages/opencode/src/tool/external-directory.ts`, and `packages/core/src/util/wildcard.ts`: read and edit subjects are worktree-relative, while external subjects name parent directories. `~`-keyed read/edit entries and file-level external entries do not match, so active relative deny forms remain required. Recheck before relying on those pins.
- Source-checked 2026-08-15 on OpenCode 1.18.18 in `packages/opencode/src/tool/webfetch.ts`: WebFetch had no equivalent to Claude Code's classifier, hostname canonicalization, resolved-address check, or redirect-aware SSRF boundary. Keep sensitive reads and shell network separately restricted; recheck when that source changes.
- The repository's `opencode/.config/opencode/plugins/reviewed-writes.ts` validates every `apply_patch` source and move destination before native permission handling. Source-checked 2026-09-01 on OpenCode 1.18.25, upstream `packages/opencode/src/tool/apply_patch.ts` applies accepted operations sequentially. Same-user path replacement between validation and write remains a TOCTOU residual; recheck both components when either changes.
- The spar payload scanner cannot identify every secret format, and another same-user process can mutate a validated repository or handoff before reviewer access. Final review remains required.
- A 2026-08-17 user-traversable-path probe confirmed that `/var/tmp` shares the root filesystem and permits same-filesystem hard-link aliases. A Codex write grant for `/var/tmp/spar-*` remains unsafe; re-run the probe before reconsidering it.
- Live-verified 2026-08-12 on OpenCode 1.18.16: headless argument prompts above about 3.8 KB and ask-gated external reads hung before completion, while an ask-gated edit was rejected. Re-run those canaries before relying on unattended prompt handling.
- Observed 2026-09-01 on OpenCode 1.18.25: an explicitly selected TUI model variant persisted across restarts and overrode configured base effort. Confirm xhigh in the selector when effective effort matters.
- Observed 2026-08-15: while the tracked Codex runtime config remains deployed, app rewrites can include plugin, MCP, and desktop state. Reconcile those changes without copying host state into the portable template, and watch openai/codex#30045 for runtime-write corruption.
- Live-verified 2026-09-02 on Claude Code 2.1.258: two fresh `spar-claude` calls from OpenCode could read the repository but not their validated, flushed handoff. Treat OpenCode-to-Claude spar as unavailable until the bridge grant is diagnosed and a fresh live call reads the exact handoff.
- Checked 2026-08-12: standalone `opencode -s` and `codex resume` showed snapshots rather than a supported concurrent live-follow view. Recheck when Claude Code, Codex, or OpenCode adds session following.

## Open Decisions

- Decide whether Claude settings should define `fallbackModel` for provider-overload resilience.
- Decide whether to remove the status-line hostname segment, which renders only when `SSH_CONNECTION` is present.
- Decide whether an Omarchy-only Claude Code sandbox trial justifies tracked promotion. The untracked trial denies `~/.ssh`, `~/.aws`, and `~/.gnupg`, asks before `dangerouslyDisableSandbox`, checks command classification and repository writes, and requires a separate WSL behavior test. Relevant upstream issues: anthropics/claude-code#43713, #26722, and #54215.
- Keep the `spar-claude` stall watchdog at 180 seconds until ordinary review latency distinguishes slow progress from genuine stalls.
- Revalidate whether skill `allowed-tools` approval lasts for the invoking turn or the session. Current managed workflows do not depend on the longer interpretation.
- Decide ownership of host-created `diagnose-crash` and `omarchy` links under `~/.agents/skills` before managing or removing them.

## Deferred Work

- Complete the WSL host pass: inspect status and diff before pulling migration changes; reconcile app-managed state and obtain H's approval before discarding generated or obsolete hunks; keep config content out of chat and logs; restow from the supplying clone; run `make verify`; migrate Codex config from that clone; verify `~/.codex` is real and owner-controlled and its config is a current-user-owned mode-600 single-link regular file; preserve the evidence and stop on any mismatch; add a WSL-compatible Codex installation; confirm OpenCode's app-temp root; then run fresh permission and bridge checks, including hard-link alias and both link-count refusals before spar use. After migration, do not run `make clean`, `make stow`, `make restow`, or `make verify` until tracked runtime retirement.
- Retire the tracked Codex runtime config only after the WSL migration evidence is reviewed and a separate candidate is approved.
- Run `/fewer-permission-prompts` against accumulated host transcripts and promote only durable read-only rules. Keep `gh api` excluded.
- Run fresh primary external-read canaries for Claude Code and Codex when each tool is next started.
- Revisit native cross-model review when a managed tool provides a suitable read-only cross-vendor path under subscription authentication.
- Keep Codex-to-Claude review manual outside the strict Codex profile until its root-denied permissions can grant the required Claude runtime and state without weakening the primary sandbox.

## Revalidation Triggers

- Routine client releases require no ledger update. Revalidate when a dependent interface, permission rule, hook, temp root, matcher, model catalog, or observed behavior changes.
- Re-run bridge repository, handoff, scanner, lifecycle, timeout, and authentication checks after changing their scripts, reviewer profiles, permission semantics, or runtime dependencies.
- Re-run Claude Code safe-mode, tool-surface, model-family, effort, and authentication checks after changing reviewer flags or when `claude -p` behavior changes.
- Re-run Codex root-deny, workspace, network, plugin-isolation, and resumed-session checks after changing its permission profile or runtime boundaries.
- Re-run OpenCode project-isolation, plugin, package-state, app-temp, grouped-patch, and permission-subject checks after a relevant OpenCode or plugin API change.
- Use `claude --version` for Claude Code evidence and `mise ls --current` for Codex and OpenCode evidence so stateful wrappers are not invoked.
