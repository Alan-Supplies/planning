#!/usr/bin/env bash
# gymboxx-lib-version 스킬을 ~/.claude/skills 에 심볼릭 링크로 설치한다.
# 링크라서 이 레포를 git pull 하면 스킬도 같이 갱신된다.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/skill/gymboxx-lib-version"
DEST="$HOME/.claude/skills/gymboxx-lib-version"

mkdir -p "$HOME/.claude/skills"

if [ -L "$DEST" ]; then
  ln -sfn "$SRC" "$DEST"
elif [ -e "$DEST" ]; then
  echo "❌ $DEST 가 링크가 아닌 실제 디렉터리로 있다. 내용을 확인하고 옮긴 뒤 다시 실행한다." >&2
  exit 1
else
  ln -s "$SRC" "$DEST"
fi
echo "✅ $DEST -> $SRC"

# 선행 조건 점검 (설치는 막지 않는다)
LIB_DIR=${LIB_DIR:-$HOME/workspace/supplies/gymboxx-lib}
APP_DIR=${APP_DIR:-$HOME/workspace/supplies/gymboxx-app-server}
[ -d "$LIB_DIR/.git" ] || echo "⚠️ gymboxx-lib 클론이 없다: $LIB_DIR (다른 곳이면 LIB_DIR 을 셸 프로필에 export)"
[ -d "$APP_DIR/.git" ] || echo "⚠️ gymboxx-app-server 클론이 없다: $APP_DIR (다른 곳이면 APP_DIR 을 셸 프로필에 export)"
if [ -d "$LIB_DIR" ]; then
  (cd "$LIB_DIR" && npm view @suppliesfitness/gymboxx-lib version >/dev/null 2>&1) \
    || echo "⚠️ npm 에서 @suppliesfitness/gymboxx-lib 을 조회하지 못했다 — GitHub Packages 토큰(~/.npmrc) 확인"
fi
