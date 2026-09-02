---
name: commit
description: Stage, review, and commit one exact atomic change with H's approval.
---

# Commit

## Message format

```
<type>[(scope)]: <subject>

[optional body]

Co-Authored-By: <official display name of the active model> <provider no-reply address>
```

- Types: `feat`, `fix`, `docs`, `refactor`, `style`, `test`, `chore`. Add a scope when the change is localized to one component.
- Subject: imperative mood, lowercase, 50 characters max. No ticket numbers, audit numbers, or session identifiers.
- Trailer: resolve the display name from the active model identifier at commit time and keep every qualifier. Anthropic models use `<noreply@anthropic.com>`; OpenAI models use `OpenAI <display name> <noreply@openai.com>`. Never hard-code a model.

## Before staging

1. Confirm `git config user.email` resolves to the GitHub no-reply address; stop if it does not.
2. Classify untracked files (`git ls-files --others --exclude-standard`) as intended new files or session scratch. Propose a disposition for scratch; never delete an untracked file without H's approval.
3. Update documentation whose commands, paths, workflows, or listings changed, keeping each fact in its canonical owner. Create no documentation file unasked.
4. If the index already holds unrelated staged changes, stop and ask.

## Candidate

1. Stage only the intended paths with `git add -- <path>...`. When a file mixes the commit's hunks with unrelated changes, stage exactly the intended hunks with `git apply --cached` on a trimmed patch, or defer the file and ask H. Never use `git add -A` or `git add .`, and never stage credential-shaped files.
2. Record the candidate tree: `git write-tree`.
3. Screen the staged diff, paths, and message for content unsuited to the audience, world-readable unless H says otherwise: machine, user, and host identifiers; local paths; security posture; private correspondence; session metadata. Report only metadata for binary or unreadable files and ask H to inspect them in a separate pane.
4. Present the packet: `git diff --cached --stat`, the proposed message, the tree id, verification results and anything not run, the privacy screen result, and the scratch disposition. Do not paste the full diff unless H asks. Tell H to review with `git diff --cached` or Neovim's staged-hunk view, then offer `Commit and resume`, `Commit and pause`, and free-text revision, rejection, or questions.

Any change to the staged content, message, audience, or scratch disposition after approval requires a fresh packet. Rejection preserves the worktree; `git restore --staged -- <paths>` clears the index if H wants that.

## Commit

1. Confirm `git write-tree` still equals the recorded tree; otherwise present a fresh packet.
2. Apply the approved scratch disposition, then commit on the current branch with the approved message. Never amend or create branches unasked. Never push.
3. Report the hash and title. `Commit and resume` continues only work the active request authorizes; when none remains, load the `publish` skill before presenting a push. `Commit and pause` stops for discussion.
