#!/usr/bin/env bash
# ask 모드 설치 — 이 디렉토리의 파일을 ~/.claude 로 심볼릭 링크한다.
#
# 링크를 쓰는 이유: 저장소 파일이 실물 하나로 유지되므로 git pull 하면 모든 머신에 반영된다.
# 복사본을 두면 머신마다 갈라지고, 문서와 실제가 어긋나도 알아챌 방법이 없다.
#
# 이 스크립트가 하지 않는 것 — settings.json 은 건드리지 않는다.
# 기존 훅(Stop/SessionStart 등)을 망칠 위험이 있어 자동 병합하지 않는다. 안내만 출력한다.
#
# 사용법: bash install.sh
# 롤백:   bash install.sh --uninstall

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP=$(date '+%Y%m%d%H%M%S')

# 링크 대상: <저장소 파일> <설치 위치>
TARGETS=(
  "ask-guard.sh:$CLAUDE_DIR/hooks/ask-guard.sh"
  "ask.md:$CLAUDE_DIR/commands/ask.md"
  "statusline-command.sh:$CLAUDE_DIR/statusline-command.sh"
)

uninstall() {
  echo "ask 모드 제거"
  for entry in "${TARGETS[@]}"; do
    dst="${entry#*:}"
    if [ -L "$dst" ]; then
      rm "$dst"
      echo "  링크 제거: $dst"
    elif [ -e "$dst" ]; then
      echo "  건너뜀(링크가 아님): $dst"
    fi
  done
  echo
  echo "저장소 파일은 그대로다. .zshrc 의 alias 와 settings.json 의 훅 등록은 직접 지운다."
  exit 0
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
fi

echo "ask 모드 설치"
echo "  원본: $SRC"
echo

echo "1) 파일 링크"
for entry in "${TARGETS[@]}"; do
  src="$SRC/${entry%%:*}"
  dst="${entry#*:}"
  mkdir -p "$(dirname "$dst")"

  # 이미 이 저장소를 가리키고 있으면 그대로 둔다.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "  이미 링크됨: $dst"
    continue
  fi

  # 실물 파일이 있으면 지우지 않고 백업한다 — 머신마다 다를 수 있다.
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.bak.$STAMP"
    echo "  기존 파일 백업: $dst.bak.$STAMP"
  fi

  ln -sfn "$src" "$dst"
  echo "  링크: $dst"
done
echo

echo "2) 셸 alias (~/.zshrc)"
if grep -q "alias unask=" "$HOME/.zshrc" 2>/dev/null; then
  echo "  이미 있음 — 건너뜀"
else
  cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$STAMP" 2>/dev/null || true
  cat >>"$HOME/.zshrc" <<'ZSHRC'

# Claude Code ask 모드 — 세션 밖에서 토글한다. 훅을 타지 않으므로 항상 동작하는 탈출구다.
alias ask='mkdir -p .claude && touch .claude/.ask && echo "ask mode ON"'
alias unask='rm -f .claude/.ask && echo "ask mode OFF"'
ZSHRC
  echo "  추가함 (백업: ~/.zshrc.bak.$STAMP)"
  echo "  새 셸을 열거나 'source ~/.zshrc' 를 실행한다."
fi
echo

echo "3) ~/.claude/settings.json — 직접 넣는다 (이 스크립트는 건드리지 않는다)"
cat <<'GUIDE'
  기존 hooks 키를 덮어쓰지 말고 PreToolUse 항목만 병합한다.

  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit|Bash",
        "hooks": [
          { "type": "command", "command": "bash '<HOME>/.claude/hooks/ask-guard.sh'", "timeout": 10 }
        ]
      }
    ]
  }

  statusline 을 쓰려면 같은 파일에 아래도 필요하다.

  "statusLine": { "type": "command", "command": "bash '<HOME>/.claude/statusline-command.sh'" }

  <HOME> 는 실제 홈 경로로 바꾼다. 틸드(~)는 확장되지 않으니 절대 경로로 쓴다.
GUIDE
echo
echo "4) .gitignore 에 센티널 제외가 있는지 확인한다 — **/.claude/.ask"
echo
echo "설치 완료. 새 Claude Code 세션에서 /ask 를 눌러 확인한다."
