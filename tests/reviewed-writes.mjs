import fs from "node:fs"
import { ReviewedWritesPlugin } from "../opencode/.config/opencode/plugins/reviewed-writes.ts"

const hook = (await ReviewedWritesPlugin({ directory: process.cwd() }))["tool.execute.before"]

async function expectToolAccepted(name, tool, args) {
  try {
    await hook({ tool }, { args })
  } catch (error) {
    throw new Error(`${name} was rejected: ${error.message}`)
  }
}

async function expectToolRejected(name, tool, args) {
  try {
    await hook({ tool }, { args })
  } catch {
    return
  }
  throw new Error(`${name} was accepted`)
}

const expectAccepted = (name, patchText) => expectToolAccepted(name, "apply_patch", { patchText })
const expectRejected = (name, patchText) => expectToolRejected(name, "apply_patch", { patchText })
const expectEditAccepted = (name, filePath) => expectToolAccepted(name, "edit", { filePath })
const expectEditRejected = (name, filePath) => expectToolRejected(name, "edit", { filePath })

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

// Spar handoff containment: flat targets in a validated handoff pass; alias,
// symlink, and nested-path shapes are rejected before permission.
const handoff = `/var/tmp/spar-${crypto.randomUUID()}`
const aliasSource = `/var/tmp/reviewed-writes-alias-src-${process.pid}`
try {
  fs.mkdirSync(handoff, { mode: 0o700 })
  fs.writeFileSync(`${handoff}/spar-plan.md`, "plan\n", { mode: 0o600 })

  await expectEditAccepted("flat handoff edit", `${handoff}/spar-plan.md`)
  await expectEditAccepted("flat handoff new file", `${handoff}/spar-objections.md`)

  fs.writeFileSync(aliasSource, "persistent\n", { mode: 0o600 })
  fs.linkSync(aliasSource, `${handoff}/alias.md`)
  await expectEditRejected("hard-link alias inside handoff", `${handoff}/alias.md`)
  await expectRejected("apply_patch through hard-link alias", `*** Begin Patch
*** Update File: ${handoff}/alias.md
@@
-persistent
+tampered
*** End Patch`)
  fs.unlinkSync(`${handoff}/alias.md`)

  fs.symlinkSync("/var/tmp", `${handoff}/sub`)
  await expectEditRejected("symlinked subdirectory traversal", `${handoff}/sub/escape.md`)
  fs.unlinkSync(`${handoff}/sub`)

  fs.symlinkSync(aliasSource, `${handoff}/link.md`)
  await expectEditRejected("symlink target inside handoff", `${handoff}/link.md`)
  fs.unlinkSync(`${handoff}/link.md`)

  await expectEditRejected("spar-shaped non-uuid parent", "/var/tmp/spar-not-a-uuid/file.md")
  await expectEditRejected(
    "spar-shaped path outside /var/tmp",
    `${process.env.HOME}/var/tmp/spar-00000000-0000-4000-8000-000000000000/file.md`,
  )

  fs.chmodSync(handoff, 0o755)
  await expectEditRejected("wrong handoff mode", `${handoff}/spar-plan.md`)
  fs.chmodSync(handoff, 0o700)
} finally {
  fs.rmSync(handoff, { recursive: true, force: true })
  fs.rmSync(aliasSource, { force: true })
}

console.log("ok: reviewed-writes rejects grouped and malformed patches")
