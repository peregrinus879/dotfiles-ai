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
const siblingHandoff = `/var/tmp/spar-${crypto.randomUUID()}`
const aliasSource = `/var/tmp/reviewed-writes-alias-src-${process.pid}`
const aliasWorkspace = fs.mkdtempSync("/tmp/reviewed-writes-workspace-")
try {
  fs.mkdirSync(handoff, { mode: 0o700 })
  fs.mkdirSync(siblingHandoff, { mode: 0o700 })
  fs.writeFileSync(`${handoff}/spar-plan.md`, "plan\n", { mode: 0o600 })

  await expectEditAccepted("flat handoff edit", `${handoff}/spar-plan.md`)
  await expectEditAccepted("flat handoff new file", `${handoff}/spar-objections.md`)
  await expectEditRejected("reviewer manifest edit", `${handoff}/reviewer-id`)
  await expectEditRejected("reviewer instruction injection", `${handoff}/AGENTS.md`)
  await expectEditRejected("Claude instruction injection", `${handoff}/CLAUDE.md`)
  await expectEditRejected("sensitive handoff backup", `${handoff}/private.pem.bak`)

  fs.symlinkSync(handoff, `${aliasWorkspace}/handoff`)
  await expectEditAccepted("workspace alias to handoff content", `${aliasWorkspace}/handoff/spar-plan.md`)
  await expectEditRejected("workspace alias to reviewer manifest", `${aliasWorkspace}/handoff/reviewer-id`)
  await expectEditRejected(
    "workspace alias and parent traversal to reviewer manifest",
    `${aliasWorkspace}/handoff/../${siblingHandoff.split("/").at(-1)}/reviewer-id`,
  )
  await expectEditRejected(
    "missing component before normalized handoff alias",
    `${aliasWorkspace}/missing/../handoff/reviewer-id`,
  )
  fs.symlinkSync(`${handoff}/reviewer-id`, `${aliasWorkspace}/manifest-link`)
  await expectEditRejected("direct symlink to reviewer manifest", `${aliasWorkspace}/manifest-link`)
  fs.symlinkSync("/var/tmp", `${handoff}/out`)
  await expectEditRejected(
    "workspace alias entering and escaping handoff",
    `${aliasWorkspace}/handoff/out/reviewed-writes-escape-${process.pid}`,
  )
  fs.unlinkSync(`${handoff}/out`)

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
  fs.rmSync(siblingHandoff, { recursive: true, force: true })
  fs.rmSync(aliasSource, { force: true })
  fs.rmSync(aliasWorkspace, { recursive: true, force: true })
}

console.log("ok: reviewed-writes rejects grouped and malformed patches")
