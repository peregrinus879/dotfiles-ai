import fs from "node:fs"
import path from "node:path"

type PluginInput = { directory: string }
type ToolInput = { tool?: unknown }
type ToolOutput = { args?: { patchText?: unknown; filePath?: unknown } }

const PATCH_BEGIN = "*** Begin Patch"
const PATCH_END = "*** End Patch"
const PATCH_HEADERS = ["*** Add File:", "*** Delete File:", "*** Update File:"] as const
const MOVE_HEADER = "*** Move to:"
const PATCH_DOTENV = /^\.env(?:\..*)?$/i
const PATCH_PRIVATE_KEY = /\.(?:key|pem)$/i
const SPAR_PARENT = /^\/var\/tmp\/spar-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/
const SPAR_TREE = /^\/var\/tmp\/spar-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}(?:\/|$)/
const SPAR_RESERVED = new Set([
  ".git",
  "agents.md",
  "agents.override.md",
  "claude.md",
  "claude.local.md",
  "reviewer-id",
])
const SPAR_SENSITIVE = /^(?:\.env(?:[._~-].*)?|\.(?:netrc|npmrc|pypirc)(?:[._~-].*)?|auth\.json(?:[._~-].*)?|secrets?(?:[._~-].*)?|.*credentials.*|.*\.(?:key|pem|p12|pfx)(?:[._~-].*)?|id_(?:rsa|dsa|ecdsa|ed25519)(?:[._~-].*)?)$/i

export const ReviewedWritesPlugin = async ({ directory }: PluginInput) => {
  const workspaceRoot = path.resolve(directory)
  const canonicalWorkspaceRoot = fs.realpathSync(workspaceRoot)
  const absoluteTarget = (target: string) =>
    path.isAbsolute(target) ? target : `${directory.replace(/\/+$/, "")}/${target}`
  const patchTarget = (target: string) => path.resolve(workspaceRoot, target)

  return {
    "tool.execute.before": async (input: ToolInput, output: ToolOutput) => {
      if (typeof input.tool !== "string" || input.tool.length === 0) {
        throw new Error("tool call requires a verifiable tool name")
      }
      if (input.tool === "apply_patch") {
        const operations = parsePatchOperations(output.args?.patchText)
        const unique = new Set(operations.flat().map(patchTarget))
        for (const target of unique) assertPatchTargetSafe(target)
      }
      if (input.tool === "edit" || input.tool === "write") {
        const filePath = output.args?.filePath
        if (typeof filePath !== "string" || filePath.length === 0) {
          throw new Error(`${input.tool} requires a verifiable filePath`)
        }
        assertSparTargetSafe(absoluteTarget(filePath))
      }
    },
  }

  // Resolve existing symlinks and existing parent symlinks before deciding
  // whether a write reaches a handoff, including through a workspace alias.
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

  function traversesSparHandoff(target: string) {
    const root = path.parse(target).root
    let current = root
    for (const part of target.slice(root.length).split(path.sep).filter(Boolean)) {
      current = `${current.replace(/\/$/, "")}/${part}`
      try {
        if (SPAR_TREE.test(fs.realpathSync(current))) return true
      } catch {
        break
      }
    }
    return false
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
    const lexicallyContained = isContained(workspaceRoot, target)
    if (lexicallyContained) assertWorkspaceTargetNotSensitive(workspaceRoot, target)
    if (assertSparTargetSafe(target)) return
    if (!lexicallyContained) throw new Error("apply_patch rejected: target escapes the workspace")

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

  // Alias-safe containment for spar handoff scratch writes: targets sit
  // directly inside a validated /var/tmp/spar-<uuid> directory, and an
  // existing target must be a regular, owner-owned, single-link file, so
  // hard-link aliases of persistent files and symlinked subdirectories are
  // rejected before the permission system sees the call.
  function assertSparTargetSafe(target: string) {
    let handoffTarget = false
    for (const candidate of new Set([target, path.normalize(target)])) {
      const resolved = resolveWriteTarget(candidate)
      if (traversesSparHandoff(candidate) && !SPAR_TREE.test(resolved)) {
        throw new Error("spar handoff write rejected: target escapes its handoff through an alias")
      }
      if (!resolved.startsWith("/var/tmp/spar-")) {
        if (/\/var\/tmp\/spar-/.test(candidate) || /\/var\/tmp\/spar-/.test(resolved)) {
          throw new Error("spar handoff write rejected: spar-shaped path outside /var/tmp")
        }
        continue
      }
      handoffTarget = true
      const parent = path.dirname(resolved)
      if (!SPAR_PARENT.test(parent)) {
        throw new Error("spar handoff write rejected: targets must sit directly inside /var/tmp/spar-<uuid>")
      }
      const name = path.basename(resolved)
      if (SPAR_RESERVED.has(name.toLowerCase()) || SPAR_SENSITIVE.test(name)) {
        throw new Error("spar handoff write rejected: bridge-owned, reviewer-instruction, or sensitive target")
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
    return handoffTarget
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
