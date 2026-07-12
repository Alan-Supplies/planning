클로드 세팅
```json
{
  "permissions": {
    "allow": [
      "Write",
      "Read",
      "Edit",
      "WebSearch",
      "Bash(git:*)",
      "Bash(ls:)",
      "Bash(cat:)",
      "Bash(date:)",
      "Bash(python3 -m json.tool:)",
      "Bash(command -v:)",
      "Bash(claude:)",
      "mcp__claude_ai_Slack",
      "mcp__claude_ai_Linear",
      "Skill(update-config)",
      "Bash(mysql:)",
      "Bash(npm:)",
      "Bash(node:)",
      "Bash(npx:)",
      "Bash(env:)",
      "Bash(kubectl get:)",
      "Bash(nslookup:)",
      "Bash(grep:*)",
      "Bash(awk:*)",
      "Bash(sed:*)",
      "Bash(curl:*)",
      "Bash(wget:*)",
      "Bash(jq:*)"
    ],
    "additionalDirectories": [
      "/Users/swkim/.claude"
    ]
  },
  "model": "opus[1m]",
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline-command.sh\""
  },
  "language": "korean",
  "theme": "dark"
}
```