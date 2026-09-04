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
4. Run the repository's gates, fixing and rerunning until each passes: the repository checks, `make lint` and `make check` when the Makefile defines them, else `npm run check` when the package defines it; then the host verification, `make restow` and `make verify` when defined, else `npm run verify`. A target that refuses because this is not its host or its deployed clone is skipped with that reason. The contract covers H's repositories; elsewhere run the checks the project documents.
5. If the index already holds unrelated staged changes, stop and ask.

## Candidate

1. Stage only the intended paths with `git add -- <path>...`. When a file mixes the commit's hunks with unrelated changes, stage exactly the intended hunks with `git apply --cached` on a trimmed patch, or defer the file and ask H. Never use `git add -A` or `git add .`, and never stage credential-shaped files.
2. Record the candidate: the tree from `git write-tree`, the parent from `git rev-parse HEAD`, and the branch from `git branch --show-current`.
3. Run `git diff --cached | spar-payload-scan diff`. A finding names a credential-shaped value or a sensitive path in the staged content and blocks the packet until the span is removed or H rules it public; never stage around it. Then screen the staged diff, paths, and message for content unsuited to the audience, world-readable unless H says otherwise: machine, user, and host identifiers; local paths; security posture; private correspondence; session metadata. Report only metadata for binary or unreadable files and ask H to inspect them in a separate pane.
4. Present the packet: `git diff --cached --stat`, the proposed message, the tree, parent, and branch, the gate report (each target passed, failed with its output, or skipped with its reason, and whether `git diff --quiet` held after staging, which shows the gates covered exactly the candidate tree), the scanner and privacy screen results, and the scratch disposition. Do not paste the full diff unless H asks. Follow the packet with the review cheat sheet below, then use the tool's interactive question selector (Claude Code, OpenCode, and Codex each have one) with `Commit and resume` first and `Commit and pause` second. Free text carries revision requests, rejection, and questions and never authorizes a commit by itself: a revision request updates the candidate and produces a fresh packet; a question is answered and the same packet and selector are presented again.

Any change to the staged content, message, audience, or scratch disposition after approval requires a fresh packet. Rejection preserves the worktree; on H's instruction, `git restore --staged -- <paths>` clears the index.

## Review cheat sheet

Repeat this in every packet until H asks to retire it. Review from a separate terminal pane at the repository root:

1. `nvim .`, then `<Space>gd`: open tracked staged and unstaged hunks.
2. `<M-w>`: cycle the input, hunk list, and preview panes. `<C-n>`/`<C-p>` or arrow keys: move between hunks; the highlight updates the preview.
3. `<M-p>`: toggle the preview. `<M-m>`: maximize or restore the active picker pane.
4. `<Enter>`: open the selected file and close the picker. `<Space>sR`: resume after opening a file. `<Esc>`: close without opening.
5. `<Space>gs`: open Git Status for intended untracked files. Highlight each file to inspect its preview; use `<Enter>` only when it must be opened, then `<Space>sR` to resume.
6. Avoid `<Tab>`, which stages, and `<C-r>`, which restores, in both Git pickers.

Terminal fallback: `git diff --cached --stat`, `git diff --cached`, and `git diff --cached -- path/to/file`.

## Commit

1. Confirm `git write-tree`, `git rev-parse HEAD`, and `git branch --show-current` still equal the recorded tree, parent, and branch; otherwise present a fresh packet.
2. Apply the approved scratch disposition, then commit on the current branch with the approved message. Never amend, create branches, or skip hooks unasked. Never push.
3. Verify the result before reporting it: the new commit's tree (`git rev-parse HEAD^{tree}`), parent (`git rev-parse HEAD^`), branch, full message (`git log -1 --format=%B`), and author and committer addresses (`git log -1 --format='%ae %ce'`, both the GitHub no-reply) must equal the approved values. A hook can restage content or rewrite the message after the checks in step 1; if anything differs, report the exact difference and stop for H's decision instead of amending.
4. Report the hash and title. `Commit and resume` continues the request's authorized work; when none remains and the branch has a configured upstream or H named a destination, load the `publish` skill and present the push without stopping. `Commit and pause` stops for discussion.
