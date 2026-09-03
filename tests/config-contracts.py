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
load_json("opencode/.config/opencode/tui.json")

print("ok: configuration authority boundaries")
