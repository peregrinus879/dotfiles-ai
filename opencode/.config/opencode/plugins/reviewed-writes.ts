import fs from "node:fs"
import path from "node:path"
import type { Plugin } from "@opencode-ai/plugin"

const PATCH_BEGIN = "*** Begin Patch"
const PATCH_END = "*** End Patch"
const PATCH_HEADERS = ["*** Add File:", "*** Delete File:", "*** Update File:"] as const
const MOVE_HEADER = "*** Move to:"
const SPAR_PARENT = /^\/var\/tmp\/spar-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/

export const ReviewedWritesPlugin: Plugin = async ({ directory }) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "apply_patch") {
        const operations = parsePatchOperations(output.args?.patchText)
        const moves = operations.filter((operation) => operation.length === 2)
        const unique = new Set(operations.flat().map((target) => path.resolve(directory, target)))
        if ((moves.length > 0 && operations.length !== 1) || (moves.length === 0 && unique.size !== 1)) {
          throw new Error("apply_patch must modify exactly one file; split this patch into one call per file")
        }
        for (const target of unique) assertSparTargetSafe(target)
      }
      if ((input.tool === "edit" || input.tool === "write") && typeof output.args?.filePath === "string") {
        assertSparTargetSafe(path.resolve(directory, output.args.filePath))
      }
    },
  }

  // Alias-safe containment for spar handoff scratch writes: targets sit
  // directly inside a validated /var/tmp/spar-<uuid> directory, and an
  // existing target must be a regular, owner-owned, single-link file, so
  // hard-link aliases of persistent files and symlinked subdirectories are
  // rejected before the permission system sees the call.
  function assertSparTargetSafe(resolved: string) {
    if (!resolved.startsWith("/var/tmp/spar-")) {
      if (/\/var\/tmp\/spar-/.test(resolved)) {
        throw new Error("spar handoff write rejected: spar-shaped path outside /var/tmp")
      }
      return
    }
    const parent = path.dirname(resolved)
    if (!SPAR_PARENT.test(parent)) {
      throw new Error("spar handoff write rejected: targets must sit directly inside /var/tmp/spar-<uuid>")
    }
    const uid = process.getuid?.()
    const parentStat = fs.lstatSync(parent, { throwIfNoEntry: false })
    if (
      !parentStat ||
      parentStat.isSymbolicLink() ||
      !parentStat.isDirectory() ||
      parentStat.uid !== uid ||
      (parentStat.mode & 0o777) !== 0o700 ||
      fs.realpathSync(parent) !== parent
    ) {
      throw new Error("spar handoff write rejected: the handoff directory failed validation")
    }
    const targetStat = fs.lstatSync(resolved, { throwIfNoEntry: false })
    if (targetStat && (!targetStat.isFile() || targetStat.uid !== uid || targetStat.nlink !== 1)) {
      throw new Error("spar handoff write rejected: an existing target must be a regular owner-owned single-link file")
    }
  }

  function parsePatchOperations(value: unknown) {
    if (typeof value !== "string") throw new Error("apply_patch requires a verifiable patchText")

    const lines = value.replaceAll("\r\n", "\n").replaceAll("\r", "\n").trim().split("\n")
    if (lines[0] !== PATCH_BEGIN || lines.at(-1) !== PATCH_END) {
      throw new Error("apply_patch rejected: malformed patch envelope")
    }

    const operations: string[][] = []
    for (let index = 1; index < lines.length - 1; index++) {
      const line = lines[index]
      const header = PATCH_HEADERS.find((candidate) => line.startsWith(candidate))
      if (header) {
        const target = line.slice(header.length).trim()
        if (!target) throw new Error("apply_patch rejected: empty file path")
        const operation = [target]

        if (header === "*** Update File:" && lines[index + 1]?.startsWith(MOVE_HEADER)) {
          const moveTarget = lines[++index].slice(MOVE_HEADER.length).trim()
          if (!moveTarget) throw new Error("apply_patch rejected: empty move destination")
          operation.push(moveTarget)
        }
        operations.push(operation)
        continue
      }

      if (line.startsWith(MOVE_HEADER)) {
        throw new Error("apply_patch rejected: move destination without an update header")
      }
      if (line.startsWith("*** ") && line !== "*** End of File") {
        throw new Error(`apply_patch rejected: unrecognized patch directive: ${line}`)
      }
    }

    if (operations.length === 0) throw new Error("apply_patch rejected: no file operations found")
    return operations
  }
}
