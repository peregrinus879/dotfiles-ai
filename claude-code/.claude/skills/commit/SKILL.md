---
name: commit
description: Prepare, review, and commit an exact atomic diff with documentation, privacy, and publication checks.
---

# Commit Conventions

## Format

```
<type>[(scope)]: <subject>

[optional body]

Co-Authored-By: {official display name of current model} <noreply@anthropic.com>
```

Co-Authored-By model rule: resolve the placeholder at commit time from the active model identifier. Use the provider's official human-facing display name, preserving every qualifier in that name. Never copy the raw technical identifier or hard-code a specific model.
Use conventional commit types (`feat`, `fix`, `docs`, `refactor`, `style`, `test`, `chore`).

## Pre-commit check

Before staging, classify each affected document by its canonical owner:

- Shared guidance contains cross-tool policy; project AGENTS files contain current repository invariants.
- README files contain public scope, setup, and usage; maintenance ledgers contain only unresolved decisions, deferred work, active limitations, watch items, and evidence tied to a live revalidation trigger.
- Skills contain exact workflow procedure; script headers and code comments contain local present constraints.

Update documentation whose commands, paths, workflows, or file listings changed. Remove duplicated authority, completed provenance, closed maintenance items, and transition narration after preserving any lasting constraint in its canonical owner. Keep the edit within the current commit's scope and create no new documentation file unless H requested it.

## Scratch file handling

Before review, inspect untracked files (`git ls-files --others --exclude-standard`) and distinguish intended new files from session scratch or iteration artifacts such as test scripts, debug outputs, scratch notes, and single-use scripts.

- Include every proposed deletion or `.gitignore` addition in the review packet. Do not change those files before approval.
- Delete or ignore only the items covered by H's approval. Never auto-delete an untracked repository file.
- If none exist, skip silently.

## Candidate privacy screen

Before presenting the candidate, screen the proposed message, complete status path inventory, intended paths, complete diff, and intended new-file contents for context inappropriate to the intended audience. Use H's declared audience when available; otherwise assume world-readable publication. Check for machine, user, and host identifiers; local paths; security posture; private correspondence; and session metadata. This is separate from code review and secret scanning.

Inventory path names before content. Semantically review each readable text or supported binary artifact. Never open a path barred by the shared Safety rules; treat any other binary or opaque artifact that cannot be reviewed semantically the same way. Report only safe path and object metadata and require H to inspect the exact artifact in a separate terminal pane, never through `!` or pasted session content, then rule on it for the candidate and audience. The ruling permits neither an agent read nor staging or commit.

## Candidate bindings

Use the following versioned schemes exactly. Any normalization change requires a new scheme suffix, synchronized skill copies, and updated contract tests.

- `candidate-status-v1`: SHA-256 from the canonical command `git --no-optional-locks -c core.quotePath=true -c color.status=false -c status.renames=false status --porcelain=v2 -z --untracked-files=all | sha256sum`. Internally inventory and privacy-screen every path, then report only the digest and reconciled total, intended, and preserved-unrelated counts. This is presentation-time scope evidence, not a candidate-content binding or post-stage comparison. Unrelated-only drift requires renewed inventory, screening, counts, and digest without invalidating unchanged candidate approval; intended-path overlap invalidates approval.
- `candidate-tracked-v1`: capture one literal path list containing only intended paths present in the reported base, and reuse it before and after staging. Canonical command template: `git --no-optional-locks -c core.quotePath=true -c color.ui=false -c color.diff=false -c core.compression=0 -c diff.orderFile=/dev/null -c diff.suppressBlankEmpty=false diff [--cached] --binary --full-index --no-ext-diff --no-textconv --no-renames --no-indent-heuristic --diff-algorithm=myers --unified=3 --no-relative --src-prefix=a/ --dst-prefix=b/ "<base>" -- "<base-present-intended-path>"... | sha256sum`; omit `--cached` before approval and include it after staging. Report the scheme, exact base and path inputs, and digest only, never the diff stream.
- `candidate-new-v1`: exclude paths absent from the base from both tracked fingerprints. For a regular file, run `sha256sum -- "<path>"` and `git hash-object --no-filters -- "<path>"`; never use `-w`. Active `filter`, `working-tree-encoding`, `text`, `eol`, or `ident` attributes, or `core.autocrlf` conversion, block approval until the would-be staged content is separately reviewable. For a symlink, bind mode `120000` with `readlink -n -- "<path>" | sha256sum` and `readlink -n -- "<path>" | git hash-object --stdin`; never use `-w`. Gitlinks with mode `160000` and other unsupported file types block approval. Treat a rename as a tracked deletion plus a separately bound new path.

Report effective `core.fileMode`. When false, preserve base/index modes and block a candidate that intends a tracked mode change or new executable until it can be handled on a mode-capable worktree with H's ruling; never force `core.fileMode=true`. Disclose active content conversion on tracked paths; their authoritative candidate bytes are the Git diff bound by `candidate-tracked-v1` and displayed by the editor and terminal diff views.

## Review gate

Before staging, prepare one complete candidate from the complete status inventory, unstaged and staged binary diffs, and the full contents of readable intended untracked files. Represent a Safety-barred intended file only by the safe metadata and H ruling defined above. Report:

- the exact base object ID, `candidate-status-v1` digest and reconciled counts, intended path/status/Git-mode manifest, explicit deletion and binary/opaque labels, diff stat, effective `core.fileMode`, `candidate-tracked-v1` inputs and digest, and every `candidate-new-v1` binding;
- verification results, literal warnings, and anything not run;
- the intended audience, candidate privacy-screen result, and any unreadable or opaque artifact rulings;
- the proposed commit message; and
- the proposed disposition of every scratch-looking untracked file.

Do not reproduce the complete diff or intended new-file contents in the conversation unless H explicitly asks. Offer one compact reproduction block for the named bindings only on request; fingerprints bind the candidate but never substitute for H's editor review.

Repeat this complete compact cheat sheet in every review packet until H asks to retire it, and tell H to review from a separate terminal pane at the repository root:

1. `nvim .`, then `<Space>gd`: open tracked staged and unstaged hunks.
2. `<M-w>`: cycle the input, hunk list, and preview panes. `<C-n>`/`<C-p>` or arrow keys: move between hunks; the highlight updates the preview.
3. `<M-p>`: toggle the preview. `<M-m>`: maximize or restore the active picker pane.
4. `<Enter>`: open the selected file and close the picker. `<Space>sR`: resume after opening a file. `<Esc>`: close without opening.
5. `<Space>gs`: open Git Status for intended untracked files. Highlight each file to inspect its preview; use `<Enter>` only when it must be opened, then `<Space>sR` to resume.
6. Avoid `<Tab>`, which stages, and `<C-r>`, which restores, in both Git pickers.

Offer the read-only terminal fallback `git status --short`, `git diff --stat HEAD`, `git diff HEAD`, and `git diff HEAD -- path/to/file`. Then use the tool's interactive selector with `Commit and resume` first, followed by `Commit and pause`. Use its built-in custom answer for questions, revision requests, rejection, and other instructions. Custom input never authorizes staging or commit. A revision request updates the current candidate: incorporate the comments, verify, and present a refreshed packet. Rejection preserves the candidate and worktree unless H explicitly requests disposal; approved disposal removes only candidate-owned changes and preserves unrelated and user-authored work. If custom input changes nothing, answer it, then present the same packet and selector again.

Plan approval and skill invocation do not authorize a commit. Approval covers only the fingerprint-bound candidate content, intended paths, message, audience, and scratch disposition. Any change to one of them requires a refreshed packet and selector. Interruption leaves the current worktree intact.

## Staging and commit

- Proceed only after `Commit and resume` or `Commit and pause` for the current packet.
- Apply only the approved scratch disposition.
- Stage specific files by name (`git add <file>`). Do not use `git add -A` or `git add .`.
- If a file mixes the current commit with unrelated changes, do not alter, stage, or temporarily revert the unrelated hunks. Defer the file or stop and ask the user how to split the work.
- If the index already contains unrelated staged changes, stop rather than unstaging, replacing, or committing them.
- Never stage sensitive files (.env, credentials, private keys).
- Verify the exact staged path/status/mode set, cached `candidate-tracked-v1` digest, every staged `candidate-new-v1` mode and object, and absence of unstaged intended-path drift against the approved bindings before committing. Unrelated-only drift follows the `candidate-status-v1` reconciliation rule; any candidate mismatch requires a new review.

## Post-commit routing

After the approved commit, verify and report its hash and title. `Commit and resume` continues only work authorized by H's active request or approved plan. When no approved unit remains, complete any warranted final review and run publication review automatically before presenting a push instruction. `Commit and pause` reports status and stops for discussion.

## Rules

- Atomic: one complete, self-contained change per commit; separate commits by type.
- Scope: include when the change is localized to a component; omit for top-level or cross-cutting changes.
- Subject: imperative mood, lowercase, 50 chars max.
- No ephemeral references: no audit numbers, ticket IDs, or session-specific identifiers.
- Commit identity: confirm `git config user.email` is the GitHub no-reply, not a personal inbox; stop if not.
- Commit on the current branch; do not create branches unasked.
- Never amend unless H explicitly requests it for the exact current commit.
- Push: user handles manually. Do not push.

## Publication review and push hint

Run this review automatically after the final approved commit and any final review, before presenting a push, release, pull request, or other publication as ready.

1. Define a publication descriptor with a credential-free logical destination, intended audience, exact local ref set and tips, immutable source object IDs, any ref updates and expected destination values, full source-to-destination refspecs, implicit publication behavior, referenced Git LFS objects, and the complete set of action-specific metadata fields and values, bodies, and asset digests. Use H's explicit destination when supplied; otherwise use the current branch's single configured upstream or push destination when unambiguous. Use H's declared audience or default to world-readable publication. Ask only when destination or audience remains materially ambiguous. A no-ref-update pull request or release is valid when stated explicitly. Never infer privacy from a remote name or URL, read or display endpoint credentials, or expose transient authenticated transfer endpoints.
2. Record how and when destination state was observed. Use it to narrow the review only when it is confirmed current and the effective operation enforces that exact expected value at execution. Otherwise review the complete history of the refs being published. A named destination ref with no recorded tip also requires complete-history review. An audience expansion at unchanged tips likewise requires complete-history review of the refs being published. Do not fetch unasked.
3. Before opening content, inventory every included commit and annotated tag's metadata and message; every path/version's name, type, mode, size, object identifier, and containing commits; every referenced Git LFS object; every action-metadata field and value, body, and asset name and digest; every configured push option; and every active client-side publication hook. If submodule recursion is not suppressed, give each submodule publication its own complete descriptor and history review. Record commit-metadata, tag-metadata, path/version, action-metadata, unique content-object, and external-artifact counts.
4. Never open an artifact barred by the shared Safety rules; treat any other binary or opaque artifact that cannot be reviewed semantically the same way. Report only safe metadata and require H to inspect the exact path and object in a separate terminal pane, never through `!` or pasted session content. H must rule explicitly on that artifact's suitability for the bound descriptor. The ruling permits neither an agent read nor commit or publication and becomes invalid with the descriptor. Treat unreadable hook or push-option effects the same way without exposing sensitive values.
5. Review metadata, messages, path names, action fields, and every readable artifact version for the candidate screen's privacy classes, including intermediate or later-deleted planning, review, and documentation material. Code review and secret scanning neither satisfy nor are replaced by this review. Process large inventories in bounded chunks without silent truncation.
6. Reconcile every commit-metadata, tag-metadata, path/version, action-metadata, and external-artifact record to reviewed readable content, an exact H ruling, or a blocking finding. A unique readable object may be reviewed once if every occurrence maps to it. Any count mismatch, unmatched record, truncation, decode failure, unsupported object, unruled unreadable or opaque artifact, unresolved implicit ref, hook, option, destination, or asset, or incomplete review blocks publication readiness.
7. Show H the descriptor, effective operation, immutable source IDs and asset digests, counts, rulings, omissions, destination-state freshness, and pass or blocker. Any destination, audience, ref-set, source ID, expected destination value, action field, asset digest, implicit behavior, or observed destination-state change invalidates the result.

Only after a passing review, show an explicit publication command bound to immutable source IDs, reviewed logical destinations, full destination ref names, exact action metadata, and asset-digest prechecks. Never rely on a bare `git push`, a mutable local source ref, `push.default`, or `remote.*.push`; suppress unreviewed implicit tag and submodule publication, use exact tag object IDs and refspecs when tags are reviewed, and account for every configured push destination, push option, and active client-side publication hook without bypassing safety checks. A differential-history review also requires an execution-time expected-old-value guard; otherwise use complete-history coverage. If the effective operation or destination remains ambiguous, withhold the hint and ask one focused question.
