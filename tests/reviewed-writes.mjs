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

try {
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

  await expectRejected("unsafe move destination", `*** Begin Patch
*** Update File: old.txt
*** Move to: escape/moved.txt
@@
-old
+new
*** End Patch`, "through an alias")

  await expectRejected("sensitive move destination", `*** Begin Patch
*** Update File: old.txt
*** Move to: secrets/moved.txt
@@
-old
+new
*** End Patch`, "sensitive target")

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
  await expectToolRejected("missing tool name", undefined, {}, "verifiable tool name")

  await expectToolAccepted("edit stays native-permission scoped", "edit", { filePath: `${outside}/existing.txt` })
  await expectToolAccepted("write stays native-permission scoped", "write", { filePath: `${workspace}/.env` })
} finally {
  fs.rmSync(testRoot, { recursive: true, force: true })
}

console.log("ok: reviewed-writes validates every grouped patch target")
