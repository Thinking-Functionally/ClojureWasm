#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-.}"
PROJECT_CLAUDE="$PROJECT_DIR/.claude"
GLOBAL_DIR="$HOME/.claude"
RULES_DIR="$PROJECT_CLAUDE/rules"

echo "🔧 Anti-Thrash Fix (runtime.zig edition)"
echo "========================================="

# ─── 1. ARCHIVE RULES (the real fix) ───────────────────────
if [ -d "$RULES_DIR" ]; then
    RULE_COUNT=$(find "$RULES_DIR" -type f -name "*.md" | wc -l | tr -d ' ')
    RULES_SIZE=$(du -sk "$RULES_DIR" 2>/dev/null | cut -f1)
    echo ""
    echo "📊 Current rules: $RULE_COUNT files, ${RULES_SIZE}KB"

    # Archive all rules
    ARCHIVE="$PROJECT_CLAUDE/rules-archive-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$ARCHIVE"
    cp "$RULES_DIR"/*.md "$ARCHIVE/" 2>/dev/null || true
    echo "📦 All rules backed up to: $ARCHIVE"

    # Merge ALL rules into ONE compact file
    echo "🔨 Merging $RULE_COUNT rules into 1 compact file..."

    MERGED="$RULES_DIR/_merged-rules.md"
    echo "# Project Rules (merged)" > /tmp/merged-rules.md
    echo "" >> /tmp/merged-rules.md

    for f in "$RULES_DIR"/*.md; do
        [ -f "$f" ] || continue
        BASENAME=$(basename "$f")
        [ "$BASENAME" = "_merged-rules.md" ] && continue

        echo "## $(echo "$BASENAME" | sed 's/\.md$//' | sed 's/-/ /g')" >> /tmp/merged-rules.md
        # Keep only first 15 lines of each rule (strip fluff)
        head -20 "$f" | grep -v '^#' | grep -v '^$' | head -10 >> /tmp/merged-rules.md
        echo "" >> /tmp/merged-rules.md
    done

    # Remove all old rules, keep only merged
    rm -f "$RULES_DIR"/*.md
    mv /tmp/merged-rules.md "$MERGED"

    NEW_SIZE=$(du -sk "$RULES_DIR" 2>/dev/null | cut -f1)
    echo "✅ Rules: $RULE_COUNT files (${RULES_SIZE}KB) → 1 file (${NEW_SIZE}KB)"
else
    echo "⏭️  No rules directory"
fi

# ─── 2. GLOBAL SETTINGS ────────────────────────────────────
mkdir -p "$GLOBAL_DIR"
GLOBAL_SETTINGS="$GLOBAL_DIR/settings.json"
[ -f "$GLOBAL_SETTINGS" ] && cp "$GLOBAL_SETTINGS" "$GLOBAL_SETTINGS.bak.$(date +%s)"

cat > "$GLOBAL_SETTINGS" << 'EOF'
{
  "env": {
    "BASH_MAX_OUTPUT_LENGTH": "10000",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "15000"
  }
}
EOF
echo "✅ Global settings: output limits set"

# ─── 3. HOOKS ──────────────────────────────────────────────
mkdir -p "$PROJECT_CLAUDE/hooks"

# Read guard: force chunked reads >200 lines
cat > "$PROJECT_CLAUDE/hooks/read-guard.sh" << 'HOOK'
#!/usr/bin/env bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ "$TOOL" = "Read" ]; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    HAS_LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty' 2>/dev/null)
    if [ -n "$FILE" ] && [ -f "$FILE" ] && [ -z "$HAS_LIMIT" ]; then
        LINES=$(wc -l < "$FILE" 2>/dev/null || echo "0")
        if [ "$LINES" -gt 200 ]; then
            cat << JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: $FILE has $LINES lines. Read in chunks: use offset+limit (max 150 lines per read)."
  }
}
JSON
            exit 0
        fi
    fi
fi
exit 0
HOOK
chmod +x "$PROJECT_CLAUDE/hooks/read-guard.sh"

# Bash guard: block unbounded test output
cat > "$PROJECT_CLAUDE/hooks/bash-guard.sh" << 'HOOK'
#!/usr/bin/env bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ "$TOOL" = "Bash" ]; then
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if echo "$CMD" | grep -qE '(zig build test|cargo test|npm test|make test|pytest)' 2>/dev/null; then
        if ! echo "$CMD" | grep -qE '(head|tail|grep|wc)' 2>/dev/null; then
            cat << JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Test commands must pipe through '2>&1 | head -50' to limit output."
  }
}
JSON
            exit 0
        fi
    fi
fi
exit 0
HOOK
chmod +x "$PROJECT_CLAUDE/hooks/bash-guard.sh"
echo "✅ Hooks installed (read-guard + bash-guard)"

# ─── 4. PROJECT SETTINGS: wire hooks ───────────────────────
PROJECT_SETTINGS="$PROJECT_CLAUDE/settings.json"
[ -f "$PROJECT_SETTINGS" ] && cp "$PROJECT_SETTINGS" "$PROJECT_SETTINGS.bak.$(date +%s)"

cat > "$PROJECT_SETTINGS" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/read-guard.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/bash-guard.sh"
          }
        ]
      }
    ]
  }
}
EOF
echo "✅ Project settings: hooks wired"

# ─── 5. CLAUDE.md ──────────────────────────────────────────
CLAUDE_MD="$PROJECT_CLAUDE/CLAUDE.md"

# Remove old context management section if exists
if [ -f "$CLAUDE_MD" ]; then
    sed -i '/## Context Management/,/^##/{ /^## Context Management/d; /^##/!d; }' "$CLAUDE_MD" 2>/dev/null || true
    sed -i '/## CRITICAL.*runtime/,/^##/{ /^## CRITICAL/d; /^##/!d; }' "$CLAUDE_MD" 2>/dev/null || true
fi

cat >> "$CLAUDE_MD" << 'EOF'

## Context Management — MANDATORY
- NEVER read files >200 lines without offset+limit. Max 150 lines per read.
- For runtime.zig (460 lines): read in 3 chunks (0-149, 150-299, 300-460). NEVER read it fully.
- NEVER run test commands without `2>&1 | head -50`
- When Edit fails, do NOT re-read the whole file. Use `sed -i` commands instead.
- Prefer `grep -n "pattern" file` to find line numbers, then read only ±20 lines around the target.
- Workflow for large file edits:
  1. `grep -n "target_pattern" file` → get line number
  2. Read offset=LINE-20, limit=40
  3. Apply edit or generate sed command
  4. Do NOT re-read to verify. Use `sed -n 'LINEp' file` to check.
EOF
echo "✅ CLAUDE.md updated"

# ─── 6. VERIFY ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "📊 Before vs After"
echo "========================================="
if [ -d "$ARCHIVE" ]; then
    ARCHIVE_SIZE=$(du -sk "$ARCHIVE" 2>/dev/null | cut -f1)
    CURRENT_SIZE=$(du -sk "$RULES_DIR" 2>/dev/null | cut -f1)
    echo "Rules: ${ARCHIVE_SIZE}KB → ${CURRENT_SIZE}KB"
fi
echo ""
echo "Context budget estimate:"
echo "  System prompt:    ~10%"
echo "  Rules (merged):   ~8%   (was ~40%)"
echo "  CLAUDE.md:        ~5%"
echo "  runtime.zig:      ~15%  (460 lines in chunks)"
echo "  Working space:    ~62%  ← plenty of room"
echo ""
echo "========================================="
echo "✅ Done! Now:"
echo "  1. Ctrl+C kill Claude Code"
echo "  2. Run: claude"
echo "  3. /clear"
echo "  4. Ask your question about runtime.zig"
echo "========================================="
