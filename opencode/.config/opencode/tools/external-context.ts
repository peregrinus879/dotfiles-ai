import fs from "node:fs"
import os from "node:os"
import path from "node:path"

type ToolContext = {
  agent: string
  worktree: string
  abort: AbortSignal
  ask(input: {
    permission: string
    patterns: string[]
    always: string[]
    metadata: Record<string, unknown>
  }): Promise<void>
}

type ToolArgs = { operation: "read" | "list"; path: string }

const MAX_FILE_BYTES = 256 * 1024
const MAX_DIRECTORY_ENTRIES = 128
const MAX_OUTPUT_BYTES = 32 * 1024
const MAX_NAME_BYTES = 1024
const SENSITIVE = /^(?:\.git|\.env(?:[._~-].*)?|\.(?:netrc|npmrc|pypirc)(?:[._~-].*)?|auth\.json(?:[._~-].*)?|secrets?(?:[._~-].*)?|.*credentials.*|.*\.(?:key|pem|p12|pfx)(?:[._~-].*)?|id_(?:rsa|dsa|ecdsa|ed25519)(?:[._~-].*)?)$/i

function contained(root: string, target: string) {
  const relative = path.relative(root, target)
  return relative === "" || (relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative))
}

function assertLexicalPathSafe(target: string) {
  const components = target.slice(path.parse(target).root.length).split(path.sep).filter(Boolean)
  for (const component of components) {
    if (Buffer.byteLength(component) > MAX_NAME_BYTES || /[\u0000-\u001f\u007f"'\\]/.test(component)) {
      throw new Error("external context rejected: unsupported path spelling")
    }
    if (SENSITIVE.test(component)) throw new Error("external context rejected: sensitive-shaped path")
  }

  const home = os.homedir()
  for (const root of [
    "/dev",
    "/proc",
    "/run",
    "/sys",
    path.join(home, ".aws"),
    path.join(home, ".config/gh"),
    path.join(home, ".docker"),
    path.join(home, ".gnupg"),
    path.join(home, ".kube"),
    path.join(home, ".ssh"),
  ]) {
    if (contained(root, target)) throw new Error("external context rejected: protected path")
  }
  if (/^\/var\/tmp\/spar-[^/]+(?:\/|$)/.test(target)) {
    throw new Error("external context rejected: use the managed spar handoff tools")
  }
}

function assertReady(context: ToolContext) {
  if (context.abort.aborted) throw new Error("external context request aborted")
}

function assertStablePath(target: string) {
  const info = fs.lstatSync(target)
  if (info.isSymbolicLink() || fs.realpathSync(target) !== target) {
    throw new Error("external context rejected: symlinks are unsupported")
  }
  return info
}

function readFile(target: string) {
  const before = assertStablePath(target)
  if (!before.isFile() || before.nlink !== 1 || before.size > MAX_FILE_BYTES) {
    throw new Error("external context rejected: expected a bounded regular single-link file")
  }

  const fd = fs.openSync(target, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW)
  try {
    const opened = fs.fstatSync(fd)
    if (
      !opened.isFile() ||
      opened.nlink !== 1 ||
      opened.size > MAX_FILE_BYTES ||
      before.dev !== opened.dev ||
      before.ino !== opened.ino
    ) {
      throw new Error("external context rejected: file metadata changed")
    }
    const data = fs.readFileSync(fd)
    const after = fs.fstatSync(fd)
    if (opened.dev !== after.dev || opened.ino !== after.ino || opened.size !== after.size || after.nlink !== 1) {
      throw new Error("external context rejected: file metadata changed")
    }
    const output = new TextDecoder("utf-8", { fatal: true }).decode(data)
    if (output.includes("\0")) throw new Error("external context rejected: binary content")
    return output
  } finally {
    fs.closeSync(fd)
  }
}

function listDirectory(target: string, context: ToolContext) {
  const root = assertStablePath(target)
  if (!root.isDirectory()) throw new Error("external context rejected: expected a directory")

  const entries: string[] = []
  const rootFd = fs.openSync(
    target,
    fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW,
  )
  const opened = fs.fstatSync(rootFd)
  if (!opened.isDirectory() || root.dev !== opened.dev || root.ino !== opened.ino) {
    fs.closeSync(rootFd)
    throw new Error("external context rejected: directory metadata changed")
  }
  let directory: fs.Dir | undefined
  try {
    directory = fs.opendirSync(`/proc/self/fd/${rootFd}`)
    while (true) {
      assertReady(context)
      const entry = directory.readSync()
      if (!entry) break
      if (entries.length >= MAX_DIRECTORY_ENTRIES) {
        throw new Error("external context rejected: directory exceeds the entry bound")
      }
      assertLexicalPathSafe(path.join(target, entry.name))
      const child = path.join(target, entry.name)
      const info = assertStablePath(child)
      if (info.isFile() && info.nlink !== 1) {
        throw new Error("external context rejected: directory contains a hard-linked file")
      }
      if (!info.isFile() && !info.isDirectory()) {
        throw new Error("external context rejected: directory contains an unsupported entry type")
      }
      entries.push(`${info.isDirectory() ? "directory" : "file"}\t${entry.name}`)
    }
  } finally {
    try {
      directory?.closeSync()
    } finally {
      fs.closeSync(rootFd)
    }
  }
  entries.sort()
  const output = entries.length ? `${entries.join("\n")}\n` : "<empty directory>\n"
  if (Buffer.byteLength(output) > MAX_OUTPUT_BYTES) {
    throw new Error("external context rejected: directory output exceeds the byte bound")
  }
  return output
}

export default {
  description: "Read one explicitly named non-sensitive external text file, or list one external directory level. Never use for workspace paths, sensitive data, writes, recursion, or delegated work.",
  args: {
    operation: {
      type: "string",
      enum: ["read", "list"],
      description: "Read one file or list one directory level.",
    },
    path: {
      type: "string",
      description: "Normalized absolute path explicitly named by H for the current task.",
    },
  },
  async execute(args: ToolArgs, context: ToolContext) {
    if (context.agent !== "build") throw new Error("external context is available only to the primary build agent")
    if (!args || !["read", "list"].includes(args.operation) || typeof args.path !== "string" || !path.isAbsolute(args.path)) {
      throw new Error("external context requires a valid operation and absolute path")
    }

    const target = path.normalize(args.path)
    if (target !== args.path) throw new Error("external context requires normalized path spelling")
    assertLexicalPathSafe(target)
    if (contained(path.normalize(context.worktree), target)) {
      throw new Error("external context rejected: use native tools for workspace paths")
    }
    assertReady(context)
    await context.ask({
      permission: "external_context",
      patterns: [target],
      always: [],
      metadata: { operation: args.operation, path: target },
    })
    assertReady(context)

    return {
      title: `${args.operation === "read" ? "Read" : "List"} external context`,
      output: args.operation === "read" ? readFile(target) : listDirectory(target, context),
      metadata: { operation: args.operation, path: target },
    }
  },
}
