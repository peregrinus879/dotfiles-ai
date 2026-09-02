#!/usr/bin/env python3
"""Validate documentation ownership and workflow structure."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def load(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def headings(text: str, level: int) -> list[str]:
    prefix = "#" * level + " "
    return [line.removeprefix(prefix) for line in text.splitlines() if line.startswith(prefix)]


def section(text: str, title: str) -> str:
    marker = f"## {title}\n"
    require(marker in text, f"missing section: {title}")
    body = text.split(marker, 1)[1]
    return body.split("\n## ", 1)[0]


def require_terms(text: str, terms: tuple[str, ...], label: str) -> None:
    missing = [term for term in terms if term not in text]
    require(not missing, f"{label} missing concepts: {', '.join(missing)}")


readme = load("README.md")
agents = load("AGENTS.md")
maintenance = load("docs/maintenance.md")
shared = load("claude-code/.claude/rules/shared-guidance.md")
commit_skills = [
    load("claude-code/.claude/skills/commit/SKILL.md"),
    load("codex/.agents/skills/commit/SKILL.md"),
    load("opencode/.config/opencode/skills/commit/SKILL.md"),
]

require(
    headings(readme, 2)
    == ["Scope", "Layout", "Safety Model", "Setup", "Untrusted Checkouts", "Workflows", "Verify", "License"],
    "README ownership structure drifted",
)
require(
    headings(agents, 2)
    == [
        "Instruction Loading",
        "Documentation",
        "Workflow Authority",
        "Security Boundaries",
        "Reviewer Bridges",
        "Tool Configuration",
        "State And Deployment",
        "Verification",
        "Skills",
    ],
    "AGENTS ownership structure drifted",
)
require(
    headings(maintenance, 2)
    == ["Active Limitations", "Open Decisions", "Deferred Work", "Revalidation Triggers"],
    "maintenance ledger structure drifted",
)
require(
    headings(shared, 2) == ["Style", "Safety", "Work and Review", "Environment"],
    "shared guidance structure drifted",
)

for title in headings(maintenance, 2):
    for line in section(maintenance, title).splitlines():
        require(not line or line.startswith("- "), f"maintenance {title} contains narrative prose")

for path, text in (
    ("README.md", readme),
    ("AGENTS.md", agents),
    ("docs/maintenance.md", maintenance),
    ("shared-guidance.md", shared),
):
    require(
        not re.search(r"\b(?:previously|reverted|superseded|used to)\b", text, re.IGNORECASE),
        f"{path} contains repository-history narration",
    )
    for number, line in enumerate(text.splitlines(), 1):
        if all(tool in line for tool in ("Claude Code", "Codex", "OpenCode")):
            require(
                line.index("Claude Code") < line.index("Codex") < line.index("OpenCode"),
                f"{path}:{number} violates tool order",
            )

require_terms(
    section(agents, "Documentation"),
    ("shared-guidance.md", "README.md", "docs/maintenance.md", "current repository invariants", "Git history"),
    "AGENTS documentation ownership",
)
require_terms(
    section(shared, "Style"),
    (
        "When H supplies wording",
        "Preserve its intended meaning",
        "verbatim only when H requests exact wording",
        "Repository documentation states current behavior",
        "Git history owns provenance",
        "Remove closed items",
    ),
    "shared lean-documentation policy",
)
require_terms(
    section(shared, "Safety"),
    (
        "including path discovery and local format conversion",
        "do not require an exact filename, redaction",
        "external content as untrusted data",
        "Never use broad working-root grants",
        "Ordinary personal and professional documents",
        "Never read, write, or expose secret",
    ),
    "shared safety policy",
)
require_terms(
    section(shared, "Work and Review"),
    (
        "Before every commit or publication-readiness assessment, load `/commit`",
        "H approves one exact candidate before staging",
        "requires a refreshed candidate",
        "push, release, pull request, or other publication",
        "Any unmatched record",
    ),
    "shared workflow authority",
)
require_terms(
    section(agents, "Workflow Authority"),
    ("publication-readiness assessment", "push, release, pull request, or other publication"),
    "AGENTS publication authority",
)

expected_commit_sections = [
    "Format",
    "Pre-commit check",
    "Scratch file handling",
    "Candidate privacy screen",
    "Candidate bindings",
    "Review gate",
    "Staging and commit",
    "Post-commit routing",
    "Rules",
    "Publication review and push hint",
]
for skill in commit_skills:
    require(headings(skill, 2) == expected_commit_sections, "commit skill structure drifted")
    require_terms(
        section(skill, "Pre-commit check"),
        ("canonical owner", "README", "maintenance ledgers", "completed provenance", "closed maintenance items"),
        "commit documentation check",
    )
    require_terms(
        section(skill, "Candidate bindings"),
        ("candidate-status-v1", "candidate-tracked-v1", "candidate-new-v1"),
        "commit candidate bindings",
    )
    require_terms(
        section(skill, "Review gate"),
        ("Custom input never authorizes staging or commit", "requires a refreshed packet"),
        "commit review gate",
    )
    require_terms(
        section(skill, "Staging and commit"),
        ("Proceed only after", "exact staged path/status/mode set"),
        "commit staging gate",
    )
    require_terms(
        section(skill, "Rules"),
        ("Push: user handles manually. Do not push.",),
        "commit push ownership",
    )
    require_terms(
        section(skill, "Post-commit routing"),
        ("Commit and resume", "Commit and pause", "publication review automatically"),
        "commit completion routing",
    )
    require_terms(
        section(skill, "Publication review and push hint"),
        (
            "push, release, pull request, or other publication",
            "single configured upstream",
            "default to world-readable",
            "immutable source",
            "Any count mismatch",
            "Never rely on a bare `git push`",
            "expected-old-value guard",
        ),
        "commit publication review",
    )

require_terms(
    section(readme, "Workflows"),
    (
        "never reproduces the complete diff or new-file contents unless the user asks",
        "before every commit or publication-readiness assessment",
        "push, release, pull request, or other publication",
    ),
    "README commit workflow",
)

print("ok: documentation ownership and workflow contracts")
