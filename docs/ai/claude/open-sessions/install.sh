#!/usr/bin/env bash
# /open-sessions 설치 — 이 디렉토리의 파일을 ~/.claude 로 심볼릭 링크한다.
#
# 링크를 쓰는 이유: 저장소 파일이 실물 하나로 유지되므로 git pull 하면 모든 머신에 반영된다.
# 복사본을 두면 머신마다 갈라지고, 문서와 실제가 어긋나도 알아챌 방법이 없다.
#
# 이 스크립트가 하지 않는 것 — settings.json 은 건드리지 않는다.
# 이 도구는 훅을 쓰지 않으므로 애초에 등록할 것이 없다.
#
# 사용법: bash install.sh
# 롤백:   bash install.sh --uninstall

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP=$(date '+%Y%m%d%H%M%S')

# 백업은 skills/ · commands/ 바깥에 둔다.
# skills/ 안에 남긴 백업 디렉토리는 SKILL.md 를 품고 있어 같은 이름의 스킬로 또 잡힌다.
BACKUP_DIR="$CLAUDE_DIR/.backups"

# 링크 대상: <저장소 경로> <설치 위치>
# skill 은 디렉토리째 링크한다 — SKILL.md 와 scripts/ 가 같이 따라와야 한다.
TARGETS=(
  "skill:$CLAUDE_DIR/skills/open-sessions"
  "command/open-sessions.md:$CLAUDE_DIR/commands/open-sessions.md"
)

uninstall() {
  echo "/open-sessions 제거"
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
  echo "저장소 파일은 그대로다. ~/.claude/.backups 의 백업은 직접 정리한다."
  exit 0
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
fi

echo "/open-sessions 설치"
echo "  원본: $SRC"
echo

echo "1) 사전 조건"
if command -v python3 >/dev/null 2>&1; then
  echo "  python3: $(python3 --version 2>&1)"
else
  echo "  python3 없음 — 이 도구는 python3 로만 돌아간다. 설치 후 다시 실행한다." >&2
  exit 1
fi
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "  gh: 로그인됨 — PR 상태까지 조회한다"
else
  echo "  gh: 없거나 미로그인 — PR 칸만 비고 나머지는 정상 동작한다"
fi
echo

echo "2) 파일 링크"
for entry in "${TARGETS[@]}"; do
  src="$SRC/${entry%%:*}"
  dst="${entry#*:}"
  mkdir -p "$(dirname "$dst")"

  # 이미 이 저장소를 가리키고 있으면 그대로 둔다.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "  이미 링크됨: $dst"
    continue
  fi

  # 실물 파일/디렉토리가 있으면 지우지 않고 백업한다 — 머신마다 다를 수 있다.
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    backup="$BACKUP_DIR/$(basename "$dst").bak.$STAMP"
    mv "$dst" "$backup"
    echo "  기존 항목 백업: $backup"
  fi

  ln -sfn "$src" "$dst"
  echo "  링크: $dst"
done
echo

echo "3) 동작 확인"
if python3 "$SRC/skill/scripts/open_sessions.py" --no-net >/dev/null 2>&1; then
  echo "  스크립트 실행 OK"
else
  echo "  스크립트 실행 실패 — 아래 명령으로 원인을 본다" >&2
  echo "  python3 $SRC/skill/scripts/open_sessions.py --no-net" >&2
  exit 1
fi
echo

cat <<'GUIDE'
설치 완료.

Claude Code 는 스킬·명령 목록을 세션 시작 때 읽는다. 새로 깐 직후에는 안 보인다.
  - VSCode: Cmd+Shift+P -> "Developer: Reload Window"
  - CLI   : claude 를 새로 띄운다

확인:  /open-sessions
GUIDE
