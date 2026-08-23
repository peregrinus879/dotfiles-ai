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
opencode_package = load_json("opencode/.config/opencode/package.json")
opencode_lock = load_json("opencode/.config/opencode/package-lock.json")
load_json("opencode/.config/opencode/tui.json")
claude_project = load_json(".claude/settings.json")
opencode_project = load_json("opencode.json")
with (ROOT / "codex/.codex/config.toml").open("rb") as handle:
    codex = tomllib.load(handle)

openai_attribution = "Co-Authored-By: OpenAI {official display name of current model} <noreply@openai.com>"
model_display_rule = "Use the provider's official human-facing display name"
for path in (
    "codex/.agents/skills/commit/SKILL.md",
    "opencode/.config/opencode/skills/commit/SKILL.md",
):
    skill = (ROOT / path).read_text(encoding="utf-8")
    require(openai_attribution in skill, f"OpenAI commit attribution drifted: {path}")
    require(model_display_rule in skill, f"OpenAI model display rule drifted: {path}")

claude_skill = (ROOT / "claude-code/.claude/skills/commit/SKILL.md").read_text(encoding="utf-8")
claude_attribution = "Co-Authored-By: {official display name of current model} <noreply@anthropic.com>"
require(claude_attribution in claude_skill, "Claude commit attribution drifted")
require(model_display_rule in claude_skill, "Claude model display rule drifted")

require(claude["model"] == "claude-fable-5", "Claude model pin drifted")
require(
    claude["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == "max",
    "Claude maximum effort pin drifted",
)
require("effortLevel" not in claude, "Claude maximum effort must use the environment pin")
require(claude["permissions"]["defaultMode"] == "auto", "Claude default mode drifted")
require(claude["workflowSizeGuideline"] == "large", "Claude workflow guidance drifted")
# Per-file review is produced by the spar gate hook's deterministic ask
# fallback, not by bare ask-list entries: a matching ask rule overrides a hook
# allow, so bare Edit/Write/NotebookEdit entries would defeat the handoff
# exemption (anthropics/claude-code#35136 precedence).
for bare in ("Edit", "Write", "NotebookEdit"):
    require(
        bare not in claude["permissions"]["ask"],
        f"bare {bare} ask entry defeats the spar gate hook",
    )
hook_source = (ROOT / "claude-code/.claude/hooks/spar-handoff-approve.sh").read_text(
    encoding="utf-8"
)
for marker in (
    '"permissionDecision":"%s"',
    'emit ask "per-file review"',
    "gate_error",
    "exit 2",
    "stat -c '%h'",
    ".env | .env.* | *.key | *.pem | *credentials* | auth.json | secrets",
    "HANDOFF_RE='^/var/tmp/spar-",
):
    require(marker in hook_source, f"spar gate hook control drifted: {marker}")
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
    ],
    "Claude automatic allowlist drifted",
)
for rule in (
    "Bash(tree * --output *)",
    "Bash(tree * -o *)",
    "Bash(tree --output*)",
    "Bash(tree -o *)",
):
    require(rule in claude["permissions"]["deny"], f"Claude tree output deny drifted: {rule}")
for rule in ("Bash(git push)", "Bash(git push *)"):
    require(rule in claude["permissions"]["deny"], f"Claude push deny drifted: {rule}")
require(
    claude["hooks"]["PreToolUse"]
    == [
        {
            "matcher": "Edit|Write|NotebookEdit",
            "hooks": [
                {"type": "command", "command": "~/.claude/hooks/spar-handoff-approve.sh"}
            ],
        }
    ],
    "Claude spar handoff hook registration drifted",
)
require(
    os.access(ROOT / "claude-code/.claude/hooks/spar-handoff-approve.sh", os.X_OK),
    "Claude spar handoff hook missing or not executable",
)

# OpenCode's edit-permission subject is the worktree-relative path, so
# handoff rules use ../-anchored relative patterns; the external_directory
# subject is the parent directory joined with a literal *, so its allow uses
# the absolute prefix form.
HANDOFF_EDIT_ALLOW = "../*var/tmp/spar-*"
HANDOFF_EXTERNAL_ALLOW = "/var/tmp/spar-*"
HANDOFF_SENSITIVE_DENIES = (
    "../*var/tmp/spar-*/*.key",
    "../*var/tmp/spar-*/*.pem",
    "../*var/tmp/spar-*/*credentials*",
    "../*var/tmp/spar-*/.env",
    "../*var/tmp/spar-*/.env.*",
    "../*var/tmp/spar-*/auth.json",
    "../*var/tmp/spar-*/secrets/*",
)

codex_profile = codex["permissions"]["reviewed-writes"]
filesystem = codex_profile["filesystem"]
workspace = filesystem[":workspace_roots"]
require(codex["model"] == "gpt-5.6-sol", "Codex model pin drifted")
require(codex["model_reasoning_effort"] == "ultra", "Codex effort drifted")
require(codex["model_reasoning_summary"] == "auto", "Codex reasoning summary drifted")
require(codex["service_tier"] == "fast", "Codex Fast service tier drifted")
require(codex["web_search"] == "live", "Codex primary web search drifted")
require(codex["features"]["fast_mode"] is True, "Codex Fast feature drifted")
require(codex["agents"]["default_subagent_model"] == "gpt-5.6-sol", "Codex subagent model drifted")
require(
    codex["agents"]["default_subagent_reasoning_effort"] == "max",
    "Codex subagent effort drifted",
)
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
require(
    [command for command, action in bash_items if action == "allow"]
    == [
        "claude --version",
        "codex --version",
        "git branch",
        "git branch --show-current",
        "git diff",
        "git log",
        "git rev-parse --abbrev-ref @{upstream}",
        "git rev-parse --abbrev-ref HEAD",
        "git show",
        "git status",
        "ls",
        "opencode --version",
        "pacman -Q*",
        "pacman -Si *",
        "pacman -Ss *",
        "pwd",
        "spar-claude *",
    ],
    "OpenCode metadata-only allowlist drifted",
)
for command in ("tree -o *", "tree --output*", "tree * -o *", "tree * --output *"):
    require(bash[command] == "deny", f"OpenCode tree output deny drifted: {command}")
for unsafe in ("gh api", "gh api *", "codex *", "claude -p *"):
    require(unsafe not in bash, f"Unsafe OpenCode Bash allow found: {unsafe}")
require(bash["git push"] == "deny" and bash["git push *"] == "deny", "OpenCode push deny drifted")
require(opencode["permission"]["webfetch"] == "allow", "OpenCode WebFetch auto-read drifted")
require(opencode["permission"]["websearch"] == "allow", "OpenCode WebSearch drifted")
require(opencode["model"] == "openai/gpt-5.6-sol-fast", "OpenCode Fast model drifted")
require(opencode["share"] == "disabled", "OpenCode sharing drifted")
require(opencode["autoupdate"] is False, "OpenCode must not compete with wrapper-managed updates")
require(set(opencode["provider"]) == {"openai"}, "Unused OpenCode provider configured")
require(opencode["enabled_providers"] == ["openai"], "OpenCode enabled-provider gate drifted")
require(opencode_package["private"] is True, "OpenCode plugin package must remain private")
require(
    opencode["skills"]["paths"] == ["~/.claude/skills/omarchy"],
    "OpenCode explicit skill paths drifted",
)
require(
    all(
        name not in path
        for path in opencode["skills"]["paths"]
        for name in ("commit", "spar")
    ),
    "OpenCode re-imports colliding external workflow skills",
)
require(
    opencode_package["dependencies"]["@opencode-ai/plugin"] == "1.18.18",
    "OpenCode plugin dependency drifted",
)
require(
    opencode_lock["packages"][""]["dependencies"]["@opencode-ai/plugin"]
    == opencode_package["dependencies"]["@opencode-ai/plugin"],
    "OpenCode plugin lock drifted",
)
require(
    opencode_lock["packages"]["node_modules/@opencode-ai/plugin"]["version"]
    == opencode_package["dependencies"]["@opencode-ai/plugin"],
    "OpenCode resolved plugin version drifted",
)
require(
    opencode["provider"]["openai"]["models"]["gpt-5.6-sol-fast"]["options"]["reasoningEffort"]
    == "max",
    "OpenCode Fast max option drifted",
)
require(
    opencode["provider"]["openai"]["models"]["gpt-5.6-sol-fast"]["options"]["reasoningSummary"]
    == "auto",
    "OpenCode reasoning summary drifted",
)

edit_expected = {
    "*": "ask",
    HANDOFF_EDIT_ALLOW: "allow",
    "**/*.key": "deny",
    "**/*.pem": "deny",
    ".env": "deny",
    "secrets/**": "deny",
    "~/.aws/**": "deny",
    "~/.gnupg/**": "deny",
    **{path: "deny" for path in HANDOFF_SENSITIVE_DENIES},
}
require(
    list(opencode["permission"]["edit"].items()) == list(edit_expected.items()),
    "OpenCode edit map or its order drifted (catch-all, spar allow, denies last)",
)
require("build" not in opencode["agent"], "OpenCode build override bypasses global review")
plan_edit_expected = {
    "*": "deny",
    HANDOFF_EDIT_ALLOW: "allow",
    **{path: "deny" for path in HANDOFF_SENSITIVE_DENIES},
}
require(
    list(opencode["agent"]["plan"]["permission"]["edit"].items())
    == list(plan_edit_expected.items()),
    "OpenCode plan edit map or its order drifted",
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
# Liveness note (ledger-recorded, 1.18.18 subject semantics): directory-glob
# external entries are live; file-level external entries and the ~-keyed read
# entries can never match their subjects and are retained as
# forward-compatibility, so drift here still fails closed.
require(
    external_rules[HANDOFF_EXTERNAL_ALLOW] == "allow",
    "OpenCode spar external-directory allow drifted",
)
external_keys = list(external_rules)
require(
    external_keys.index(HANDOFF_EXTERNAL_ALLOW) > external_keys.index("*"),
    "OpenCode spar allow precedes the catch-all",
)
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
