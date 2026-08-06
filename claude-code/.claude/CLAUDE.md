# CLAUDE.md

## Claude Code

- Use the file edit tools for changes; never bulk shell edits (`sed -i`, `perl -pi`, scripts) across files.
- Order workflow agents by criticality; near session limits, split large workflows across turns.
- Multi-agent runs are expensive; scale finder pools to the remaining session budget.
- Resume a killed or edited workflow with `resumeFromRunId` plus `scriptPath`; completed agents return cached results, so only the failed tail re-runs.
