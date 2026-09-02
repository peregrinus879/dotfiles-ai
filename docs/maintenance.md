# Maintenance Ledger

This ledger contains unresolved decisions, deferred work, active limitations, and revalidation triggers. Remove closed items after folding any lasting constraint into `AGENTS.md`, shared guidance, a skill, a script header, or a test.

## Active Limitations

- OpenCode has no classifier or OS sandbox. Its native `grep` and `glob` permission subjects, finite Bash path scanner, unrecognized readers, dynamic path arguments, wrappers, and scripts leave instruction-governed residuals. Recheck when OpenCode changes permission matching or `packages/opencode/src/tool/shell.ts`.
- OpenCode 1.18.26 supplies worktree-relative read and edit subjects and parent-directory external subjects. `~`-keyed read/edit entries and file-level external entries do not match those subjects, so active relative deny forms remain required. Recheck before relying on the pins.
- OpenCode WebFetch has no equivalent to Claude Code's classifier, hostname canonicalization, resolved-address check, or redirect-aware SSRF boundary. Keep sensitive reads and shell network separately restricted; recheck when its fetch implementation changes.
- OpenCode `apply_patch` validates every source and move destination before native permission handling, then applies accepted operations sequentially. Same-user path replacement between validation and write remains a TOCTOU residual.
- The spar payload scanner cannot identify every secret format, and another same-user process can mutate a validated repository or handoff before reviewer access. Final review remains required.
- A Codex write grant for `/var/tmp/spar-*` remains unsafe because `/var/tmp` shares the root filesystem and permits same-filesystem hard-link aliases. The user-traversable-path probe confirmed that the alias class is live on the host. Re-run the probe before reconsidering the grant.
- OpenCode 1.18.16 headless calls hung on large argument prompts and ask-gated external reads. Recheck before relying on unattended prompt handling.
- An explicitly selected OpenCode TUI model variant persists across restarts and overrides the configured base effort. Confirm xhigh in the selector when effective effort matters.
- While the tracked Codex runtime config remains deployed, app rewrites can include plugin, MCP, and desktop state. Reconcile those changes without copying host state into the portable template, and watch openai/codex#30045 for runtime-write corruption.
- On Claude Code 2.1.258, two fresh `spar-claude` calls from OpenCode could read the repository but not their validated, flushed handoff. Treat OpenCode-to-Claude spar as unavailable until the bridge grant is diagnosed and a fresh live call reads the exact handoff.
- Headless reviewer sessions have no supported live-follow view. Recheck when Claude Code, Codex, or OpenCode adds concurrent session following.

## Open Decisions

- Decide whether Claude settings should define `fallbackModel` for provider-overload resilience.
- Decide whether to remove the status-line hostname segment, which renders only when `SSH_CONNECTION` is present.
- Keep Claude Code sandboxing disabled. Any trial stays Omarchy-only in untracked `settings.local.json`, denies `~/.ssh`, `~/.aws`, and `~/.gnupg`, asks before `dangerouslyDisableSandbox`, checks command classification and repository writes, and requires a separate WSL behavior test before tracked promotion. Relevant upstream issues: anthropics/claude-code#43713, #26722, and #54215.
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
