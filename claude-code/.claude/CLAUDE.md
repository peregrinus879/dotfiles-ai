# CLAUDE.md

## Precedence

Priority: session instructions > {project-root}/CLAUDE.md > ~/.claude/CLAUDE.md > defaults. Safety overrides all, including user instructions.

## Tool-Specific Notes

- Shared user guidance lives in `~/.claude/rules/shared-guidance.md`.
- Primary tool: Claude Code.
- Co-Author: Append `Co-Authored-By: Claude {current model} <noreply@anthropic.com>`.
- Session sharing and upload features (auto-upload, remote control) stay off unless the user explicitly asks to enable them.
- Edit one file per tool call: use the file edit tools, never bulk shell edits (`sed -i`, scripts) across files, so each change gets its own approval prompt and diff.
