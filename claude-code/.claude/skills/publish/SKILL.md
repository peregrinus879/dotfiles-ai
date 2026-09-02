---
name: publish
description: Review the exact commits a push, release, or pull request would expose before presenting it as ready.
---

# Publish

Run this before presenting any push, release, pull request, or other publication as ready, including when no new commit is needed. H performs the push.

1. Bind the operation: the destination (H's explicit destination, else the branch's single configured upstream; ask if ambiguous), the audience (H's declared audience, else world-readable), the local ref with its commit id, and the exact refspec. Never read or display endpoint credentials.
2. Determine the delta as the commits in `<tracking-ref>..HEAD`, using the local tracking ref as the last known destination tip. Do not fetch unasked; state that the tracking ref is the assumed base. Review complete history only for a first publication, a destination without a tracking ref, or an audience expansion.
3. Review every commit in the delta: message, author identity, and every changed path's content, including files later deleted, for the commit skill's privacy classes. Report only metadata for binary or unreadable files and ask H to inspect them in a separate pane. Any unresolved finding blocks readiness.
4. Account for anything else the operation would publish: release or pull request metadata, bodies, assets, tags, and configured push options or client-side hooks.
5. Present the binding, the commit list with ids, the review result, and the exact command bound to the reviewed commit, for example `git push origin <commit-id>:refs/heads/main`. A fast-forward push is rejected by the destination if the assumed base is stale, which is the intended guard. Any change to the bound values invalidates the result.
