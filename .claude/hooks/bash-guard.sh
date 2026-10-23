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
