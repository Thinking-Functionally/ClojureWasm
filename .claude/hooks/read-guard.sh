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
