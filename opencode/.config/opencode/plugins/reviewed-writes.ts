import path from "node:path"
import type { Plugin } from "@opencode-ai/plugin"

const PATCH_BEGIN = "*** Begin Patch"
const PATCH_END = "*** End Patch"
const PATCH_HEADERS = ["*** Add File:", "*** Delete File:", "*** Update File:"] as const
const MOVE_HEADER = "*** Move to:"

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
      }
    },
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
