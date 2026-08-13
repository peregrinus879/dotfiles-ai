---
name: commit
description: Commit workflow with doc sync, scratch cleanup, staging, and conventional commit conventions.
---

# Commit Conventions

## Format

```
<type>[(scope)]: <subject>

[optional body]

Co-Authored-By: OpenAI {current model} <noreply@openai.com>
```

Use conventional commit types (`feat`, `fix`, `docs`, `refactor`, `style`, `test`, `chore`).

## Pre-commit check

Before staging, sync existing project documentation with the pending changes:

- Identify documentation (README.md, CLAUDE.md, or similar) whose commands, paths, workflows, or file listings the changes affect, and update it before staging.
- Update only what the current change requires; do not expand scope.
- Do not create new documentation files unless explicitly requested.

## Scratch file cleanup

Before staging, check for untracked files that look like session scratch or iteration artifacts (`git ls-files --others --exclude-standard`): test scripts, debug outputs, scratch notes, single-use scripts.

- Present the list to the user and ask which to delete or add to `.gitignore`.
- Delete or gitignore only after explicit confirmation. Never auto-delete.
- If none exist, skip silently.

## Staging

- Stage specific files by name (`git add <file>`). Do not use `git add -A` or `git add .`.
- If a file mixes the current commit with unrelated changes, do not alter, stage, or temporarily revert the unrelated hunks. Defer the file or stop and ask the user how to split the work.
- Never stage sensitive files (.env, credentials, private keys).

## Rules

- Atomic: one complete, self-contained change per commit; separate commits by type.
- Scope: include when the change is localized to a component; omit for top-level or cross-cutting changes.
- Subject: imperative mood, lowercase, 50 chars max.
- No ephemeral references: no audit numbers, ticket IDs, or session-specific identifiers.
- Commit identity: confirm `git config user.email` is the GitHub no-reply, not a personal inbox; stop if not.
- Commit on the current branch; do not create branches unasked.
- Push: user handles manually (SSH passphrase required). Do not push.

## Push hint

After committing, show the push command matching the branch's upstream state: `git push` with an upstream, `git push -u origin <branch>` when `origin` exists without one, or add the remote first when there is no `origin`.
