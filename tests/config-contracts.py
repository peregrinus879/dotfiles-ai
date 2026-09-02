#!/usr/bin/env python3
import ast
import json
import os
import runpy
import tomllib
from pathlib import Path

ROOT = Path(os.environ.get("CONFIG_CONTRACT_ROOT", Path(__file__).resolve().parent.parent))


def load_json(path: str):
    with (ROOT / path).open(encoding="utf-8") as handle:
        return json.load(handle)


def require(condition: bool, message: str):
    if not condition:
        raise AssertionError(message)


def require_recursive_subset(expected: dict, actual: dict, prefix: tuple[str, ...] = ()) -> None:
    for key, expected_value in expected.items():
        path = (*prefix, key)
        require(key in actual, f"tracked Codex runtime is missing portable key {'.'.join(path)}")
        actual_value = actual[key]
        if isinstance(expected_value, dict):
            require(isinstance(actual_value, dict), f"tracked Codex runtime table changed at {'.'.join(path)}")
            require_recursive_subset(expected_value, actual_value, path)
        else:
            require(actual_value == expected_value, f"tracked Codex runtime value changed at {'.'.join(path)}")


CODEX_PORTABLE_TOP_LEVEL_KEYS = frozenset(
    {
        "model",
        "model_reasoning_effort",
        "model_reasoning_summary",
        "service_tier",
        "web_search",
        "approval_policy",
        "approvals_reviewer",
        "default_permissions",
        "auto_review",
        "features",
        "agents",
        "permissions",
    }
)
CODEX_MANAGED_READ_PATHS = (
    "~/.claude/CLAUDE.md",
    "~/.claude/settings.json",
    "~/.claude/statusline.sh",
    "~/.claude/agents",
    "~/.claude/hooks",
    "~/.claude/rules",
    "~/.claude/skills/commit",
    "~/.claude/skills/spar",
    "~/.codex/AGENTS.md",
    "~/.codex/config.toml",
    "~/.agents/skills",
    "~/.config/opencode",
    "~/.local/bin",
)
CODEX_SENSITIVE_HOME_PATHS = (
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
)
CODEX_SENSITIVE_HOME_GLOBS = (
    "~/**/.env",
    "~/**/.env.*",
    "~/**/auth.json",
    "~/**/secrets",
    "~/**/secrets/**",
    "~/**/*.key",
    "~/**/*.pem",
    "~/**/*.p12",
    "~/**/*.pfx",
    "~/**/*credentials*",
)
CODEX_WORKSPACE_DENY_PATHS = (".env", ".env.*", "secrets", "**/*.key", "**/*.pem", "**/*credentials*")
CODEX_FILESYSTEM_KEYS = frozenset(
    {
        ":root",
        ":minimal",
        ":tmpdir",
        ":slash_tmp",
        "glob_scan_max_depth",
        ":workspace_roots",
        *CODEX_MANAGED_READ_PATHS,
        *CODEX_SENSITIVE_HOME_PATHS,
        *CODEX_SENSITIVE_HOME_GLOBS,
    }
)
CODEX_AUTO_REVIEW_POLICY = (
    "Approve only actions necessary for H's requested work. For request_permissions, approve turn-scoped filesystem "
    "reads needed to discover, inspect, search, or locally convert non-secret files or directories that H names or "
    "directs the agent to use; ordinary personal information and document formats are not credentials. Reject "
    "session-scoped grants, external writes, all other writes outside the workspace, subagent grants, secret or "
    "credential access, privileged actions, destructive state changes, uploads, remote mutations, and bypasses of "
    "safety checks. A local Git commit is eligible only after H explicitly approves the exact candidate in the "
    "conversation.\n"
)


def require_exact_keys(table: dict, expected: set[str] | frozenset[str], label: str) -> None:
    require(set(table) == expected, f"{label} key set changed")


def validate_codex_profile(config: dict, label: str, *, allow_top_level_extras: bool) -> None:
    if allow_top_level_extras:
        require(CODEX_PORTABLE_TOP_LEVEL_KEYS <= config.keys(), f"{label} lost a portable top-level key")
    else:
        require_exact_keys(config, CODEX_PORTABLE_TOP_LEVEL_KEYS, f"{label} top level")

    require_exact_keys(config["auto_review"], {"policy"}, f"{label} auto_review")
    require_exact_keys(
        config["features"],
        {"fast_mode", "js_repl", "request_permissions_tool"},
        f"{label} features",
    )
    require_exact_keys(
        config["agents"],
        {"default_subagent_model", "default_subagent_reasoning_effort"},
        f"{label} agents",
    )
    require_exact_keys(config["permissions"], {"trusted-workspace"}, f"{label} permissions")

    profile = config["permissions"]["trusted-workspace"]
    require_exact_keys(profile, {"description", "extends", "filesystem", "network"}, f"{label} profile")
    filesystem = profile["filesystem"]
    require_exact_keys(filesystem, CODEX_FILESYSTEM_KEYS, f"{label} filesystem")
    workspace = filesystem[":workspace_roots"]
    require_exact_keys(workspace, {".", *CODEX_WORKSPACE_DENY_PATHS}, f"{label} workspace roots")
    require_exact_keys(profile["network"], {"enabled"}, f"{label} network")

    for key, expected in (
        ("model", "gpt-5.6-sol"),
        ("model_reasoning_effort", "xhigh"),
        ("model_reasoning_summary", "auto"),
        ("service_tier", "fast"),
        ("web_search", "live"),
        ("approval_policy", "on-request"),
        ("approvals_reviewer", "auto_review"),
        ("default_permissions", "trusted-workspace"),
    ):
        require(config[key] == expected, f"{label} {key} drifted")

    require(config["features"]["fast_mode"] is True, f"{label} Fast feature drifted")
    require(config["features"]["js_repl"] is False, f"{label} js_repl drifted")
    require(
        config["features"]["request_permissions_tool"] is True,
        f"{label} external-context permission tool drifted",
    )
    require(config["agents"]["default_subagent_model"] == "gpt-5.6-sol", f"{label} subagent model drifted")
    require(
        config["agents"]["default_subagent_reasoning_effort"] == "xhigh",
        f"{label} subagent effort drifted",
    )

    policy = config["auto_review"]["policy"]
    require(policy == CODEX_AUTO_REVIEW_POLICY, f"{label} auto-review policy drifted")

    require("sandbox_mode" not in config, f"{label} mixes legacy sandbox with permission profile")
    require(
        isinstance(profile["description"], str) and profile["description"].strip(),
        f"{label} profile description is empty",
    )
    require(profile["extends"] == ":workspace", f"{label} profile base drifted")
    require(profile["network"]["enabled"] is False, f"{label} network deny drifted")
    require(filesystem[":root"] == "deny", f"{label} filesystem root deny drifted")
    require(filesystem[":minimal"] == "read", f"{label} runtime-minimal read drifted")
    require(filesystem[":tmpdir"] == "write", f"{label} temp permission drifted")
    require(filesystem[":slash_tmp"] == "write", f"{label} /tmp permission drifted")
    require(
        type(filesystem["glob_scan_max_depth"]) is int and filesystem["glob_scan_max_depth"] == 64,
        f"{label} glob depth drifted",
    )
    for path in CODEX_MANAGED_READ_PATHS:
        require(filesystem[path] == "read", f"{label} managed read root drifted: {path}")
    for path in (*CODEX_SENSITIVE_HOME_PATHS, *CODEX_SENSITIVE_HOME_GLOBS):
        require(filesystem[path] == "deny", f"{label} sensitive deny drifted: {path}")
    require(workspace["."] == "write", f"{label} workspace write rule drifted")
    for path in CODEX_WORKSPACE_DENY_PATHS:
        require(workspace[path] == "deny", f"{label} workspace deny drifted: {path}")
    require(".env.example" not in workspace, f"{label} exception weakens .env.* deny")


claude = load_json("claude-code/.claude/settings.json")
opencode = load_json("opencode/.config/opencode/opencode.json")
opencode_plugin_package = load_json("opencode/.config/opencode/plugins/package.json")
opencode_ignore = (ROOT / "opencode/.config/opencode/.gitignore").read_text(encoding="utf-8").splitlines()
codex_ignore = (ROOT / "codex/.codex/.gitignore").read_text(encoding="utf-8").splitlines()
load_json("opencode/.config/opencode/tui.json")
claude_project = load_json(".claude/settings.json")
opencode_project = load_json("opencode.json")
with (ROOT / "codex/.codex/config.toml").open("rb") as handle:
    codex = tomllib.load(handle)
with (ROOT / "templates/codex/config.toml").open("rb") as handle:
    codex_template = tomllib.load(handle)

for removed_path in (
    "claude-code/.local/bin/context-read-gate.sh",
    "codex/.codex/hooks.json",
    "opencode/.config/opencode/tools/external-context.ts",
    "opencode/.config/opencode/tools/package.json",
    "tests/external-context.sh",
):
    require(not (ROOT / removed_path).exists(), f"retired external-context artifact remains: {removed_path}")

validate_codex_profile(codex_template, "Codex portable template", allow_top_level_extras=False)
validate_codex_profile(codex, "tracked Codex runtime", allow_top_level_extras=True)
require_recursive_subset(codex_template, codex)

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

require(claude["model"] == "fable", "Claude model alias drifted")
require(
    claude["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == "xhigh",
    "Claude xhigh effort pin drifted",
)
require("effortLevel" not in claude, "Claude effort must use the environment pin")
require(claude["permissions"]["defaultMode"] == "auto", "Claude default mode drifted")
require(
    claude["permissions"]["disableBypassPermissionsMode"] == "disable",
    "Claude bypass mode must remain disabled",
)
require(claude["workflowSizeGuideline"] == "large", "Claude workflow guidance drifted")
# Ordinary edits defer to auto mode. Bare ask rules would restore per-file
# prompts and override the spar hook's validated handoff allow.
for bare in ("Edit", "Write", "NotebookEdit"):
    require(
        bare not in claude["permissions"].get("ask", []),
        f"bare {bare} ask entry defeats the spar gate hook",
    )
hook_source = (ROOT / "claude-code/.claude/hooks/spar-handoff-approve.sh").read_text(
    encoding="utf-8"
)
for marker in (
    '"permissionDecision":"%s"',
    'emit defer "use the configured permission mode"',
    'emit deny "invalid spar handoff parent"',
    "gate_error",
    "exit 2",
    "realpath -m",
    "path_traverses_handoff",
    "stat -c '%h'",
    "case ${name,,} in",
    "reviewer-id | agents.md | agents.override.md | claude.md | claude.local.md | .git",
    ".env | .env.* | .env-* | .env_* | .env~*",
    ".netrc | .netrc.* | .netrc-* | .netrc_* | .netrc~*",
    "id_ed25519 | id_ed25519.* | id_ed25519~* | id_ed25519-* | id_ed25519_*",
    "HANDOFF_RE='^/var/tmp/spar-",
):
    require(marker in hook_source, f"spar gate hook control drifted: {marker}")
scanner_path = ROOT / "claude-code/.local/bin/spar-payload-scan"
scanner_source = scanner_path.read_text(encoding="utf-8")
for marker in (
    "#!/usr/bin/python3 -I",
    'DETECTOR_SCHEMA = "spar-content-v1"',
    "PROMPT_MAX = 256 * 1024",
    "ENTRY_MAX = 512 * 1024",
    "TOTAL_MAX = 1024 * 1024",
    "ENTRY_COUNT_MAX = 128",
    "FINDING_REPORT_MAX = 8",
    're.fullmatch(r"\\.env(?:[._~-].*)?", name)',
    "return any(sensitive_component(part) for part in parts)",
    "def validate_repository_paths(root: Path)",
    "for component in root.parts:",
    "repository symlink cannot be covered by reviewer deny globs",
    'inside_recursive_secrets = "secrets" in Path(relative_parent).parts',
    "def decode_quoted_git_path(value: str, start: int = 0)",
    'raise ValueError("NUL in Git path")',
    "def decode_git_path(value: str)",
    "def split_git_header_paths(value: str)",
    '"claude.local.md",',
    '"reviewer-id",',
    "def diff_paths(text: str):",
    "def safe_assignment_value(value: str)",
    "PATTERN_SAFE_VALUE.fullmatch",
    "def scan_outbound(root: Path)",
    "def scan_reply()",
    'sys.argv[1] == "outbound"',
    'sys.argv[1] == "reply"',
    'sys.argv[1] == "repository"',
    'text.split("\\n")',
    "sys.stdout.buffer.write(prompt)",
    "PUBLIC_FINDINGS = frozenset",
):
    require(marker in scanner_source, f"spar payload scanner control drifted: {marker}")
require(
    "public-vectors.json" not in scanner_source,
    "spar scanner regained an external public-vector registry",
)
scanner_tree = ast.parse(scanner_source)
public_findings_assignments = [
    node
    for node in scanner_tree.body
    if isinstance(node, ast.Assign)
    and any(isinstance(target, ast.Name) and target.id == "PUBLIC_FINDINGS" for target in node.targets)
]
require(
    len(public_findings_assignments) == 1,
    "spar scanner must assign public findings exactly once",
)
public_findings_assignment = public_findings_assignments[0]
require(
    len(public_findings_assignment.targets) == 1
    and isinstance(public_findings_assignment.targets[0], ast.Name),
    "spar scanner public findings assignment target is malformed",
)
public_findings_bindings = [
    node
    for node in ast.walk(scanner_tree)
    if isinstance(node, ast.Name)
    and node.id == "PUBLIC_FINDINGS"
    and not isinstance(node.ctx, ast.Load)
]
require(
    public_findings_bindings == public_findings_assignment.targets,
    "spar scanner must bind public findings exactly once",
)
public_findings_call = public_findings_assignment.value
require(
    isinstance(public_findings_call, ast.Call)
    and isinstance(public_findings_call.func, ast.Name)
    and public_findings_call.func.id == "frozenset"
    and len(public_findings_call.args) == 1
    and not public_findings_call.keywords,
    "spar scanner public findings are malformed",
)
try:
    public_findings = ast.literal_eval(public_findings_call.args[0])
except (TypeError, ValueError):
    public_findings = None
require(isinstance(public_findings, set), "spar scanner public findings must be literal")
expected_public_findings = frozenset(
    {
        ("cloud-access-id-v1", "90df53b892f02c56a9ac257e62b03dec2b71b1b92005e62a12c9eb7365a658f0"),
        ("credential-assignment-v1", "35073e528e7a1e75b3dfdfcd6737e4d505fbe0d61ecaffb854affae141599a54"),
        ("credential-assignment-v1", "3a190e6f2167eace506544001d96cbccd41b60c154d3d554f65afe6538617ff0"),
        ("credential-assignment-v1", "88410c8e88290dedce53fdfe0050b07db6813a02b0196b746554273b6172eae5"),
        ("key-envelope-v1", "2bbbd02db29ea579a75b63dd32d112600c61b73232b210a613bf6c17e58ae3ff"),
        ("provider-b-token-v1", "e75d8f87b5e64a0cc6970fca5b675619a1429eb0cb4e6d8b9d0c6ecc2dd76770"),
        ("provider-c-token-v1", "f9a6ae28ec3a6ec93bd3e0854df808528823669b3a2d89f628a5e0c395eb26cc"),
    }
)
require(
    frozenset(public_findings) == expected_public_findings,
    "spar scanner public finding set drifted",
)
scanner_runtime = runpy.run_path(str(scanner_path), run_name="spar_payload_scan_contract")
runtime_public_findings = scanner_runtime.get("PUBLIC_FINDINGS")
require(
    type(runtime_public_findings) is frozenset
    and runtime_public_findings == expected_public_findings,
    "spar scanner runtime public finding set drifted",
)

claude_bridge_source = (ROOT / "claude-code/.local/bin/spar-claude").read_text(
    encoding="utf-8"
)
codex_bridge_source = (ROOT / "codex/.local/bin/spar-codex").read_text(encoding="utf-8")
for name, source in (("Claude", claude_bridge_source), ("Codex", codex_bridge_source)):
    for marker in (
        "canonical_repo_root()",
        'printf \'%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n\'',
        'NF != 6 || $2 != bridge || $6 != repo',
        '"$SCANNER" outbound',
        '"$SCANNER" reply',
        "interrupt_stream()",
        "trap interrupt_stream INT TERM HUP",
        'exit 130',
    ):
        require(marker in source, f"{name} repository reviewer control drifted: {marker}")
    require(
        '"$SCANNER" repository "$REPO_ROOT"' in source,
        f"{name} repository path preflight drifted",
    )

for marker in (
    '--add-dir "$HANDOFF"',
    '--tools "Read,Glob,Grep"',
    '--safe-mode',
    '--setting-sources=',
    '--strict-mcp-config',
    '"Read(/" + $repo + "/.git)"',
    '"Read(/" + $repo + "/.git/**)"',
    '"Read(/" + $handoff + "/reviewer-id)"',
    '"Read(./.git)"',
    '"Read(./**/.git)"',
    '"Read(./secret~*)"',
    '"Read(./**/secrets/**)"',
    '"Read(./**/.env~*)"',
    '"Read(./**/*.pem.*)"',
    '"Read(./**/*.p12~*)"',
    '"Read(./**/auth.json_*)"',
    '"Read(./**/.netrc~*)"',
    '"Read(./**/.npmrc-*)"',
    '"Read(./**/.pypirc.*)"',
    "CLAUDE_CODE_USE_ANTHROPIC_AWS",
    "CLAUDE_CODE_USE_MANTLE",
    "CLAUDE_CODE_SKIP_ANTHROPIC_AWS_AUTH",
    "CLAUDE_CODE_SKIP_MANTLE_AUTH",
    "/usr/bin/env -u CLAUDE_CODE_EFFORT_LEVEL",
    '--model "$MODEL" --effort xhigh',
    '-C "$REPO_ROOT" "$REVIEWER_BIN"',
    "--safe-mode --setting-sources= auth status",
    '--arg home "$account_home"',
    '"Read(/" + $home + "/.ssh/**)"',
    '"Read(/" + $home + "/.config/gh/hosts.yml)"',
):
    require(marker in claude_bridge_source, f"Claude reviewer isolation drifted: {marker}")

for marker in (
    '\\":root\\"=\\"deny\\"',
    '\\":minimal\\"=\\"read\\"',
    '\\":tmpdir\\"=\\"deny\\"',
    '\\":slash_tmp\\"=\\"deny\\"',
    '\\":workspace_roots\\"',
    '\\"$escaped_repo\\"=\\"read\\"',
    '\\"$escaped_repo/.git\\"=\\"deny\\"',
    '\\"$HANDOFF/reviewer-id\\"=\\"deny\\"',
    "project_doc_max_bytes=0",
    "project_doc_fallback_filenames=[]",
    "**/.env~*",
    "**/*.pem.*",
    "**/*.p12~*",
    "secret~*",
    "**/secrets/**",
    "**/auth.json_*",
    "**/.netrc~*",
    "**/.npmrc-*",
    "**/.pypirc.*",
    'network={enabled=false}',
    '--ignore-user-config',
    '--ignore-rules',
    "project_root_markers=[]",
    'PROJECT_ISOLATION="projects={\\"$REPO_ROOT\\"={trust_level=\\"untrusted\\"}}"',
):
    require(marker in codex_bridge_source, f"Codex reviewer isolation drifted: {marker}")

for stem in (
    ".env",
    "*.key",
    "*.pem",
    "*.p12",
    "*.pfx",
    "auth.json",
    ".netrc",
    ".npmrc",
    ".pypirc",
    "id_rsa",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
):
    for suffix in (".*", "-*", "_*", "~*"):
        require(
            f'"Read(./**/{stem}{suffix})"' in claude_bridge_source,
            f"Claude sensitive backup deny drifted: {stem}{suffix}",
        )
        require(
            f"**/{stem}{suffix}" in codex_bridge_source,
            f"Codex sensitive backup deny drifted: {stem}{suffix}",
        )

for stem in ("secret", "secrets"):
    for suffix in ("", ".*", "-*", "_*", "~*"):
        require(
            f'"Read(./**/{stem}{suffix})"' in claude_bridge_source,
            f"Claude secret-name deny drifted: {stem}{suffix}",
        )
        require(
            f"**/{stem}{suffix}" in codex_bridge_source,
            f"Codex secret-name deny drifted: {stem}{suffix}",
        )

for source in (claude_bridge_source, codex_bridge_source):
    require(
        "secret*/**" not in source,
        "reviewer policy overmatches public secret-prefixed paths",
    )
    for stem in ("id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"):
        require(
            f"{stem}*" not in source,
            f"reviewer policy overmatches public {stem}-prefixed paths",
        )

require(
    '"**/.git/**"="deny"' not in codex_bridge_source,
    "Codex recursive Git deny would break native sandbox startup",
)

for name, source in (("Claude", claude_bridge_source), ("Codex", codex_bridge_source)):
    for marker in (
        "compgen -A variable GIT_",
        "repository contains a hard-linked file outside denied directories",
        "repository contains a nested mount boundary",
        "REPO_ROOT != /",
        "findmnt -R -J -o TARGET",
        "-xdev -mindepth 1",
        '-path "$REPO_ROOT/.git"',
        "INIT_HANDOFF=$root",
        "cannot report the handoff directory",
        "child_rc == 124 || $child_rc == 137",
        'rm -rf -- "$workdir" || true',
        "trap '' INT TERM HUP",
    ):
        require(marker in source, f"{name} repository boundary drifted: {marker}")

require("EXPECTED_SESSION_ID" in claude_bridge_source, "Claude session-result binding drifted")
require(
    claude_bridge_source.index("trap cleanup_stream EXIT")
    < claude_bridge_source.index("workdir=$(mktemp -d)"),
    "Claude recovery trap must precede private workdir creation",
)
require(
    claude_bridge_source.index('stream 2 --session-id "$sid"')
    < claude_bridge_source.index("REPORT_SESSION=0"),
    "Claude recovery reporting clears before final session delivery",
)
require(
    "A reviewer descendant may outlive its leader" in claude_bridge_source,
    "Claude normal-exit descendant cleanup drifted",
)
for marker in (
    "EXPECTED_THREAD_ID",
    "-xdev -mindepth 65 -printf 'deep\\n' -quit",
    '(.installed | type) == "array"',
    "REPORT_THREAD=1",
):
    require(marker in codex_bridge_source, f"Codex session or depth boundary drifted: {marker}")

for path in (
    ".gitignore",
    "scripts/activate-spar-gate.sh",
    "tests/spar-gate.sh",
):
    require(not (ROOT / path).exists(), f"activation artifact remains: {path}")
require(
    not any(path.is_file() or path.is_symlink() for path in (ROOT / "spar-gate").rglob("*")),
    "activation files remain under spar-gate",
)
reviewed_writes_source = (
    ROOT / "opencode/.config/opencode/plugins/reviewed-writes.ts"
).read_text(encoding="utf-8")
for marker in (
    "SPAR_RESERVED",
    "SPAR_SENSITIVE",
    "resolveWriteTarget",
    "traversesSparHandoff",
    "reviewer-instruction",
    "env(?:[._~-].*)?",
    "key|pem|p12|pfx",
    "rsa|dsa|ecdsa|ed25519",
):
    require(marker in reviewed_writes_source, f"OpenCode handoff write gate drifted: {marker}")
for marker in (
    "PATCH_DOTENV",
    "PATCH_PRIVATE_KEY",
    "canonicalWorkspaceRoot",
    "path.resolve(workspaceRoot, target)",
    "assertPatchTargetSafe",
    "assertWorkspaceTargetNotSensitive",
    "target escapes the workspace through an alias",
    "targetStat.nlink !== 1",
):
    require(marker in reviewed_writes_source, f"OpenCode grouped patch gate drifted: {marker}")
require("exactly one file" not in reviewed_writes_source, "OpenCode grouped patch cardinality gate remains")
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
for rule in (
    "Bash(git clean *)",
    "Bash(git reset *)",
    "Bash(git restore *)",
    "Bash(git stash clear *)",
    "Bash(git stash drop *)",
    "Bash(gh api *)",
    "Bash(sudo *)",
):
    require(rule in claude["permissions"]["deny"], f"Claude hard deny drifted: {rule}")
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
    "Claude pre-tool hook registrations drifted",
)
require(
    os.access(ROOT / "claude-code/.claude/hooks/spar-handoff-approve.sh", os.X_OK),
    "Claude spar handoff hook missing or not executable",
)
require("!hooks.json" not in codex_ignore, "retired Codex hooks ignore exception remains")

# OpenCode's edit-permission subject is the worktree-relative path, so
# handoff rules use ../-anchored relative patterns; the external_directory
# subject is the parent directory joined with a literal *, so its allow uses
# the absolute prefix form.
HANDOFF_EDIT_ALLOW = "../*var/tmp/spar-*"
HANDOFF_EXTERNAL_ALLOW = "/var/tmp/spar-*"
APP_TEMP_EXTERNAL_ALLOW = "/tmp/opencode/*"
HANDOFF_SENSITIVE_DENIES = (
    "../*var/tmp/spar-*/*.key",
    "../*var/tmp/spar-*/*.pem",
    "../*var/tmp/spar-*/*credentials*",
    "../*var/tmp/spar-*/.env",
    "../*var/tmp/spar-*/.env.*",
    "../*var/tmp/spar-*/auth.json",
    "../*var/tmp/spar-*/secrets/*",
)
APP_TEMP_SENSITIVE_DENIES = (
    "../*tmp/opencode*/*.key",
    "../*tmp/opencode*/*.pem",
    "../*tmp/opencode*/*credentials*",
    "../*tmp/opencode*/.env",
    "../*tmp/opencode*/.env.*",
    "../*tmp/opencode*/auth.json",
    "../*tmp/opencode*/secrets/*",
)

bash = opencode["permission"]["bash"]
bash_items = list(bash.items())
require(
    bash_items[0] == ("*", "allow"),
    "OpenCode Bash autonomy catch-all must remain first",
)
require(
    [command for command, action in bash_items if action == "allow"]
    == [
        "*",
        "claude --version",
        "codex --version",
        "opencode --version",
    ],
    "OpenCode Bash safe exceptions drifted",
)
require(all(action != "ask" for _, action in bash_items), "OpenCode Bash prompt reintroduced")
for command, exception in (
    ("claude *", "claude --version"),
    ("codex *", "codex --version"),
    ("opencode *", "opencode --version"),
):
    require(bash[command] == "deny", f"OpenCode nested-agent deny drifted: {command}")
    require(
        list(bash).index(exception) > list(bash).index(command),
        f"OpenCode safe version exception precedes broad deny: {exception}",
    )
for command in ("tree -o *", "tree --output*", "tree * -o *", "tree * --output *"):
    require(bash[command] == "deny", f"OpenCode tree output deny drifted: {command}")
require(bash["git push"] == "deny" and bash["git push *"] == "deny", "OpenCode push deny drifted")
for command in (
    "curl *",
    "gh api *",
    "git clean *",
    "git reset *",
    "git restore *",
    "git stash clear *",
    "git stash drop *",
    "rm *",
    "scp *",
    "ssh *",
    "sudo *",
    "wget *",
):
    require(bash[command] == "deny", f"OpenCode hard deny drifted: {command}")
require(opencode["permission"]["webfetch"] == "allow", "OpenCode WebFetch auto-read drifted")
require(opencode["permission"]["websearch"] == "allow", "OpenCode WebSearch drifted")
require(
    "external_context" not in opencode["permission"],
    "OpenCode format-specific external-context permission remains",
)
require(opencode["model"] == "openai/gpt-5.6-sol-fast", "OpenCode Fast model drifted")
require(opencode["share"] == "disabled", "OpenCode sharing drifted")
require(opencode["autoupdate"] is False, "OpenCode must not compete with wrapper-managed updates")
require(set(opencode["provider"]) == {"openai"}, "Unused OpenCode provider configured")
require(opencode["enabled_providers"] == ["openai"], "OpenCode enabled-provider gate drifted")
require(
    opencode_plugin_package
    == {"name": "eyragents-opencode-plugins", "private": True, "type": "module"},
    "OpenCode nested plugin module marker drifted",
)
require(
    opencode_ignore == ["/package.json", "/package-lock.json", "/bun.lock", "/bun.lockb", "/node_modules/"],
    "OpenCode generated-state ignores drifted",
)
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
    '@opencode-ai/plugin' not in reviewed_writes_source,
    "OpenCode write-review plugin regained a generated package dependency",
)
opencode_provider_id, opencode_model_id = opencode["model"].split("/", 1)
require(
    opencode["provider"][opencode_provider_id]["models"][opencode_model_id]["options"]
    == {"reasoningEffort": "xhigh"},
    "OpenCode selected model xhigh overlay drifted",
)

edit_expected = {
    "*": "allow",
    HANDOFF_EDIT_ALLOW: "allow",
    "**/*.key": "deny",
    "**/*.pem": "deny",
    ".env": "deny",
    "secrets/**": "deny",
    "~/.aws/**": "deny",
    "~/.gnupg/**": "deny",
    **{path: "deny" for path in HANDOFF_SENSITIVE_DENIES},
    **{path: "deny" for path in APP_TEMP_SENSITIVE_DENIES},
}
require(
    list(opencode["permission"]["edit"].items()) == list(edit_expected.items()),
    "OpenCode edit map or its order drifted (catch-all, spar allow, denies last)",
)
require("build" not in opencode["agent"], "OpenCode build override bypasses global policy")
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
    "**/.env",
    "**/.env.*",
    "**/.netrc",
    "**/.npmrc",
    "**/.pypirc",
    "**/auth.json",
    "**/.aws/**",
    "**/.config/gh/hosts.yml",
    "**/.docker/config.json",
    "**/.gnupg/**",
    "**/.kube/**",
    "**/.local/share/opencode/auth.json",
    "**/.ssh/**",
    "**/secrets/**",
    ".env",
    ".env.*",
    "**/*.key",
    "**/*.pem",
    "**/*credentials*",
    "secrets/**",
    "~/.ssh/**",
):
    require(read_rules[path] == "deny", f"OpenCode read deny drifted: {path}")
for path in HANDOFF_SENSITIVE_DENIES:
    require(read_rules[path] == "deny", f"OpenCode handoff read deny drifted: {path}")
require(external_rules["*"] == "ask", "OpenCode external-directory approval drifted")
require(
    external_rules[APP_TEMP_EXTERNAL_ALLOW] == "allow",
    "OpenCode app-temp external-directory allow drifted",
)
for path in ("/tmp*", "/tmp/*", "/tmp/**", "/tmp/opencode*"):
    require(
        external_rules.get(path) != "allow",
        f"OpenCode broad temporary-directory allow introduced: {path}",
    )
# The external subject is a parent-directory glob, while read receives a
# worktree-relative path. Directory globs and the **-prefixed read entries are
# load-bearing; file-level external and ~-keyed read entries are retained only
# as forward-compatible defense.
require(
    external_rules[HANDOFF_EXTERNAL_ALLOW] == "allow",
    "OpenCode spar external-directory allow drifted",
)
external_keys = list(external_rules)
require(
    external_keys.index(APP_TEMP_EXTERNAL_ALLOW) > external_keys.index("*"),
    "OpenCode app-temp allow precedes the catch-all",
)
require(
    external_keys.index(HANDOFF_EXTERNAL_ALLOW) > external_keys.index(APP_TEMP_EXTERNAL_ALLOW),
    "OpenCode spar allow precedes the app-temp allowance",
)
require(
    external_keys.index(HANDOFF_EXTERNAL_ALLOW) > external_keys.index("*"),
    "OpenCode spar allow precedes the catch-all",
)
for path in (
    "~/.aws/**",
    "~/.gnupg/**",
    "~/.kube/**",
    "~/.ssh/**",
    "**/.aws/**",
    "**/.config/gh/**",
    "**/.docker/**",
    "**/.gnupg/**",
    "**/.kube/**",
    "**/.local/share/opencode/**",
    "**/.ssh/**",
    "**/secrets/**",
):
    require(external_rules[path] == "deny", f"OpenCode active external deny drifted: {path}")
    require(
        external_keys.index(path) > external_keys.index(HANDOFF_EXTERNAL_ALLOW),
        f"OpenCode active external deny precedes the spar allowance: {path}",
    )
for path in ("~/.claude/.credentials.json", "~/.codex/auth.json"):
    require(read_rules[path] == "deny", f"OpenCode credential read deny drifted: {path}")
    require(external_rules[path] == "deny", f"OpenCode credential external deny drifted: {path}")

claude_denies = set(claude["permissions"]["deny"])
for rule in (
    "Read(./.env)",
    "Read(./.env.*)",
    "Read(./secrets/**)",
    "Read(//**/*.key)",
    "Read(//**/*.pem)",
    "Read(//**/*credentials*)",
    "Read(//**/.env)",
    "Read(//**/.env.*)",
    "Read(//**/auth.json)",
    "Read(//**/secrets/**)",
    "Read(~/.claude/.credentials.json)",
    "Read(~/.codex/auth.json)",
):
    require(rule in claude_denies, f"Claude credential read deny drifted: {rule}")

require(
    claude_project == {"$schema": "https://json.schemastore.org/claude-code-settings.json"},
    "Claude project config must not grant mutable repository commands",
)
require(
    opencode_project == {"$schema": "https://opencode.ai/config.json"},
    "OpenCode project config must not grant mutable repository commands",
)

print("ok: config syntax and security contracts")
