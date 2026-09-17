#!/usr/bin/env bash
# ask-guard.sh — Claude Code "ask 모드" PreToolUse 훅
#
# 프로젝트에 .claude/.ask 센티널 파일이 있으면
#   - 편집 툴(Edit/Write/NotebookEdit)은 무조건 거부하고
#   - Bash 툴은 쓰기성 명령일 때만 거부한다 (읽기 전용 명령은 그대로 통과).
# 센티널이 없으면 아무 결정도 내리지 않고 빠져나가 평소 권한 흐름을 그대로 탄다.
#
# 설계 의도: permissions.allow 를 건드리지 않고 ask 모드에서만 조인다.
# ask 모드에서는 오탐(읽기 명령을 쓰기로 오판)의 비용이 낮으므로 —
# 모델이 설명으로 전환할 뿐이고 사용자는 센티널을 지우면 된다 — 애매하면 거부한다.
#
# 입출력 규약: stdin 으로 훅 JSON 을 받고, exit 0 + stdout JSON 으로 결정을 반환한다.
# (exit 2 는 JSON 을 무시하고 무조건 차단하므로 여기서는 쓰지 않는다.)

set -u

# 디버그 로그는 /tmp 에 둔다. ~/.claude 하위는 샌드박스 세션에서 쓰기가 막혀
# 정작 검증이 필요한 상황에서 로그가 남지 않는다.
DEBUG_FLAG="/tmp/ask-guard.debug"
DEBUG_LOG="/tmp/ask-guard.log"

# 이 문구는 모델에게 그대로 전달된다. 금지만 적으면 다른 경로로 재시도하므로
# 대안 행동까지 명시한다. JSON 문자열에 그대로 들어가므로 " 와 \ 는 쓰지 않는다.
DENY_REASON='현재 ask 모드입니다. 파일을 수정하지 말고 분석과 설명만 하세요. 수정이 필요해 보이면 무엇을 어떻게 바꿔야 하는지 말로만 제시하세요.'

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$DENY_REASON"
  exit 0
}

log() {
  if [ -f "$DEBUG_FLAG" ]; then
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" >>"$DEBUG_LOG" 2>/dev/null || true
  fi
}

input=$(cat)

# Cursor 도 이 훅을 실행한다 — ~/.claude/settings.json 의 hooks 를 그대로 읽어간다.
# ask 모드는 Claude Code 전용 기능이므로 Cursor 의 호출에는 관여하지 않고 빠져나간다.
# 판별 키는 Cursor 만 보내는 cursor_version 이다 (Claude Code 의 입력에는 없다).
if printf '%s' "$input" | jq -e 'has("cursor_version")' >/dev/null 2>&1; then
  log "skip (cursor)"
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

if [ ! -f "$cwd/.claude/.ask" ]; then
  log "pass cwd=$cwd tool=$tool (센티널 없음)"
  exit 0
fi

case "$tool" in
  Edit | Write | NotebookEdit)
    log "deny cwd=$cwd tool=$tool"
    deny
    ;;
  Bash) ;;
  *)
    exit 0
    ;;
esac

command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# 리다이렉트 판정 전에 "쓰기가 아닌" 리다이렉트를 걷어낸다.
#   2>&1 같은 fd 복제 / /dev/null·stdout·stderr·tty / 임시 디렉토리
redirect_probe=$(printf '%s' "$command" |
  sed -E 's/[0-9]*>>?[[:space:]]*&[0-9-]+//g' |
  sed -E 's#[0-9]*>>?[[:space:]]*/dev/(null|stdout|stderr|tty)##g' |
  sed -E 's#[0-9]*>>?[[:space:]]*"?[^"[:space:]]*(\$TMPDIR|/tmp/)[^"[:space:]]*"?##g')

if printf '%s' "$redirect_probe" | grep -q '>'; then
  log "deny cwd=$cwd tool=Bash reason=redirect cmd=$command"
  deny
fi

# 명령어 위치에 나타나면 쓰기로 보는 패턴들 (확장 정규식)
WRITE_PATTERNS=(
  # 제자리 편집기
  '(^|[[:space:];&|(])(sed|perl)([[:space:]]+-[^[:space:]]+)*[[:space:]]+-i'
  # 파일·디렉토리 조작
  '(^|[[:space:];&|(])(tee|cp|mv|rm|rmdir|touch|truncate|ln|install|dd|chmod|chown|chgrp|mkdir|patch)([[:space:]]|$)'
  # 인라인 코드 실행 — 명령 문자열만으로는 쓰기 여부를 판정할 수 없다
  '(^|[[:space:];&|(])(python3?|node|perl|ruby|osascript)[[:space:]]+-(c|e)([[:space:]]|$)'
  '(^|[[:space:];&|(])(eval|source)[[:space:]]'
  # 패키지 설치·빌드 산출물
  '(^|[[:space:];&|(])(npm|pnpm|yarn|pip3?|go|cargo|brew)[[:space:]]+(i|ci|install|add|get)([[:space:]]|$)'
  '(^|[[:space:];&|(])npx([[:space:]]|$)'
  # 작업 트리를 바꾸는 git 하위 명령 (git log·status·diff 등 읽기는 통과)
  '(^|[[:space:];&|(])git[[:space:]]+(add|am|apply|checkout|cherry-pick|clean|commit|merge|mv|pull|push|rebase|reset|restore|revert|rm|stash|switch|tag|worktree)([[:space:]]|$)'
)

for pattern in "${WRITE_PATTERNS[@]}"; do
  if printf '%s' "$command" | grep -qE "$pattern"; then
    log "deny cwd=$cwd tool=Bash reason=pattern cmd=$command"
    deny
  fi
done

log "pass cwd=$cwd tool=Bash cmd=$command"
exit 0
