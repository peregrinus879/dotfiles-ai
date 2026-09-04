---
name: eyrsync
description: Sync this harness against the official documentation, changelogs, and announcements of Claude Code, Codex, and OpenCode, and the Agent Skills specification. Use when a tool releases a change to its configuration, hooks, agents, skills, or permissions, when OpenCode moves to a new major version, when Claude Code starts reading AGENTS.md or ~/.agents natively, or on a periodic pass. Also sync the sibling repositories eyrarchy and eyrwsl where they depend on the harness: the gate contract, the project-skill layout, and their statements about the harness.
---

# Eyrsync

Compare the repository's structure, names, configuration keys, and instructions against what the three tools and the Agent Skills specification currently document, and apply changes only where they belong. The omasync skill in the sibling repositories is the model; this one covers the harness, and the sibling repositories where they meet it.

## Sources

Official documentation, read live: Claude Code (`https://code.claude.com/docs/llms.txt` indexes it; the `.claude` directory, memory, skills, sub-agents, hooks, settings reference, model configuration, and changelog pages own the conventions this repository uses); Codex (`https://learn.chatgpt.com/docs`: the configuration reference, hooks, subagents, skills, and sandbox pages); OpenCode (`https://opencode.ai/docs`: config, agents, skills, plugins, permissions, and the source clone under `~/Projects/quarry/opencode` that `references.txt` names, including its changelog and the permission, skill, and tool sources the ledger cites); the Agent Skills specification (`https://agentskills.io/specification`); the AGENTS.md convention (`https://agents.md`). Announcements: the Anthropic and OpenAI engineering posts and the OpenCode releases page. Dated evidence already gathered lives in `docs/maintenance.md`; start from its newest entries. The sibling pass reads the clones under `~/Projects/eyrie/eyrarchy` and `~/Projects/eyrie/eyrwsl` by standing grant.

## When To Use

- A tool release changed an interface the ledger's revalidation triggers name: a permission rule, a hook event or payload, a skill or agent frontmatter field, a config key, a temp root, or a model catalog.
- OpenCode moves to a new major version, or Claude Code starts reading `AGENTS.md` or `~/.agents/skills` natively.
- Before a structural change to the packages, so the change lands on current conventions.
- Periodically, when no trigger has fired for a while.
- The harness changed something a sibling depends on, or H names a sibling: run the sibling pass.

## Workflow

1. Read the OpenCode source clone as it is and note its checked-out version; compare with the newest upstream tag through `git ls-remote --tags`, which writes nothing, and ask H to refresh the clone (`make refs` in a sibling repository) when it lags, because the clone lies outside this repository's edit boundary. Note the installed versions of the three tools with `mise ls --current`, and read the ledger's dated entries to know what was last verified and when.
2. For each tool, compare what the packages deploy against what its documentation names: the directories and file names under `~/.claude`, `~/.codex`, and `~/.config/opencode`; the settings and config keys the tracked files use, including any the reference marks deprecated; the hook events, payload shapes, and decision formats `templates/hooks/commit-gate` and the plugin rely on; agent and skill frontmatter fields against the tool and the specification; and permission rule syntax against the current matcher semantics. Everything under `~/.agents` keeps H's names; only tool-side files are measured against the docs.
3. Read each tool's changelog since the last dated evidence for anything that touches those interfaces, including new capabilities the harness does not use yet.
4. Classify each difference: an intentional choice recorded in `AGENTS.md` or `docs/design.md`, an upstream change the harness must follow, or a new capability worth adopting. Name the source and date for each.
5. Apply upstream changes and adopted capabilities through the commit skill, package by package, running the gates as it defines them; after a change to the deployed shape, or a tool release that touches hooks, skills, agents, or permissions, ask H to run `make canary` from a plain terminal, which runs each tool once and asserts the skills inventory, the gate's denial, the read grant, and a credential refusal, and record the result in the ledger. Update `AGENTS.md`, `README.md`, and `docs/design.md` when ownership, layout, or reasoning changes, and record new dated evidence and revalidation triggers in `docs/maintenance.md`.
6. Summarize what was adopted, rejected, or kept different, with the sources.
7. Run the sibling pass below when the harness's contract surface changed, when a sibling's clone moved past the last pass, or when H asks for it.

## Sibling Pass

`eyrarchy` and `eyrwsl` are synced only where they and the harness depend on each other:

- The gate contract: each `Makefile` defines `lint`, `check`, `test`, `restow`, and `verify`, with `require-host` and `require-clone` guarding the host targets, and `verify-published` where the repository publishes; GitHub Actions runs `make check` and `make lint` on every push to `main` and every pull request. The commit skill owns the contract; a sibling only defines the targets.
- The project-skill layout: `omasync` lives at `.agents/skills/omasync/SKILL.md` with `.claude/skills` and `.opencode/skills` symlinks, and its frontmatter names the directory and carries the specification's fields, the layout `eyrsync` uses here.
- The statements about the harness in their `AGENTS.md` and `README.md`: EyrAgents owns the tool configuration, the AI tools run as it configures them, the family links and the EyrAgents install steps are current, and no rule the shared guidance or a skill owns is restated.
- The OpenCode environment their Bash exports, `OPENCODE_DISABLE_EXTERNAL_SKILLS` and `OPENCODE_ENABLE_EXA`, checked against the source clone's runtime flags and skill discovery: the first disables discovery through `~/.claude`, `~/.agents`, and a project's `.claude` and `.agents` directories, so the harness reaches its skills through `skills.paths` and a project through `.opencode/skills`; when either side changes, the other follows.
- The mise wrappers the harness resolves through, `~/.local/bin/{claude,codex,opencode}` from `eyrwsl` and Omarchy's own on `eyrarchy`, against the Codex template's mise grant and `make verify` here.
- `references.txt`: the family union defines `~/Projects/quarry` and the siblings' `make refs` keeps it, so every clone this skill reads is declared in this repository's file.

Report each difference with its owner. Apply a change in a sibling only when H names that repository in the request: edit there, run its gates, and commit through the commit skill from that repository's root, one candidate per repository, then present every push together at the end. Otherwise report the drift with the exact steps for a session in that repository.

## Completion Checks

- Every tool-side file still carries the name and fields its tool documents, and every shared file still lives under `~/.agents`.
- `make lint`, `make check`, `make restow`, and `make verify` pass on this host, and the ledger carries a host pass item for the other host when deployed state changed.
- The ledger's dated evidence names the versions checked and the trigger for the next check.
- When the deployed shape or a relevant tool interface changed: `make canary` passed on this host and the ledger carries its date.
- When the sibling pass ran: each sibling's `make lint` and `make check` pass, and its statements about the harness match what the packages deploy.
