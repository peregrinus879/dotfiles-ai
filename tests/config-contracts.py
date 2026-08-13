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
require(
    claude["permissions"]["allow"]
    == [
        "Bash(claude --version)",
        "Bash(codex --version)",
        "Bash(opencode --version)",
        "Bash(pacman -Q*)",
        "Bash(pacman -Si *)",
        "Bash(pacman -Ss *)",
        "Bash(spar-codex *)",
        "Bash(tree *)",
        "WebFetch(domain:github.com)",
        "WebFetch(domain:code.claude.com)",
        "WebFetch(domain:learn.chatgpt.com)",
        "WebFetch(domain:opencode.ai)",
        "WebFetch(domain:www.gnu.org)",
        "WebFetch(domain:arxiv.org)",
        "WebSearch",
    ],
    "Claude automatic allowlist drifted",
)
for rule in ("Bash(git push)", "Bash(git push *)"):
    require(rule in claude["permissions"]["deny"], f"Claude push deny drifted: {rule}")

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
    "~/.claude/.credentials.json",
    "~/.config/gh/hosts.yml",
    "~/.codex/auth.json",
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
require(".env.example" not in workspace, "Codex template exception weakens .env.* deny")

bash = opencode["permission"]["bash"]
bash_items = list(bash.items())
guard_index = next((index for index, item in enumerate(bash_items) if item[0] == "* >*"), None)
require(guard_index is not None, "OpenCode redirect guard missing")
require(
    all(action != "allow" for _, action in bash_items[guard_index:]),
    "OpenCode allow appears after guard block",
)
require(bash["*"] == "ask", "OpenCode Bash catch-all drifted")
require(bash["spar-claude *"] == "allow", "OpenCode Claude bridge allow drifted")
require(
    [command for command, action in bash_items if action == "allow"]
    == [
        "claude --version",
        "codex --version",
        "git branch",
        "git branch --show-current",
        "git rev-parse --abbrev-ref @{upstream}",
        "git rev-parse --abbrev-ref HEAD",
        "git status",
        "ls",
        "opencode --version",
        "pacman -Q*",
        "pwd",
        "spar-claude *",
        "tree",
    ],
    "OpenCode metadata-only allowlist drifted",
)
for unsafe in ("gh api", "gh api *", "codex *", "claude -p *"):
    require(unsafe not in bash, f"Unsafe OpenCode Bash allow found: {unsafe}")
require(bash["git push"] == "deny" and bash["git push *"] == "deny", "OpenCode push deny drifted")
require(opencode["permission"]["webfetch"] == "ask", "OpenCode WebFetch must remain review-gated")

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
require(".env.example" not in read_rules, "OpenCode template exception weakens .env.* deny")
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
for path in ("~/.claude/.credentials.json", "~/.codex/auth.json"):
    require(read_rules[path] == "deny", f"OpenCode credential read deny drifted: {path}")
    require(external_rules[path] == "deny", f"OpenCode credential external deny drifted: {path}")

claude_denies = set(claude["permissions"]["deny"])
for rule in ("Read(~/.claude/.credentials.json)", "Read(~/.codex/auth.json)"):
    require(rule in claude_denies, f"Claude credential read deny drifted: {rule}")
require("Read(./.env.*)" in claude_denies, "Claude .env.* read deny drifted")

require(
    claude_project == {"$schema": "https://json.schemastore.org/claude-code-settings.json"},
    "Claude project config must not grant mutable repository commands",
)
require(
    opencode_project == {"$schema": "https://opencode.ai/config.json"},
    "OpenCode project config must not grant mutable repository commands",
)

print("ok: config syntax and security contracts")
