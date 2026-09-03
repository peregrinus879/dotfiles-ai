#!/usr/bin/env python3
"""Reconcile a host-local Codex config with the portable template.

    reconcile-codex-config.py merge TEMPLATE [HOST]
    reconcile-codex-config.py check TEMPLATE HOST

The template owns every root-level key and every table it defines (auto_review,
features, agents, permissions). Everything else in HOST is host-only state that
Codex and the desktop app write (projects, marketplaces, plugins, mcp_servers,
shell_environment_policy, desktop, and any table the template does not know)
and is preserved verbatim, in its original order.

`merge` prints the reconciled config: the template text followed by the
host-only tables. `check` exits 0 when HOST already carries the template's
root keys and tables with the template's values, 1 when it has drifted, and 2
when either file does not parse.
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

HEADER = re.compile(r"^\s*\[\[?(?P<key>.*?)\]\]?\s*(?:#.*)?$")


def first_component(key: str) -> str:
    """Return the first dotted component of a table key, honoring quotes."""
    key = key.strip()
    if key[:1] in ('"', "'"):
        quote = key[0]
        index = 1
        while index < len(key):
            if key[index] == "\\" and quote == '"':
                index += 2
                continue
            if key[index] == quote:
                return key[1:index]
            index += 1
        return key[1:]
    match = re.match(r"[A-Za-z0-9_-]+", key)
    return match.group(0) if match else key


def split_sections(text: str) -> tuple[str, list[tuple[str, str]]]:
    """Split TOML text into its root text and top-level (name, text) sections."""
    root: list[str] = []
    sections: list[tuple[str, list[str]]] = []
    for line in text.splitlines(keepends=True):
        header = HEADER.match(line)
        if header and not line.lstrip().startswith("#"):
            sections.append((first_component(header.group("key")), [line]))
        elif sections:
            sections[-1][1].append(line)
        else:
            root.append(line)
    return "".join(root), [(name, "".join(lines)) for name, lines in sections]


def load(path: str) -> tuple[str, dict]:
    text = Path(path).read_text(encoding="utf-8")
    try:
        return text, tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise SystemExit(f"reconcile-codex-config: {path} is not valid TOML: {error}")


def template_owned(template: dict) -> set[str]:
    return set(template)


def merge(template_path: str, host_path: str | None) -> str:
    template_text, template = load(template_path)
    output = template_text if template_text.endswith("\n") else template_text + "\n"
    if host_path is not None:
        host_text, _ = load(host_path)
        owned = template_owned(template)
        _, sections = split_sections(host_text)
        for name, text in sections:
            if name in owned:
                continue
            output += "\n" + text.strip("\n") + "\n"
    try:
        result = tomllib.loads(output)
    except tomllib.TOMLDecodeError as error:
        raise SystemExit(f"reconcile-codex-config: reconciled config does not parse: {error}")
    for key, value in template.items():
        if result.get(key) != value:
            raise SystemExit(f"reconcile-codex-config: host state overrode template key {key}")
    return output


def check(template_path: str, host_path: str) -> int:
    _, template = load(template_path)
    _, host = load(host_path)
    drifted = [key for key, value in template.items() if host.get(key) != value]
    if drifted:
        print(f"reconcile-codex-config: template-owned keys drifted: {', '.join(drifted)}", file=sys.stderr)
        return 1
    return 0


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
