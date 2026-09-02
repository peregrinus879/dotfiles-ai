# AGENTS.md - EyrAgents

EyrAgents is a GNU Stow repository for shared Claude Code, Codex, and OpenCode configuration. Keep changes portable across Omarchy and WSL unless a host-specific scope is explicit.

## Instruction Loading

- Claude Code loads the stowed global `~/.claude/CLAUDE.md` and rules, then this repository through the root `CLAUDE.md` import.
- Codex loads the tracked `codex/.codex/AGENTS.md` symlink to shared guidance and this repository file.
- OpenCode loads shared guidance from its global `instructions` entry and this repository file.
- Root maintenance wrappers and documentation remain source-only; Stow deploys package contents. Root `.claude/settings.json` and `opencode.json` are inert project placeholders without command grants.

## Documentation

- `claude-code/.claude/rules/shared-guidance.md` is the canonical managed cross-tool policy. Tool-specific mechanisms stay in each tool's configuration or wrapper.
- Order tools as Claude Code, Codex, OpenCode in repository lists, trees, and prose.
- Shared guidance owns cross-tool policy. This file owns current repository invariants. Skills own exact workflow procedure. Wrappers stay thin. `README.md` owns public scope, setup, and usage. Script headers own local constraints. `docs/maintenance.md` owns unresolved decisions, deferred work, active limitations, watch items, and revalidation evidence tied to those items.
- Repository prose describes current behavior. Git history owns completed decisions, transitions, reversals, and provenance. Remove closed maintenance items after folding any lasting constraint into its canonical owner.
- Read `README.md` before structural changes. Read the maintenance ledger before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or deferred work.

## Workflow Authority

- Work on one approved commit unit at a time. Never alter, stage, or temporarily revert unrelated hunks; defer mixed files or ask H how to split them.
- A plan authorizes its listed edits, verification, reviewer calls, and deployment steps, never a commit. Every commit requires H's approval of the exact candidate content, paths, message, audience, and scratch disposition.
- `/commit` owns exact candidate preparation, editor review instructions, staging checks, commit routing, privacy screening, and destination-bound publication review. Load it before every commit and every publication-readiness assessment.
- H performs pushes manually. Before presenting a push, release, pull request, or other publication as ready, complete the skill's review of every commit and artifact version the action would expose.
- Clear task requests authorize value-based read-only spar calls within scope. Review timing and breadth follow expected value, independence, risk, and available capacity.

## Security Boundaries

- Authentication, credentials, session state, and generated host state stay out of Git. The tracked Claude settings and current tracked Codex runtime config are the only app-managed rewrite exceptions.
- Keep credential-path denies aligned across Claude Code, Codex, OpenCode, reviewer profiles, handoff write gates, and the outbound scanner. `~/.ssh` and `gh api` remain denied to agents; H handles exceptions in a separate terminal.
- User requests authorize relevant non-secret external reads through native permission mechanisms. Broad working-root grants, external writes outside managed temporary roots and validated spar handoffs, session grants, delegated external access, uploads, and secret access remain prohibited.
- Trusted-repository defaults are not an isolation boundary against hostile project configuration. Use the project-disabled commands in `README.md` for untrusted checkouts.
- Primary web research follows each tool's managed policy. Reviewer web tools and command network remain disabled.

## Reviewer Bridges

- Claude Code reviews with Codex through `spar-codex`. Codex-to-Claude review runs manually outside the strict Codex profile. OpenCode's configured Claude path is `spar-claude`; active availability is recorded in the maintenance ledger.
- Reviewers use subscription authentication, launch from the caller's canonical Git root, and receive read-only access to that repository and one validated handoff. Git internals, credential-shaped paths, and the handoff manifest remain denied; other readable repository files may reach the vendor reviewer.
- Bridges hard-code safety flags, isolate startup, reject caller-directed authentication, routing, state, and Git-control variables, and preflight authentication after payload validation. Repository checks reject unsafe roots, mounts, metadata, names, symlink shapes, and hard-link aliases before reviewer access.
- Handoffs use one private mode-700 `/var/tmp/spar-<session-id>/` directory. The selected bridge creates, validates, flushes, scans, reports, and cleans it. Native handoff writes pass through the Claude hook or OpenCode plugin; shell writes remain gated.
- `spar-payload-scan` bounds and scans outbound prompts, handoff files, replies, and diagnostics. It rejects linked, malformed, oversized, binary, non-UTF-8, instruction-shaped, credential-shaped, and sensitive-diff artifacts. Public synthetic fixtures are bound to exact detector spans.
- Bridges validate ordered lifecycle events, requested reviewer identity, terminal success, nonempty rescanned replies, timeouts, and descendant cleanup. Bridge and scanner tests exercise these executable controls.
- `spar-codex` uses an inline root-denied, temporary-root-denied, repository-scoped profile with plugins, project instructions, skills, MCP, subagents, request-permission tools, and command network disabled.
- `spar-codex` still receives trusted global `~/.codex/AGENTS.md` guidance. `spar-claude` remains subject to higher-precedence managed policy.
- `spar-claude` is configured for safe mode, isolated setting sources, the Opus family alias at xhigh effort, explicit repository and handoff grants, credential denies, and only `Read`, `Glob`, and `Grep`.

## Tool Configuration

### Claude Code

- Claude Code uses `permissions.defaultMode: auto`, disables bypass mode, and retains built-in guardrails before managed overrides. The spar hook validates handoff writes while ordinary edits remain classifier-controlled.
- Claude Code sandboxing remains disabled in tracked settings; any Omarchy trial stays untracked and follows the maintenance ledger.
- The primary uses the durable Fable alias with xhigh effort. `workflowSizeGuideline: large` remains an advisory workflow-size setting.
- The automatic shell allowlist stays narrow. Built-in read-only Bash forms need no duplicate allow rules; `gh search`, broad `jq`, and `opencode debug` are outside the managed allowlist.
- `statusline.sh` owns its display and persistence conventions in its header. `/doctor` may delete local allowlists and rewrite `~/.claude.json`; review its findings and curate durable rules instead of restoring machine-local state wholesale.

### Codex

- The primary uses the root-denied `trusted-workspace` profile with automatic approval review, managed runtime reads, workspace and OS-temp writes, credential denies, Git protection, and command network disabled.
- Scripted `codex exec` calls use one finite prompt or `</dev/null>`, avoid `--last`, and select the strict reviewer profile explicitly. Codex skills live under `~/.agents/skills`.
- `templates/codex/config.toml` is the portable 12-key profile. The tracked runtime config remains its recursive superset; host state stays at eligible top-level tables, and changes inside bounded portable or permission tables require H's reconciliation ruling.
- The primary, spawned agents, and `spar-codex` use GPT-5.6 Sol Fast with xhigh reasoning under ChatGPT subscription authentication. The reviewer remains single-agent and summary-free.

### OpenCode

- OpenCode permits ordinary workspace edits and shell commands, asks before native filesystem access outside `/tmp/opencode` on the managed Linux root and validated spar handoffs, keeps sharing disabled, and denies credential paths plus common destructive, privileged, upload, remote-mutation, and direct nested-agent commands.
- Permission order is last-match-wins. User rules follow built-in defaults; catch-all allows precede narrow grants and later hard denials.
- `reviewed-writes.ts` validates every `apply_patch` source and move destination before native permission handling. Workspace containment, sensitive paths, symlink aliases, hard links, and handoff targets fail closed.
- The upstream shell path scanner covers a finite command set. Unrecognized readers, dynamic path arguments, wrappers, and scripts remain instruction-governed because OpenCode has no classifier or OS sandbox.
- Automatic external skill discovery stays disabled. Managed commit and spar skills win deterministically, while the optional Omarchy skill is explicit.
- Generated package manifests, locks, and dependencies remain host-local beneath a real `~/.config/opencode`. Stow manages tracked child paths, and the installation wrapper owns updates.

## State And Deployment

- Claude Code may rewrite tracked settings keys and ordering. Codex and the ChatGPT desktop app may rewrite the current tracked runtime config. Preserve and review those rewrites instead of reverting them or copying host state into the portable template.
- `make clean` keeps runtime-state parents as real directories, removes only recognized package-layout links, and never runs Codex config migration. Keep GNU Stow directory folding enabled.
- `make migrate-codex-config` is an explicit transition command. It accepts only a safe local config or the exact tracked runtime leaf from the executing clone and performs an atomic same-directory replacement.
- `make verify` resolves every non-ignored package file to its deployed target, checks pending source deletions against live endpoints, and enforces host-local state boundaries. Package `.gitignore` files remain source-only.

## Verification

- Run `make verify` and `make lint` after stowing or changing managed payloads.
- Verify instruction and configuration changes in fresh Claude Code, Codex, and OpenCode sessions when practical. Restart OpenCode after changing config, agents, skills, or plugins.
- Use the focused tests named by the changed component. Record only unresolved failures or live revalidation needs in `docs/maintenance.md`.

## Skills

Skills provide specialized instructions and workflows. Load a matching skill before acting.

- `commit`: prepare, review, and commit an exact atomic diff; review any push, release, pull request, or other publication before presenting it as ready.
- `spar`: run value-based cross-model brainstorming, plan, build, and diff review.
- `omarchy`: required for end-user Linux desktop, Hyprland, Omarchy, terminal, theme, and display configuration.
