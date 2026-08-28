---
name: commit
description: Prepare, review, and commit an exact atomic diff with documentation and scratch checks.
---

# Commit Conventions

## Format

```
<type>[(scope)]: <subject>

[optional body]

Co-Authored-By: OpenAI {official display name of current model} <noreply@openai.com>
```

Co-Authored-By model rule: resolve the placeholder at commit time from the active model identifier. Use the provider's official human-facing display name, preserving every qualifier in that name. Never copy the raw technical identifier or hard-code a specific model.
Use conventional commit types (`feat`, `fix`, `docs`, `refactor`, `style`, `test`, `chore`).

## Pre-commit check

Before staging, sync existing project documentation with the pending changes:

- Identify documentation (README.md, CLAUDE.md, or similar) whose commands, paths, workflows, or file listings the changes affect, and update it.
- Update only what the current change requires; do not expand scope.
- Do not create new documentation files unless explicitly requested.

## Scratch file handling

Before review, inspect untracked files (`git ls-files --others --exclude-standard`) and distinguish intended new files from session scratch or iteration artifacts such as test scripts, debug outputs, scratch notes, and single-use scripts.

- Include every proposed deletion or `.gitignore` addition in the review packet. Do not change those files before approval.
- Delete or ignore only the items covered by H's approval. Never auto-delete an untracked repository file.
- If none exist, skip silently.

## Review gate

Before staging, prepare one complete candidate from `git status --short`, unstaged and staged binary diffs, and the full contents of intended untracked files. Report:

- the exact intended paths and diff, including deletions, binary changes, and new files;
- verification results, literal warnings, and anything not run;
- the proposed commit message; and
- the proposed disposition of every scratch-looking untracked file.

Repeat this complete compact cheat sheet in every review packet until H asks to retire it, and tell H to review from a separate terminal pane at the repository root:

1. `nvim .`, then `<Space>gd`: open tracked staged and unstaged hunks.
2. `<M-w>`: cycle the input, hunk list, and preview panes. `<C-n>`/`<C-p>` or arrow keys: move between hunks; the highlight updates the preview.
3. `<M-p>`: toggle the preview. `<M-m>`: maximize or restore the active picker pane.
4. `<Enter>`: open the selected file and close the picker. `<Space>sR`: resume after opening a file. `<Esc>`: close without opening.
5. `<Space>gs`: open Git Status for intended untracked files. Highlight each file to inspect its preview; use `<Enter>` only when it must be opened, then `<Space>sR` to resume.
6. Avoid `<Tab>`, which stages, and `<C-r>`, which restores, in both Git pickers.

Offer the read-only terminal fallback `git status --short`, `git diff --stat HEAD`, `git diff HEAD`, and `git diff HEAD -- path/to/file`. Then use the tool's interactive selector with `Approve and commit (Recommended)` first, followed by `Revise with comments` and `Reject with comments`; its built-in custom answer is the discussion path. A comment-bearing choice triggers a free-form follow-up when its comment is not already present. `Revise with comments` updates the current candidate but never authorizes a commit: incorporate the comments, verify, and present a refreshed packet. `Reject with comments` rejects the candidate: preserve unrelated and user-authored changes, remove all candidate-owned changes, build a new candidate from the comments, verify, and present a refreshed packet. A custom discussion answer changes nothing: answer it, then present the same packet and selector again.

Plan approval and skill invocation do not authorize a commit. Approval covers only the presented content, intended paths, message, and scratch disposition. Any change to one of them requires a refreshed packet and selector. Interruption leaves the current worktree intact.

## Staging and commit

- Proceed only after `Approve and commit` for the current packet.
- Apply only the approved scratch disposition.
- Stage specific files by name (`git add <file>`). Do not use `git add -A` or `git add .`.
- If a file mixes the current commit with unrelated changes, do not alter, stage, or temporarily revert the unrelated hunks. Defer the file or stop and ask the user how to split the work.
- If the index already contains unrelated staged changes, stop rather than unstaging, replacing, or committing them.
- Never stage sensitive files (.env, credentials, private keys).
- Verify the staged patch and staged path set match the approved candidate exactly before committing. Any mismatch requires a new review.

## Rules

- Atomic: one complete, self-contained change per commit; separate commits by type.
- Scope: include when the change is localized to a component; omit for top-level or cross-cutting changes.
- Subject: imperative mood, lowercase, 50 chars max.
- No ephemeral references: no audit numbers, ticket IDs, or session-specific identifiers.
- Commit identity: confirm `git config user.email` is the GitHub no-reply, not a personal inbox; stop if not.
- Commit on the current branch; do not create branches unasked.
- Never amend unless H explicitly requests it for the exact current commit.
- Push: user handles manually (SSH passphrase required). Do not push.

## Push hint

After committing, show the push command matching the branch's upstream state: `git push` with an upstream, `git push -u origin <branch>` when `origin` exists without one, or add the remote first when there is no `origin`.
