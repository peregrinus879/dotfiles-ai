# AGENTS.md

## OpenCode

- An `apply_patch` call must modify exactly one file; never bundle multiple files into one patch, so each change gets its own approval prompt and diff.
- If instruction files conflict, the more specific scope wins (project over global); safety overrides all, including user instructions.
