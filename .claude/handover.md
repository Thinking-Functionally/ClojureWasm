# Handover

## Context Management Tool (claude-ctx)
- Installed at ~/bin/claude-ctx
- SQLite archive at ~/claude-archive/claude_rules.db
- Commands: check, trim, list, restore, search
- Already trimmed .claude/ from 265KB → 27KB
- Run `claude-ctx restore` to get full rules back

## Current Session: WasmGC Backend
- Fixing Zig 0.16.0 module system integration for WasmGC backend tests
- Resolving module import errors (Runtime, Env, Value, AST)
- Setting up WasmGC backend test infrastructure

## Workflow
- Before long session: `~/bin/claude-ctx trim`
- After done: `~/bin/claude-ctx restore`
- When context > 100k tokens: `/compact` or `/clear`
