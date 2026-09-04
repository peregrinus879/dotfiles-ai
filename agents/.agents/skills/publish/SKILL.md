---
name: publish
description: Review the exact commits a push, release, or pull request would expose before presenting it as ready.
---

# Publish

Run this before presenting any push, release, pull request, or other publication as ready, including when no new commit is needed. H runs the push command; the skill verifies the result afterwards. The `publish-bind` and `publish-verify` scripts carry the procedure.

1. Run `publish-bind [<ref>]`, default `HEAD`, or `publish-bind --remote <remote> --branch <branch>` when H names a destination. It resolves the destination from the branch's single configured upstream, the reviewed commit id, and the base as the destination branch's tracking ref, the last known destination tip, assumed without a fetch; it stops as destructive when the reviewed commit does not descend from the base, and that stop is presented to H as a destructive action for a separate ruling. It lists every commit in the delta with its identities and whether `commit-apply` made it, runs the payload scanner over the flat diff and over every commit's patch, lists the client-side hooks, push options, and tags the push would carry, and only when every check passes records the binding and prints the push command bound to both ends. The audience is H's declared audience, else world-readable. Never read or display endpoint credentials.
2. A scanner or identity finding blocks readiness until H rules on it. Review every commit in the delta for the commit skill's privacy classes, including files later deleted; report only metadata for binary or unreadable files and ask H to inspect them in a separate pane. Review complete history only for a first publication, a destination without a tracking ref, or an audience expansion.
3. Run the repository's gates, as the commit skill defines them, on the reviewed commit before presenting the command. The `commit-apply` marks are provenance, not a reason to skip: a commit made in an earlier session predates whatever the gates have become since.
4. Account for anything else the operation would publish: release or pull request metadata, bodies, and assets.
5. Present the binding, the commit list with ids, the review result, and the script's command:

   ```
   git -C <repository root> push <remote> <reviewed-id>:refs/heads/<branch> --force-with-lease=refs/heads/<branch>:<base-id>
   ```

   The `-C` argument names the repository root, so the command runs unchanged from whatever directory H's terminal is in. The lease makes the destination reject the push whenever its branch is not exactly the reviewed base, including a branch someone deleted or moved after the review, and it forces nothing when the base matches; it is the guard the review depends on, not a bypass. Any change to the bound values invalidates the result: rerun `publish-bind`. H runs the command; the remaining steps start on H's next message.
6. After the push, run `publish-verify`. It confirms the tracking ref equals the reviewed id and the branch is neither ahead nor behind, then runs the repository's published verification when it defines one, `make verify-published REV=<id>` or `npm run verify-published -- <id>`, which waits for the deployment behind the destination and confirms the published state carries the reviewed commit. Report the pushed id and the result; a repository without the target is reported as pushed without published verification. Any other state is reported exactly and stops for H's decision. Then report completion.
