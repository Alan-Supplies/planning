#!/bin/bash
# Claude Code statusline: model, cwd, git branch
# ~/.zshrc에 별도 PS1이 설정되어 있지 않아(p10k 테마 사용) 표준 정보(모델/경로/브랜치)로 구성함.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
dir_name=$(basename "$current_dir")

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
reset_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

usage_info=""
if [ -n "$used_pct" ] || [ -n "$cost_usd" ] || [ -n "$reset_epoch" ] || [ -n "$session_pct" ]; then
  usage_info=$(printf ' \033[2m|\033[0m')
  if [ -n "$used_pct" ]; then
    usage_info="$usage_info $(printf '\033[35mctx %.0f%%\033[0m' "$used_pct")"
  fi
  if [ -n "$cost_usd" ]; then
    usage_info="$usage_info $(printf '\033[33m$%.2f\033[0m' "$cost_usd")"
  fi
  if [ -n "$session_pct" ]; then
    usage_info="$usage_info $(printf '\033[32msession %.0f%%\033[0m' "$session_pct")"
  fi
  if [ -n "$reset_epoch" ]; then
    reset_time=$(date -r "$reset_epoch" '+%H:%M' 2>/dev/null)
    if [ -n "$reset_time" ]; then
      usage_info="$usage_info $(printf '\033[90m리셋 %s\033[0m' "$reset_time")"
    fi
  fi
fi

# ask 모드(편집 차단) 표시 — 센티널은 세션 cwd 기준이다.
ask_info=""
if [ -f "$current_dir/.claude/.ask" ]; then
  ask_info=$(printf '\033[30;43m ASK \033[0m ')
fi

git_info=""
if git -C "$current_dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=""
    if [ -n "$(git -C "$current_dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      dirty="*"
    fi
    git_info=$(printf " \033[2m|\033[0m \033[36m%s%s\033[0m" "$branch" "$dirty")
  fi
fi

printf "%s\033[2m%s\033[0m \033[2m|\033[0m \033[34m%s\033[0m%s%s" "$ask_info" "$model" "$dir_name" "$git_info" "$usage_info"
