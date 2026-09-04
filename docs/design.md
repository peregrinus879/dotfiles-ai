# Design

`AGENTS.md` states the invariants. This note gives the reasons, so a reader can judge whether the same shape fits their own setup.

## Two interventions

Every change reaches the world through exactly two human actions: approving one exact staged candidate, and running one push command. Everything before the first is the agent's work, verified by the repository's own gates; everything between them is review; everything after the second is verification. Two fixed points keep the human in control without turning the human into the pipeline. A request that spans several repositories still ends with one push command per repository, presented together.

## Enforce, then instruct

Rules live at the lowest layer that can hold them. Permission rules and sandboxes are deterministic and hold against a prompt-injected session; hooks are deterministic but see only what the tool shows them; scripts make a procedure repeatable across models and testable in CI; prose states intent and covers what the lower layers cannot express. The commit gate is the worked example: the deny on pushes is a permission rule, the "one exact candidate" rule is a hook plus a record on disk, the packet is a script's output, and the skill says when to run which.

## One trust model, three enforcement points

The three tools enforce different things, and the configuration says so instead of pretending otherwise. Claude Code has deterministic allow and deny rules plus an auto-mode classifier that judges everything else against written rules. Codex has an OS sandbox with the filesystem root denied and command network off, so its boundary holds even when the model is wrong. OpenCode has lexical rules and no sandbox, so its rules are guardrails against mistakes, not containment. The same list of credential stores and Git internals is applied in each, and a test keeps the three lists aligned.

## Read-only cross-vendor review

A second opinion is worth most when it comes from a different model family that reads the same files. The bridges give one read-only, offline, single-turn reviewer with no write, web, plugin, or subagent surface, launched from a scrubbed environment under a hard timeout. Every flag is hard-coded so a caller cannot weaken the reviewer, and a repository that must not reach the other vendor opts out with one Git setting the bridges honor. Boundary files, the permission configs and the bridges themselves, get this review before every commit.

## One neutral source

Guidance and skills live once, under `~/.agents`, the home of the Agent Skills format. Each tool reads through its own mechanism: a rules symlink and skill symlinks for Claude Code, a global instructions symlink and native discovery for Codex, a config entry and a skill path for OpenCode. Adding a tool means adding a package of symlinks, and a tool adopting the standard means deleting one.

## The gate contract

Skills read a target contract instead of per-repository prose: `lint` and `check` are the repository checks, `restow` and `verify` the host verification, `verify-published` the post-push check. A repository declares a gate by defining the target, host-bound targets refuse on the wrong host or clone, and Make targets and npm scripts of the same name are equivalent. The commit skill therefore needs no knowledge of any repository.

## Two hosts

The harness deploys with GNU Stow without directory folding, so managed parents stay real directories that tools may write into and only leaf files are links. A change that alters deployed state is applied on the host where it is made, and the same commit adds a host pass item to the ledger with the exact steps for the other host; the agent runs the item in the next session there and deletes it.

## The repository is the record

Durable decisions live in `AGENTS.md`, unresolved ones in the maintenance ledger, and provenance in Git history. Assistant memory is a single-device cache that holds pointers at most, because the author works across machines and the memory does not travel. Dated evidence in the ledger names its revalidation trigger, so a fact is either current or scheduled to be rechecked.

## Effort and models

Each tool runs its strongest model at the highest persistent effort, because the cost of a wrong change to live configuration exceeds the cost of tokens. Lightweight tasks that tools delegate, such as titles and summaries, go to a smaller model where the tool offers that setting.
