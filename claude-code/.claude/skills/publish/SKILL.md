---
name: publish
description: Review the exact commits a push, release, or pull request would expose before presenting it as ready.
---

# Publish

Run this before presenting any push, release, pull request, or other publication as ready, including when no new commit is needed. H runs the push command; the skill verifies the result afterwards.

1. Bind the operation: the destination (H's explicit destination, else the branch's single configured upstream; ask if ambiguous), the audience (H's declared audience, else world-readable), the reviewed ref and its commit id (`git rev-parse <ref>`), the destination branch, and the exact refspec. Never read or display endpoint credentials.
2. Determine the base as the destination branch's tracking ref (`refs/remotes/<remote>/<branch>`), which is the last known destination tip; record its id. Do not fetch unasked; state that the tracking ref is the assumed base. Confirm `git merge-base --is-ancestor <base-id> <reviewed-id>`; if the reviewed commit does not descend from the base, the push would rewrite destination history, so stop and present it as a destructive action for H's separate ruling instead of continuing. The delta is `<base-id>..<reviewed-id>`, never `..HEAD`. Review complete history only for a first publication, a destination without a tracking ref, or an audience expansion.
3. Run both `git diff <base-id> <reviewed-id> | spar-payload-scan diff` and `git log -p --format= <base-id>..<reviewed-id> | spar-payload-scan diff`; the second catches a secret that one commit added and a later commit replaced. A finding blocks readiness until H rules on it. Then review every commit in the delta: message, author and committer identity, and every changed path's content, including files later deleted, for the commit skill's privacy classes. Report only metadata for binary or unreadable files and ask H to inspect them in a separate pane. Any unresolved finding blocks readiness.
4. When the reviewed commit was not committed through the `commit` skill in this session, run the repository's gates on it as that skill defines them before presenting the command.
5. Account for anything else the operation would publish: release or pull request metadata, bodies, assets, tags, and configured push options or client-side hooks.
6. Present the binding, the commit list with ids, the review result, and the exact command bound to both ends of the review:

   ```
   git push <remote> <reviewed-id>:refs/heads/<branch> --force-with-lease=refs/heads/<branch>:<base-id>
   ```

   The lease makes the destination reject the push whenever its branch is not exactly the reviewed base, including a branch someone deleted or moved after the review, and it forces nothing when the base matches; it is the guard the review depends on, not a bypass. Any change to the bound values invalidates the result. H runs the command; the remaining steps start on H's next message.
7. After the push, confirm `git rev-parse refs/remotes/<remote>/<branch>` equals the reviewed id and `git status -sb` reports neither ahead nor behind, then report the pushed id. Any other state is reported exactly and stops for H's decision.
8. Run the repository's published verification when it defines one, `make verify-published REV=<reviewed-id>` or `npm run verify-published -- <reviewed-id>`: the target waits for the deployment behind the destination and confirms the published state carries the reviewed commit. Report its result; a repository without the target is reported as pushed without published verification. Then report completion.
