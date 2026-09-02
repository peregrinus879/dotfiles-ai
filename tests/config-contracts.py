#!/usr/bin/env python3
"""Check the authority boundaries of the managed tool configurations.

These checks parse the deployed configuration files and assert the boundaries
that AGENTS.md promises: automatic modes stay bounded, pushes and privilege
escalation stay denied, credential stores stay unreadable, and permission
ordering keeps later denies effective. Wording, key order, and implementation
shape are deliberately not pinned.
"""

from __future__ import annotations

import json
import os
import tomllib
from pathlib import Path

ROOT = Path(os.environ.get("CONFIG_CONTRACT_ROOT", Path(__file__).resolve().parent.parent))

CREDENTIAL_STORES = (
    "~/.aws",
    "~/.claude/.credentials.json",
    "~/.codex/auth.json",
    "~/.config/gh/hosts.yml",
    "~/.docker/config.json",
    "~/.gnupg",
    "~/.kube",
    "~/.local/share/opencode/auth.json",
    "~/.netrc",
    "~/.npmrc",
    "~/.pypirc",
    "~/.ssh",
)
DESTRUCTIVE_GIT = (
    "git checkout -- *",
    "git clean *",
    "git push",
    "git push *",
    "git reset *",
    "git restore *",
    "git stash clear *",
    "git stash drop *",
)
PRIVILEGE = ("doas *", "pkexec *", "su *", "sudo *")
REPOSITORY_HOST = (
    "gh api *",
    "gh issue create*",
    "gh pr create*",
    "gh pr merge*",
    "gh release create*",
)


def load_json(path: str):
    with (ROOT / path).open(encoding="utf-8") as handle:
        return json.load(handle)


def load_toml(path: str):
    with (ROOT / path).open("rb") as handle:
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


# Claude Code
claude = load_json("claude-code/.claude/settings.json")
permissions = claude["permissions"]
require(permissions["defaultMode"] == "auto", "Claude default mode is not auto")
require(permissions["disableBypassPermissionsMode"] == "disable", "Claude bypass mode is enabled")
require("sandbox" not in claude, "Claude tracked settings enable sandboxing")
require("$defaults" in claude["autoMode"]["hard_deny"], "Claude auto mode dropped the built-in hard denies")
claude_deny = set(permissions["deny"])
for command in (*DESTRUCTIVE_GIT, *PRIVILEGE, *REPOSITORY_HOST):
    require(f"Bash({command})" in claude_deny, f"Claude deny missing: {command}")
for path in CREDENTIAL_STORES:
    require(
        f"Read({path})" in claude_deny or f"Read({path}/**)" in claude_deny,
        f"Claude credential store readable: {path}",
    )
for rule in ("Read(//**/.env)", "Read(//**/.env.*)", "Read(//**/secrets/**)", "Read(//**/*.key)", "Read(//**/*.pem)"):
    require(rule in claude_deny, f"Claude credential-shaped read deny missing: {rule}")
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
    for path in CREDENTIAL_STORES:
        require(filesystem.get(path) == "deny", f"{label} credential store readable: {path}")
    for path in ("~/**/.env", "~/**/.env.*", "~/**/secrets", "~/**/*.key", "~/**/*.pem"):
        require(filesystem.get(path) == "deny", f"{label} credential-shaped deny missing: {path}")
    workspace = filesystem[":workspace_roots"]
    require(workspace["."] == "write", f"{label} workspace is not writable")
    for path in (".env", ".env.*", "secrets", "**/*.key", "**/*.pem"):
        require(workspace.get(path) == "deny", f"{label} workspace credential deny missing: {path}")
    policy = config["auto_review"]["policy"]
    require("explicitly approves the exact candidate" in policy, f"{label} auto review no longer gates commits")


check_codex(codex_template, "Codex portable template")

# OpenCode
opencode = load_json("opencode/.config/opencode/opencode.json")
require(opencode["share"] == "disabled", "OpenCode sharing is enabled")
require(opencode["autoupdate"] is False, "OpenCode autoupdate competes with the wrapper")
bash = opencode["permission"]["bash"]
require(next(iter(bash.items())) == ("*", "allow"), "OpenCode Bash autonomy catch-all is not first")
require("ask" not in bash.values(), "OpenCode Bash reintroduced prompts")
for command in (*DESTRUCTIVE_GIT, *PRIVILEGE, *REPOSITORY_HOST, "claude *", "codex *", "opencode *"):
    require(bash.get(command) == "deny", f"OpenCode Bash deny missing: {command}")
read_rules = opencode["permission"]["read"]
edit_rules = opencode["permission"]["edit"]
external_rules = opencode["permission"]["external_directory"]
require(read_rules["*"] == "allow" and edit_rules["*"] == "allow", "OpenCode workspace autonomy drifted")
require(external_rules["*"] == "ask", "OpenCode external directories no longer ask")
for path in CREDENTIAL_STORES:
    covered = any(
        rules.get(candidate) == "deny"
        for rules in (read_rules, external_rules)
        for candidate in (path, f"{path}/**")
    )
    require(covered, f"OpenCode credential store reachable: {path}")
for path in ("**/.env", "**/.env.*", "**/secrets/**", "**/*.key", "**/*.pem", "**/auth.json"):
    require(read_rules.get(path) == "deny", f"OpenCode credential-shaped read deny missing: {path}")
for path in ("**/*.key", "**/*.pem", ".env", "secrets/**"):
    require(edit_rules.get(path) == "deny", f"OpenCode credential-shaped edit deny missing: {path}")
for label, rules in (("read", read_rules), ("edit", edit_rules), ("external_directory", external_rules)):
    allows_precede_denies(rules, label)
for path in ("/tmp*", "/tmp/*", "/tmp/**"):
    require(external_rules.get(path) != "allow", f"OpenCode broad temporary-directory allow: {path}")
require("build" not in opencode.get("agent", {}), "OpenCode build agent overrides global policy")
load_json("opencode/.config/opencode/tui.json")
load_json("opencode/.config/opencode/plugins/package.json")

# Project placeholders stay inert.
require(
    load_json(".claude/settings.json") == {"$schema": "https://json.schemastore.org/claude-code-settings.json"},
    "Claude project config grants something",
)
require(
    load_json("opencode.json") == {"$schema": "https://opencode.ai/config.json"},
    "OpenCode project config grants something",
)

print("ok: configuration authority boundaries")
