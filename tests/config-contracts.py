#!/usr/bin/env python3
"""Check the authority boundaries of the managed tool configurations.

These checks parse the deployed configuration files and assert the boundaries
that AGENTS.md promises: automatic modes stay bounded, pushes and privilege
escalation stay denied, credential stores are neither readable nor writable,
Git internals are not writable by file tools, destructive Git operations need
an explicit instruction, and permission ordering keeps later denies effective.
Wording, key order, and implementation shape are deliberately not pinned.
"""

from __future__ import annotations

import json
import os
import re
import tomllib
from pathlib import Path

ROOT = Path(os.environ.get("CONFIG_CONTRACT_ROOT", Path(__file__).resolve().parent.parent))

# Directory stores end with /** in Claude and OpenCode rules; file stores do not.
CREDENTIAL_DIRECTORIES = (
    "~/.aws",
    "~/.config/BraveSoftware",
    "~/.config/chromium",
    "~/.gnupg",
    "~/.kube",
    "~/.local/share/keyrings",
    "~/.mozilla",
    "~/.ssh",
)
CREDENTIAL_FILES = (
    "~/.bash_history",
    "~/.claude/.credentials.json",
    "~/.codex/auth.json",
    "~/.config/gh/hosts.yml",
    "~/.docker/config.json",
    "~/.local/share/opencode/auth.json",
    "~/.netrc",
    "~/.npmrc",
    "~/.pypirc",
    "~/.zsh_history",
)
CREDENTIAL_SHAPES = (
    ".env",
    ".env.*",
    ".netrc",
    ".npmrc",
    ".pypirc",
    "*.key",
    "*.p12",
    "*.pem",
    "*.pfx",
    "auth.json",
    "credentials",
    "credentials.*",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    "id_rsa",
    "secrets/**",
)
HARD_DENIED_GIT = ("git clean *", "git push", "git push *")
APPROVAL_GIT = (
    "git checkout -- *",
    "git reset *",
    "git restore *",
    "git stash clear *",
    "git stash drop *",
)
PRIVILEGE = ("doas *", "pkexec *", "su *", "sudo *")
REPOSITORY_HOST = (
    "gh gist create*",
    "gh issue create*",
    "gh pr create*",
    "gh pr merge*",
    "gh release create*",
)
REPOSITORY_HOST_EXTENDED = (
    "gh api *",
    "gh auth *",
    "gh gpg-key *",
    "gh repo create*",
    "gh repo delete*",
    "gh run cancel*",
    "gh secret *",
    "gh ssh-key *",
    "gh workflow run*",
)


def load_json(path: str):
    with (ROOT / path).open(encoding="utf-8") as handle:
        return json.load(handle)


def load_toml(path: str):
    with (ROOT / path).open("rb") as handle:
        return tomllib.load(handle)


def load_toml_file(path: str):
    with open(path, "rb") as handle:
        return tomllib.load(handle)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def allows_precede_denies(rules: dict, label: str) -> None:
    actions = list(rules.values())
    allows = [index for index, action in enumerate(actions) if action == "allow"]
    denies = [index for index, action in enumerate(actions) if action == "deny"]
    if allows and denies:
        require(max(allows) < min(denies), f"OpenCode {label}: an allow follows a deny and reopens it")


def covered(rules: set[str], tool: str, path: str) -> bool:
    """A store path is covered by an exact rule or by a /** rule on an ancestor."""
    candidates = {f"{tool}({path})", f"{tool}({path}/**)"}
    parts = path.split("/")
    for index in range(1, len(parts)):
        candidates.add(f"{tool}({'/'.join(parts[:index])}/**)")
    return bool(rules & candidates)


# Claude Code
claude = load_json("claude-code/.claude/settings.json")
permissions = claude["permissions"]
require(permissions["defaultMode"] == "auto", "Claude default mode is not auto")
require(permissions["disableBypassPermissionsMode"] == "disable", "Claude bypass mode is enabled")
require("sandbox" not in claude, "Claude tracked settings enable sandboxing")
require("$defaults" in claude["autoMode"]["hard_deny"], "Claude auto mode dropped the built-in hard denies")
claude_deny = set(permissions["deny"])
for command in (*HARD_DENIED_GIT, *PRIVILEGE, *REPOSITORY_HOST):
    require(f"Bash({command})" in claude_deny, f"Claude deny missing: {command}")
for command in APPROVAL_GIT:
    require(f"Bash({command})" not in claude_deny, f"Claude denies an approval-based Git command outright: {command}")
soft_denies = " ".join(claude["autoMode"]["soft_deny"])
for phrase in ("git reset", "git remote", "gh auth", "startup files"):
    require(phrase in soft_denies, f"Claude classifier rule missing for: {phrase}")
for path in (*CREDENTIAL_DIRECTORIES, *CREDENTIAL_FILES):
    require(covered(claude_deny, "Read", path), f"Claude credential store readable: {path}")
    require(covered(claude_deny, "Edit", path), f"Claude credential store writable: {path}")
for shape in CREDENTIAL_SHAPES:
    require(f"Read(//**/{shape})" in claude_deny, f"Claude credential-shaped read deny missing: {shape}")
    require(f"Edit(//**/{shape})" in claude_deny, f"Claude credential-shaped edit deny missing: {shape}")
for rule in claude_deny:
    if rule.startswith("Read(") and (rule.startswith("Read(~/") or rule.startswith("Read(//")):
        require(rule.replace("Read(", "Edit(", 1) in claude_deny or covered(claude_deny, "Edit", rule[5:-1]),
                f"Claude read deny has no write mirror: {rule}")
require("Edit(//**/.git/**)" in claude_deny and "Edit(~/.config/git/**)" in claude_deny, "Claude Git internals are writable")
for rule in permissions["allow"]:
    require(
        not rule.startswith(("Bash(git push", "Bash(gh ", "Bash(sudo")),
        f"Claude automatic allow reaches a guarded command: {rule}",
    )

# Codex
codex_template = load_toml("templates/codex/config.toml")


def check_codex(config: dict, label: str) -> None:
    require(config["default_permissions"] == "trusted-workspace", f"{label} default profile drifted")
    require(config["approvals_reviewer"] == "auto_review", f"{label} approval review drifted")
    require("sandbox_mode" not in config, f"{label} mixes legacy sandbox with permission profile")
    profile = config["permissions"]["trusted-workspace"]
    filesystem = profile["filesystem"]
    require(filesystem[":root"] == "deny", f"{label} filesystem root is not denied")
    require(profile["network"]["enabled"] is False, f"{label} command network is enabled")
    require(filesystem.get("~/.local/share/mise") == "read", f"{label} cannot execute mise-managed runtimes")
    for path in (*CREDENTIAL_DIRECTORIES, *CREDENTIAL_FILES):
        require(filesystem.get(path) == "deny", f"{label} credential store reachable: {path}")
    # OpenSSH keys live under ~/.ssh and the rc files are denied as literal
    # home paths; home-wide globs for them match files inside already denied
    # or runtime trees and break or slow sandbox startup.
    for shape in CREDENTIAL_SHAPES:
        name = shape.removesuffix("/**")
        if name.startswith("id_") or name in (".netrc", ".npmrc", ".pypirc"):
            require(f"~/**/{name}" not in filesystem, f"{label} home-wide glob breaks sandbox startup: {name}")
            continue
        require(filesystem.get(f"~/**/{name}") == "deny", f"{label} home deny missing: {shape}")
    workspace = filesystem[":workspace_roots"]
    require(workspace["."] == "write", f"{label} workspace is not writable")
    require(workspace.get(".git/config") == "read" and workspace.get(".git/hooks") == "read",
            f"{label} Git configuration or hooks are writable in the workspace")
    for shape in CREDENTIAL_SHAPES:
        name = shape.removesuffix("/**")
        require(workspace.get(f"**/{name}") == "deny", f"{label} workspace deny missing: {shape}")
        require(name not in workspace, f"{label} literal workspace entry creates placeholder files: {name}")
    policy = config["auto_review"]["policy"]
    require("explicitly approves the exact candidate" in policy, f"{label} auto review no longer gates commits")


check_codex(codex_template, "Codex portable template")
if os.environ.get("HOST_CODEX_CONFIG"):
    check_codex(load_toml_file(os.environ["HOST_CODEX_CONFIG"]), "host Codex config")

# OpenCode
opencode = load_json("opencode/.config/opencode/opencode.json")
require(opencode["share"] == "disabled", "OpenCode sharing is enabled")
require(opencode["autoupdate"] is False, "OpenCode autoupdate competes with the wrapper")
bash = opencode["permission"]["bash"]
require(next(iter(bash.items())) == ("*", "allow"), "OpenCode Bash autonomy catch-all is not first")
for command in (*HARD_DENIED_GIT, *PRIVILEGE, *REPOSITORY_HOST, *REPOSITORY_HOST_EXTENDED, "claude *", "codex *", "opencode *"):
    require(bash.get(command) == "deny", f"OpenCode Bash deny missing: {command}")
for command in (*APPROVAL_GIT, "git remote set-url *", "git config core.hooksPath*", "git config credential*"):
    require(bash.get(command) == "ask", f"OpenCode Bash approval missing: {command}")
read_rules = opencode["permission"]["read"]
edit_rules = opencode["permission"]["edit"]
external_rules = opencode["permission"]["external_directory"]
require(read_rules["*"] == "allow" and edit_rules["*"] == "allow", "OpenCode workspace autonomy drifted")
require(external_rules["*"] == "ask", "OpenCode external directories no longer ask")
# Read and edit subjects are worktree-relative; external subjects are parent
# directories. Credential stores under $HOME therefore rely on the external
# directory globs and the ask default, and worktree denies use **/ globs.
for path in CREDENTIAL_DIRECTORIES:
    glob = "**/" + path.removeprefix("~/") + "/**"
    require(external_rules.get(glob) == "deny", f"OpenCode external credential store deny missing: {glob}")
require(external_rules.get("**/.config/git/**") == "deny", "OpenCode Git configuration directory is reachable")
for shape in CREDENTIAL_SHAPES:
    require(read_rules.get(f"**/{shape}") == "deny", f"OpenCode credential-shaped read deny missing: {shape}")
    require(edit_rules.get(f"**/{shape}") == "deny", f"OpenCode credential-shaped edit deny missing: {shape}")
require(edit_rules.get("**/.git/**") == "deny", "OpenCode Git internals are writable by file tools")
for label, rules in (("read", read_rules), ("edit", edit_rules), ("external_directory", external_rules)):
    allows_precede_denies(rules, label)
for path in ("/tmp*", "/tmp/*", "/tmp/**"):
    require(external_rules.get(path) != "allow", f"OpenCode broad temporary-directory allow: {path}")
require("agent" not in opencode, "OpenCode agent overrides bypass global policy")
claude = load_json("claude-code/.claude/settings.json")
def frontmatter(path):
    """Parse the YAML subset the agent files use: top-level `key: value` and one nested block of `  key: value`."""
    text = path.read_text(encoding="utf-8")
    require(text.startswith("---\n"), f"agent file has no frontmatter: {path.name}")
    fields, nested, current = {}, {}, None
    for line in text.split("---\n", 2)[1].splitlines():
        if line.startswith("  ") and current:
            key, _, value = line.strip().partition(":")
            nested.setdefault(current, {})[key.strip()] = value.strip()
        elif ":" in line:
            key, _, value = line.partition(":")
            current = key.strip()
            fields[current] = value.strip()
    return fields, nested


claude_reviewer = ROOT / "claude-code/.claude/agents/reviewer.md"
require(claude_reviewer.is_file(), "Claude Code reviewer agent is missing")
fields, nested = frontmatter(claude_reviewer)
require(fields.get("name") == "reviewer", "Claude reviewer agent name drifted")
require(set(fields.get("tools", "").replace(",", " ").split()) == {"Read", "Grep", "Glob"}, "Claude reviewer agent is not exactly Read, Grep, Glob")
require(fields.get("model") == "fable" and fields.get("effort") == "xhigh", "Claude reviewer agent is not the strongest model at xhigh")
require(not ({"permissionMode", "hooks", "skills", "memory", "disallowedTools"} & set(fields)), "Claude reviewer agent carries authority-bearing fields")
for agent_file in (ROOT / "claude-code/.claude/agents").glob("*.md"):
    agent_fields, _ = frontmatter(agent_file)
    require(set(agent_fields.get("tools", "x").replace(",", " ").split()) <= {"Read", "Grep", "Glob"}, f"Claude agent is not read-only: {agent_file.name}")
    require(not ({"permissionMode", "hooks", "skills", "memory", "disallowedTools"} & set(agent_fields)), f"Claude agent carries authority-bearing fields: {agent_file.name}")

opencode_reviewer = ROOT / "opencode/.config/opencode/agents/reviewer.md"
require(opencode_reviewer.is_file(), "OpenCode reviewer agent is missing")
fields, nested = frontmatter(opencode_reviewer)
require(fields.get("mode") == "subagent", "OpenCode reviewer agent is not a subagent")
require(fields.get("model") == opencode["model"], "OpenCode reviewer agent does not run the configured primary model")
reviewer_model = fields["model"].split("/", 1)[1]
require(opencode["provider"]["openai"]["models"][reviewer_model]["options"]["reasoningEffort"] == "xhigh", "OpenCode reviewer model is not configured at xhigh")
require(nested.get("permission") == {"edit": "deny", "bash": "deny", "webfetch": "deny", "websearch": "deny", "task": "deny"}, "OpenCode reviewer agent does not deny exactly edit, bash, webfetch, websearch, task")
for agent_file in (ROOT / "opencode/.config/opencode/agents").glob("*.md"):
    _, agent_nested = frontmatter(agent_file)
    permissions = agent_nested.get("permission", {})
    require(permissions and all(value == "deny" for value in permissions.values()), f"OpenCode agent loosens or omits permissions: {agent_file.name}")
require(not (ROOT / "codex/.codex/agents").exists(), "a Codex agent role exists without a verified read-only authority profile")
require(claude.get("attribution", {}).get("sessionUrl") is False, "Claude Code would add a session URL trailer to commits")
require(codex_template.get("personality") == "none", "Codex personality filler is not disabled")
require(re.fullmatch(r"openai/[a-z0-9][a-z0-9.-]*", opencode.get("small_model", "")), "OpenCode small_model is not a concrete OpenAI model id")
require(opencode.get("skills", {}).get("paths") == ["~/.agents/skills"], "OpenCode skill paths are not exactly the neutral source")
load_json("opencode/.config/opencode/tui.json")


# Commit gate: every tool runs commit-gate before a shell command.
claude = load_json("claude-code/.claude/settings.json")
gate_hooks = [
    hook["command"]
    for entry in claude.get("hooks", {}).get("PreToolUse", [])
    if entry.get("matcher") == "Bash"
    for hook in entry.get("hooks", [])
    if hook.get("type") == "command"
]
require(any(command.endswith(".agents/hooks/commit-gate") for command in gate_hooks), "Claude Code does not run the installed commit-gate before Bash")
require(not any("\"if\"" in json.dumps(entry) for entry in claude.get("hooks", {}).get("PreToolUse", [])), "Claude Code narrows the gate hook with an if filter")
require("Edit(~/.agents/hooks/**)" in claude["permissions"]["deny"], "Claude Code file tools may edit the installed commit gate")
require(codex_template["features"].get("hooks") is True, "Codex hooks are not enabled, so commit-gate cannot run")
codex_gate = [
    hook["command"]
    for entry in codex_template.get("hooks", {}).get("PreToolUse", [])
    for hook in entry.get("hooks", [])
    if hook.get("type") == "command"
]
require(any(command.endswith(".agents/hooks/commit-gate") for command in codex_gate), "Codex does not run the installed commit-gate before a tool call")
require(edit_rules.get("**/.agents/hooks/**") == "deny", "OpenCode file tools may edit the installed commit gate")
require(external_rules.get("~/.agents/hooks/**") == "deny", "OpenCode may reach the installed commit gate")
require((ROOT / "opencode/.config/opencode/plugins/commit-gate.js").is_file(), "OpenCode commit-gate plugin is missing")
for skill, script in (("commit", "commit-candidate"), ("commit", "commit-apply"), ("publish", "publish-bind"), ("publish", "publish-verify")):
    require(os.access(ROOT / "agents/.agents/skills" / skill / "scripts" / script, os.X_OK), f"skill script missing or not executable: {skill}/scripts/{script}")
require(os.access(ROOT / "templates/hooks/commit-gate", os.X_OK), "templates/hooks/commit-gate is missing or not executable")

# Skills stay portable: the name matches the directory and only standard frontmatter fields appear.
STANDARD_SKILL_FIELDS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
for skill_dir in sorted((ROOT / "agents/.agents/skills").iterdir()):
    text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    require(text.startswith("---\n"), f"skill has no frontmatter: {skill_dir.name}")
    frontmatter = text.split("---\n", 2)[1]
    fields = {line.split(":", 1)[0].strip(): line.split(":", 1)[1].strip() for line in frontmatter.splitlines() if ":" in line and not line.startswith(" ")}
    require(fields.get("name") == skill_dir.name, f"skill name does not match its directory: {skill_dir.name}")
    require(bool(fields.get("description")), f"skill lacks a description: {skill_dir.name}")
    require(set(fields) <= STANDARD_SKILL_FIELDS, f"skill uses non-standard frontmatter fields: {skill_dir.name}: {set(fields) - STANDARD_SKILL_FIELDS}")

print("ok: configuration authority boundaries")
