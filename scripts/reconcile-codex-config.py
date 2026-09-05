#!/usr/bin/env python3
"""Reconcile a host-local Codex config with the portable template.

    reconcile-codex-config.py merge TEMPLATE [HOST]
    reconcile-codex-config.py check TEMPLATE HOST

The template owns every root-level key and every table it defines (auto_review,
features, hooks, agents, permissions). Everything else in HOST is host-only
state that Codex and the desktop app write (projects, marketplaces, plugins,
mcp_servers, shell_environment_policy, desktop, and any table the template does
not know) and is preserved in its original order, trimmed of surrounding blank
lines. One host-written subtable lives under a template-owned table: Codex
records each hook's trusted hash under `hooks.state` after a session, so that
subtable is preserved too and ignored when the owned tables are compared.
One root key is host-owned when the template leaves it out: Codex persists the
`/fast` choice as `service_tier`, so that line survives the merge and never
counts as drift.

`merge` prints the reconciled config: the template text followed by the
host-only tables. `check` exits 0 when HOST already carries the template's
root keys and tables with the template's values and no root key the template
lacks, the host-owned key aside, 1 when it has drifted, and 2 when either file does not parse.
Sections are split on top-level table headers line by line; a multi-line
string that contains a line shaped like a header makes the reconciled output
fail to parse, which `merge` reports instead of writing.
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path

HEADER = re.compile(r"^\s*\[\[?(?P<key>.*?)\]\]?\s*(?:#.*)?$")
# Host-written subtables under template-owned tables: Codex stores each hook's
# trusted hash under hooks.state, keyed by config path and hook position.
HOST_SUBTABLES = {"hooks": {"state"}}
# Host-owned root keys when the template does not define them: Codex writes the
# per-session /fast choice here, and it is H's own, not drift.
HOST_ROOT_KEYS = {"service_tier"}


def components(key: str) -> list[str]:
    """Split a dotted table key into its components, honoring quoted parts."""
    parts: list[str] = []
    current = ""
    quote = None
    index = 0
    key = key.strip()
    while index < len(key):
        char = key[index]
        if quote:
            if char == "\\" and quote == '"' and index + 1 < len(key):
                current += key[index + 1]
                index += 2
                continue
            if char == quote:
                quote = None
            else:
                current += char
        elif char in ('"', "'"):
            quote = char
        elif char == ".":
            parts.append(current.strip())
            current = ""
        elif not char.isspace():
            current += char
        index += 1
    parts.append(current.strip())
    return parts


def host_subtable(parts: list[str]) -> bool:
    """True for a section a host writes under a template-owned table."""
    return len(parts) >= 2 and parts[1] in HOST_SUBTABLES.get(parts[0], set())


def owned_view(name: str, value):
    """The template-owned part of a host table, with host subtables removed."""
    if isinstance(value, dict) and name in HOST_SUBTABLES:
        return {key: item for key, item in value.items() if key not in HOST_SUBTABLES[name]}
    return value


def split_sections(text: str) -> tuple[str, list[tuple[list[str], str]]]:
    """Split TOML text into its root text and top-level (key components, text) sections."""
    root: list[str] = []
    sections: list[tuple[list[str], list[str]]] = []
    for line in text.splitlines(keepends=True):
        header = HEADER.match(line)
        if header and not line.lstrip().startswith("#"):
            sections.append((components(header.group("key")), [line]))
        elif sections:
            sections[-1][1].append(line)
        else:
            root.append(line)
    return "".join(root), [(parts, "".join(lines)) for parts, lines in sections]


def load(path: str) -> tuple[str, dict]:
    text = Path(path).read_text(encoding="utf-8")
    try:
        return text, tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise SystemExit(f"reconcile-codex-config: {path} is not valid TOML: {error}")


def template_owned(template: dict) -> set[str]:
    return set(template)


def host_owned(key: str, value) -> bool:
    """True for a host-owned root key carrying the string value Codex writes."""
    return key in HOST_ROOT_KEYS and isinstance(value, str)


def host_root_lines(host: dict, owned: set[str]) -> list[str]:
    """The host-owned root keys the template does not define, re-emitted from their parsed values."""
    return [f"{key} = {json.dumps(host[key])}\n" for key in sorted(HOST_ROOT_KEYS)
            if key in host and key not in owned and host_owned(key, host[key])]


def merge(template_path: str, host_path: str | None) -> str:
    template_text, template = load(template_path)
    template_root, template_sections = split_sections(template_text)
    output = template_root
    host_sections: list[str] = []
    if host_path is not None:
        host_text, host = load(host_path)
        owned = template_owned(template)
        _, sections = split_sections(host_text)
        kept = host_root_lines(host, owned)
        if kept:
            output = output.rstrip("\n") + "\n" + "".join(kept) + "\n"
        host_sections = [text for parts, text in sections if parts[0] not in owned or host_subtable(parts)]
    output += "".join(text for _, text in template_sections)
    if not output.endswith("\n"):
        output += "\n"
    for text in host_sections:
        output += "\n" + text.strip("\n") + "\n"
    try:
        result = tomllib.loads(output)
    except tomllib.TOMLDecodeError as error:
        raise SystemExit(f"reconcile-codex-config: reconciled config does not parse: {error}")
    for key, value in template.items():
        if owned_view(key, result.get(key)) != value:
            raise SystemExit(f"reconcile-codex-config: host state overrode template key {key}")
    return output


def check(template_path: str, host_path: str) -> int:
    _, template = load(template_path)
    host_text, host = load(host_path)
    drifted = [key for key, value in template.items() if owned_view(key, host.get(key)) != value]
    # The template owns the root, so a root key it no longer defines, such as a
    # retired model pin, is drift on its own; merge drops it. What merge keeps is
    # exactly the header sections and the host-owned keys, so an inline table at
    # the root is drift too.
    _, sections = split_sections(host_text)
    section_keys = {parts[0] for parts, _ in sections}
    retired = [key for key, value in host.items() if key not in template and key not in section_keys and not host_owned(key, value)]
    if drifted:
        print(f"reconcile-codex-config: template-owned keys drifted: {', '.join(drifted)}", file=sys.stderr)
    if retired:
        print(f"reconcile-codex-config: root keys the template retired: {', '.join(retired)}", file=sys.stderr)
    return 1 if drifted or retired else 0


def main() -> None:
    argv = sys.argv[1:]
    if len(argv) in (2, 3) and argv[0] == "merge":
        sys.stdout.write(merge(argv[1], argv[2] if len(argv) == 3 else None))
        return
    if len(argv) == 3 and argv[0] == "check":
        raise SystemExit(check(argv[1], argv[2]))
    print("usage: reconcile-codex-config.py merge TEMPLATE [HOST] | check TEMPLATE HOST", file=sys.stderr)
    raise SystemExit(64)


if __name__ == "__main__":
    main()
