import fs from "node:fs"
import { ReviewedWritesPlugin } from "../opencode/.config/opencode/plugins/reviewed-writes.ts"

const testRoot = fs.mkdtempSync("/tmp/reviewed-writes-")
const workspace = `${testRoot}/workspace`
const outside = `${testRoot}/outside`
fs.mkdirSync(workspace)
fs.mkdirSync(outside)
const hook = (await ReviewedWritesPlugin({ directory: workspace }))["tool.execute.before"]

async function expectToolAccepted(name, tool, args) {
  try {
    await hook({ tool }, { args })
  } catch (error) {
    throw new Error(`${name} was rejected: ${error.message}`)
  }
}

async function expectToolRejected(name, tool, args, expected) {
  try {
    await hook({ tool }, { args })
  } catch (error) {
    if (expected && !error.message.includes(expected)) {
      throw new Error(`${name} failed for the wrong reason: ${error.message}`)
    }
    return
  }
  throw new Error(`${name} was accepted`)
}

const expectAccepted = (name, patchText) => expectToolAccepted(name, "apply_patch", { patchText })
const expectRejected = (name, patchText, expected) =>
  expectToolRejected(name, "apply_patch", { patchText }, expected)
const expectEditAccepted = (name, filePath) => expectToolAccepted(name, "edit", { filePath })
const expectEditRejected = (name, filePath) => expectToolRejected(name, "edit", { filePath })
const expectWriteAccepted = (name, filePath) => expectToolAccepted(name, "write", { filePath })

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

fs.writeFileSync(`${workspace}/delete.txt`, "delete\n")
await expectAccepted("grouped delete and add", `*** Begin Patch
*** Delete File: delete.txt
*** Add File: added.txt
+added
*** End Patch`)

await expectAccepted("grouped adds and updates", `*** Begin Patch
*** Add File: one.txt
+one
*** Update File: two.txt
@@
-old
+new
*** End Patch`)

await expectAccepted("grouped move and add", `*** Begin Patch
*** Update File: old.txt
*** Move to: new.txt
@@
-old
+new
*** Add File: other.txt
+other
*** End Patch`)

await expectAccepted("non-sensitive prose names", `*** Begin Patch
*** Add File: credentials-policy.md
+policy
*** Add File: secrets-review/notes.md
+notes
*** Add File: example.env
+placeholder
*** Add File: private.pem.txt
+public
*** End Patch`)

await expectRejected("sensitive second target", `*** Begin Patch
*** Add File: safe.txt
+safe
*** Add File: nested/.env.local
+blocked
*** End Patch`, "sensitive target")

for (const target of [".env", "nested/.env.production", "private.key", "private.pem", "docs/secrets/data.txt"]) {
  await expectRejected(`sensitive target ${target}`, `*** Begin Patch
*** Add File: ${target}
+blocked
*** End Patch`, "sensitive target")
}

await expectRejected("relative workspace escape", `*** Begin Patch
*** Add File: ../outside/escaped.txt
+blocked
*** End Patch`, "escapes the workspace")

await expectRejected("external second target", `*** Begin Patch
*** Add File: safe.txt
+safe
*** Add File: ${outside}/escaped.txt
+blocked
*** End Patch`, "escapes the workspace")

fs.writeFileSync(`${outside}/existing.txt`, "outside\n")
fs.symlinkSync(outside, `${workspace}/escape`)
fs.symlinkSync(`${outside}/missing.txt`, `${workspace}/dangling-escape`)
fs.mkdirSync(`${workspace}/real`)
fs.writeFileSync(`${workspace}/real/inside.txt`, "inside\n")
fs.symlinkSync(`${workspace}/real`, `${workspace}/inside-alias`)

await expectAccepted("contained symlink alias", `*** Begin Patch
*** Update File: inside-alias/inside.txt
@@
-inside
+updated
*** End Patch`)

await expectRejected("existing symlink escape", `*** Begin Patch
*** Update File: escape/existing.txt
@@
-outside
+blocked
*** End Patch`, "through an alias")

await expectRejected("symlink escape as second target", `*** Begin Patch
*** Add File: safe.txt
+safe
*** Update File: escape/existing.txt
@@
-outside
+blocked
*** End Patch`, "through an alias")

await expectRejected("dangling symlink escape", `*** Begin Patch
*** Add File: dangling-escape
+blocked
*** End Patch`, "through an alias")

fs.writeFileSync(`${workspace}/linked.txt`, "linked\n")
fs.linkSync(`${workspace}/linked.txt`, `${workspace}/linked-alias.txt`)
await expectRejected("hard-linked target", `*** Begin Patch
*** Update File: linked-alias.txt
@@
-linked
+blocked
*** End Patch`, "regular single-link file")

await expectRejected("hard-linked delete target", `*** Begin Patch
*** Delete File: linked-alias.txt
*** End Patch`, "regular single-link file")

await expectRejected("hard link as second target", `*** Begin Patch
*** Add File: safe.txt
+safe
*** Update File: linked-alias.txt
@@
-linked
+blocked
*** End Patch`, "regular single-link file")

await expectRejected("unsafe move destination", `*** Begin Patch
*** Update File: old.txt
*** Move to: escape/moved.txt
@@
-old
+new
*** End Patch`, "through an alias")

await expectRejected("external move destination", `*** Begin Patch
*** Update File: old.txt
*** Move to: ../outside/moved.txt
@@
-old
+new
*** End Patch`, "escapes the workspace")

await expectRejected("sensitive move destination", `*** Begin Patch
*** Update File: old.txt
*** Move to: secrets/moved.txt
@@
-old
+new
*** End Patch`, "sensitive target")

await expectRejected("hard-linked move destination", `*** Begin Patch
*** Update File: old.txt
*** Move to: linked-alias.txt
@@
-old
+new
*** End Patch`, "regular single-link file")

await expectRejected("unrecognized directive", `*** Begin Patch
*** Copy File: one.txt
*** End Patch`)
await expectRejected("empty path", `*** Begin Patch
*** Add File:
+content
*** End Patch`)
await expectRejected("orphan move destination", `*** Begin Patch
*** Move to: new.txt
*** End Patch`)
await expectRejected("missing envelope", "*** Update File: one.txt")
await expectRejected("missing patch text", undefined)

await expectEditAccepted("ordinary external edit remains native-permission scoped", `${outside}/existing.txt`)
await expectWriteAccepted("ordinary sensitive write remains native-permission scoped", `${workspace}/.env`)

// Spar handoff containment: flat targets in a validated handoff pass; alias,
// symlink, and nested-path shapes are rejected before permission.
const handoff = `/var/tmp/spar-${crypto.randomUUID()}`
const siblingHandoff = `/var/tmp/spar-${crypto.randomUUID()}`
const aliasSource = `${siblingHandoff}/nested/alias-source.md`
const aliasWorkspace = workspace
try {
  fs.mkdirSync(handoff, { mode: 0o700 })
  fs.mkdirSync(siblingHandoff, { mode: 0o700 })
  fs.mkdirSync(`${siblingHandoff}/nested`, { mode: 0o700 })
  fs.writeFileSync(`${handoff}/spar-plan.md`, "plan\n", { mode: 0o600 })

  await expectEditAccepted("flat handoff edit", `${handoff}/spar-plan.md`)
  await expectEditAccepted("flat handoff new file", `${handoff}/spar-objections.md`)
  await expectEditRejected("reviewer manifest edit", `${handoff}/reviewer-id`)
  await expectEditRejected("reviewer instruction injection", `${handoff}/AGENTS.md`)
  await expectEditRejected("Claude instruction injection", `${handoff}/CLAUDE.md`)
  await expectEditRejected("sensitive handoff backup", `${handoff}/private.pem.bak`)
  await expectEditRejected("dotenv handoff backup", `${handoff}/.env_bak`)
  await expectEditRejected("mixed-case instruction injection", `${handoff}/Agents.md`)
  await expectEditRejected("PKCS handoff backup", `${handoff}/private.p12~`)
  await expectEditRejected("OpenSSH key backup", `${handoff}/id_ed25519.bak`)

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
*** End Patch`, "regular owner-owned single-link file")
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
  fs.rmSync(testRoot, { recursive: true, force: true })
}

console.log("ok: reviewed-writes validates every grouped patch target")
