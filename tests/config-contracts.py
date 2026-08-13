#!/usr/bin/env python3
import json
import os
import tomllib
from pathlib import Path

ROOT = Path(os.environ.get("CONFIG_CONTRACT_ROOT", Path(__file__).resolve().parent.parent))


def load_json(path: str):
    with (ROOT / path).open(encoding="utf-8") as handle:
        return json.load(handle)


def require(condition: bool, message: str):
    if not condition:
        raise AssertionError(message)


claude = load_json("claude-code/.claude/settings.json")
opencode = load_json("opencode/.config/opencode/opencode.json")
load_json("opencode/.config/opencode/tui.json")
claude_project = load_json(".claude/settings.json")
opencode_project = load_json("opencode.json")
with (ROOT / "codex/.codex/config.toml").open("rb") as handle:
    codex = tomllib.load(handle)

require(claude["model"] == "claude-fable-5", "Claude model pin drifted")
require(claude["permissions"]["defaultMode"] == "auto", "Claude default mode drifted")
require(
    {"Edit", "Write"}.issubset(claude["permissions"]["ask"]),
    "Claude persistent edit asks drifted",
)

codex_profile = codex["permissions"]["reviewed-writes"]
filesystem = codex_profile["filesystem"]
workspace = filesystem[":workspace_roots"]
require(codex["model"] == "gpt-5.6-sol", "Codex model pin drifted")
require(codex["model_reasoning_effort"] == "xhigh", "Codex effort drifted")
require(codex["approval_policy"] == "on-request", "Codex approval policy drifted")
require(codex["approvals_reviewer"] == "user", "Codex human reviewer drifted")
require(codex["default_permissions"] == "reviewed-writes", "Codex profile selection drifted")
require("sandbox_mode" not in codex, "Codex mixes legacy sandbox with permission profile")
require(codex_profile["extends"] == ":read-only", "Codex profile base drifted")
require(codex_profile["network"]["enabled"] is False, "Codex network deny drifted")
require(filesystem[":tmpdir"] == "write", "Codex temp permission drifted")
require(filesystem[":slash_tmp"] == "write", "Codex /tmp permission drifted")
require(filesystem["glob_scan_max_depth"] == 64, "Codex glob depth drifted")
for path in (
    "~/.aws",
    "~/.config/gh/hosts.yml",
    "~/.docker/config.json",
    "~/.gnupg",
    "~/.kube",
    "~/.local/share/opencode/auth.json",
    "~/.netrc",
    "~/.npmrc",
    "~/.pypirc",
    "~/.ssh",
):
    require(filesystem[path] == "deny", f"Codex sensitive deny drifted: {path}")
require(workspace["."] == "read", "Codex workspace read rule drifted")
for path in (".env", ".env.*", "secrets", "**/*.key", "**/*.pem", "**/*credentials*"):
    require(workspace[path] == "deny", f"Codex workspace deny drifted: {path}")
require(workspace[".env.example"] == "read", "Codex template policy drifted")

bash = opencode["permission"]["bash"]
bash_items = list(bash.items())
guard_index = next((index for index, item in enumerate(bash_items) if item[0] == "* > *"), None)
require(guard_index is not None, "OpenCode redirect guard missing")
require(
    all(action != "allow" for _, action in bash_items[guard_index:]),
    "OpenCode allow appears after guard block",
)
require(bash["*"] == "ask", "OpenCode Bash catch-all drifted")
require(bash["spar-claude *"] == "allow", "OpenCode Claude bridge allow drifted")
for unsafe in ("gh api", "gh api *", "codex *", "claude -p *"):
    require(unsafe not in bash, f"Unsafe OpenCode Bash allow found: {unsafe}")

edit_expected = {
    "*": "ask",
    "**/*.key": "deny",
    "**/*.pem": "deny",
    ".env": "deny",
    "secrets/**": "deny",
    "~/.aws/**": "deny",
    "~/.gnupg/**": "deny",
}
require(opencode["permission"]["edit"] == edit_expected, "OpenCode edit map drifted")
require("build" not in opencode["agent"], "OpenCode build override bypasses global review")
require(
    opencode["agent"]["plan"]["permission"]["edit"] == {"*": "deny"},
    "OpenCode plan edit deny drifted",
)

read_rules = opencode["permission"]["read"]
external_rules = opencode["permission"]["external_directory"]
require(read_rules["*"] == "allow", "OpenCode read default drifted")
require(read_rules[".env.example"] == "allow", "OpenCode template policy drifted")
for path in (
    ".env",
    ".env.*",
    "**/*.key",
    "**/*.pem",
    "**/*credentials*",
    "secrets/**",
    "~/.ssh/**",
):
    require(read_rules[path] == "deny", f"OpenCode read deny drifted: {path}")
require(external_rules["*"] == "ask", "OpenCode external-directory default drifted")
require(external_rules["~/.ssh/**"] == "deny", "OpenCode SSH external deny drifted")

require(
    claude_project["permissions"]["allow"] == ["Bash(make lint)", "Bash(make verify)"],
    "Claude project allowlist drifted",
)
require(
    opencode_project["permission"]["bash"] == {"make lint": "allow", "make verify": "allow"},
    "OpenCode project allowlist drifted",
)

print("ok: config syntax and security contracts")
