import fs from "node:fs"
import path from "node:path"

// Validate every apply_patch source and move destination before OpenCode's
// native permission handling sees the call: each target must stay inside the
// workspace, lexically and after resolving existing symlinks, must not be a
// credential-shaped name, and, when it exists, must be a regular single-link
// file. This is a correctness guard for grouped patches, not containment;
// OpenCode has no sandbox.

type PluginInput = { directory: string }
type ToolInput = { tool?: unknown }
type ToolOutput = { args?: { patchText?: unknown } }

const PATCH_BEGIN = "*** Begin Patch"
const PATCH_END = "*** End Patch"
const PATCH_HEADERS = ["*** Add File:", "*** Delete File:", "*** Update File:"] as const
const MOVE_HEADER = "*** Move to:"
const PATCH_DOTENV = /^\.env(?:\..*)?$/i
const PATCH_PRIVATE_KEY = /\.(?:key|pem)$/i

export const ReviewedWritesPlugin = async ({ directory }: PluginInput) => {
  const workspaceRoot = path.resolve(directory)
  const canonicalWorkspaceRoot = fs.realpathSync(workspaceRoot)

  return {
    "tool.execute.before": async (input: ToolInput, output: ToolOutput) => {
      if (typeof input.tool !== "string" || input.tool.length === 0) {
        throw new Error("tool call requires a verifiable tool name")
      }
      if (input.tool !== "apply_patch") return
      const operations = parsePatchOperations(output.args?.patchText)
      const unique = new Set(operations.flat().map((target) => path.resolve(workspaceRoot, target)))
      for (const target of unique) assertPatchTargetSafe(target)
    },
  }

  // Resolve existing symlinks and existing parent symlinks so a write through
  // an alias is judged by where it lands.
  function resolveWriteTarget(target: string) {
    let current = path.resolve(target)
    const suffix: string[] = []
    const seen = new Set<string>()
    while (true) {
      try {
        return path.join(fs.realpathSync(current), ...suffix)
      } catch {
        const currentStat = fs.lstatSync(current, { throwIfNoEntry: false })
        if (currentStat?.isSymbolicLink()) {
          if (seen.has(current)) throw new Error("write target rejected: symlink cycle")
          seen.add(current)
          const link = fs.readlinkSync(current)
          current = path.resolve(path.dirname(current), link)
          continue
        }
        if (currentStat) throw new Error("write target rejected: existing path could not be resolved")

        const parent = path.dirname(current)
        if (parent === current) return path.join(current, ...suffix)
        suffix.unshift(path.basename(current))
        current = parent
      }
    }
  }

  function isContained(root: string, target: string) {
    const relative = path.relative(root, target)
    return relative === "" || (relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative))
  }

  function assertWorkspaceTargetNotSensitive(root: string, target: string) {
    const parts = path.relative(root, target).split(path.sep).filter(Boolean)
    const name = parts.at(-1) ?? ""
    if (
      PATCH_DOTENV.test(name) ||
      PATCH_PRIVATE_KEY.test(name) ||
      parts.some((part) => part.toLowerCase() === "secrets")
    ) {
      throw new Error("apply_patch rejected: sensitive target")
    }
  }

  function assertPatchTargetSafe(target: string) {
    if (!isContained(workspaceRoot, target)) throw new Error("apply_patch rejected: target escapes the workspace")
    assertWorkspaceTargetNotSensitive(workspaceRoot, target)

    const resolved = resolveWriteTarget(target)
    if (!isContained(canonicalWorkspaceRoot, resolved)) {
      throw new Error("apply_patch rejected: target escapes the workspace through an alias")
    }
    assertWorkspaceTargetNotSensitive(canonicalWorkspaceRoot, resolved)

    const targetStat = fs.lstatSync(resolved, { throwIfNoEntry: false })
    if (targetStat && (!targetStat.isFile() || targetStat.nlink !== 1)) {
      throw new Error("apply_patch rejected: an existing target must be a regular single-link file")
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
