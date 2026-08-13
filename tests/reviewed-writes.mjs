import { ReviewedWritesPlugin } from "../opencode/.config/opencode/plugins/reviewed-writes.ts"

const hook = (await ReviewedWritesPlugin({ directory: process.cwd() }))["tool.execute.before"]

async function expectAccepted(name, patchText) {
  try {
    await hook({ tool: "apply_patch" }, { args: { patchText } })
  } catch (error) {
    throw new Error(`${name} was rejected: ${error.message}`)
  }
}

async function expectRejected(name, patchText) {
  try {
    await hook({ tool: "apply_patch" }, { args: { patchText } })
  } catch {
    return
  }
  throw new Error(`${name} was accepted`)
}

await expectAccepted("one-file update", `*** Begin Patch
*** Update File: one.txt
@@
-old
+new
*** End Patch`)

await expectAccepted("one-file move", `*** Begin Patch
*** Update File: old.txt
*** Move to: new.txt
@@
-old
+new
*** End Patch`)

await expectRejected("two-file patch", `*** Begin Patch
*** Update File: one.txt
@@
-old
+new
*** Update File: two.txt
@@
-old
+new
*** End Patch`)

await expectRejected("move plus edit", `*** Begin Patch
*** Update File: old.txt
*** Move to: new.txt
@@
-old
+new
*** Update File: other.txt
@@
-old
+new
*** End Patch`)

await expectRejected("unrecognized directive", `*** Begin Patch
*** Copy File: one.txt
*** End Patch`)
await expectRejected("empty path", `*** Begin Patch
*** Add File:
+content
*** End Patch`)
await expectRejected("missing envelope", "*** Update File: one.txt")
await expectRejected("missing patch text", undefined)

console.log("ok: reviewed-writes rejects grouped and malformed patches")
