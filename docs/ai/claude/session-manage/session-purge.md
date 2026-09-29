# Claude Code 세션 기록 삭제 (session-purge)

## 목표

테스트·잡담처럼 **남길 이유가 없는 세션**을 종료 시점에 흔적까지 지운다.
`local/claude-sessions.md` 목록(→ [session-recap.md](session-recap.md))에 계속 "[부분] …" 으로 남아
매 세션 시작마다 따라붙는 걸 없애는 게 실질적인 목적이다.

Claude Code 에는 "exit 하면서 이 세션 지우기" 기능이 없다. `SessionEnd` 훅으로 직접 붙인다.

## 트리거: 표시한 세션만

매 종료마다 지우거나 `/clear` 로 트리거하는 방식도 가능하지만 쓰지 않는다.

| 방식 | 문제 |
|---|---|
| 모든 종료에서 삭제 | 창을 닫기만 해도 날아간다. `--resume`/`--continue` 가 사실상 불가능해진다 |
| `reason == "clear"` | 습관적으로 `/clear` 치는 멀쩡한 세션까지 같이 사라진다 |
| **마커 파일 (채택)** | 표시하지 않으면 훅이 아무것도 하지 않는다. 실수로 날아갈 일이 없다 |

표시 방법:

```sh
mkdir -p ~/.claude/purge-sessions
touch ~/.claude/purge-sessions/<session-id>
```

세션 id 는 `~/.claude/projects/<경로를-/로-치환>/` 에서 지금 쓰고 있는 `<id>.jsonl` 이며,
스크래치패드 경로 `/private/tmp/claude-*/<slug>/<id>` 의 마지막 조각과 같다.

## 지우는 대상

- `~/.claude/projects/<slug>/<session-id>.jsonl` — 대화 원본
- `/private/tmp/claude-*/<slug>/<session-id>` — 스크래치패드 디렉터리
- 마커 파일 자체

`local/claude-sessions.md` 는 **직접 손대지 않는다.** recap 이 transcript 디렉터리를 매번 훑어
새로 그리므로, 원본이 없어지면 다음 `SessionStart` 에서 목록에서도 자동으로 빠진다.

## 설치

### 1. 훅 스크립트

`~/.claude/hooks/session-purge.sh` 로 저장하고 `chmod +x` 한다. (`jq` 필요 — `/usr/bin/jq` 로 기본 존재)

```bash
#!/bin/bash
# SessionEnd 훅 — 표시된 세션만 종료 시 transcript 삭제
set -u
MARK_DIR="$HOME/.claude/purge-sessions"
LOG="$MARK_DIR/.log"

payload=$(cat 2>/dev/null) || exit 0
sid=$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null)
transcript=$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null)

[ -n "$sid" ] || exit 0
marker="$MARK_DIR/$sid"
[ -f "$marker" ] || exit 0   # 표시 없으면 아무것도 안 함

if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  transcript=$(ls "$HOME/.claude/projects"/*/"$sid.jsonl" 2>/dev/null | head -1)
fi

# 안전장치: ~/.claude/projects 아래 <session-id>.jsonl 만
case "$transcript" in
  "$HOME/.claude/projects/"*"/$sid.jsonl")
    rm -f "$transcript" && echo "$(date '+%F %T') removed $transcript" >>"$LOG" ;;
esac

for d in /private/tmp/claude-*/*/"$sid"; do
  [ -d "$d" ] && rm -rf "$d" && echo "$(date '+%F %T') removed $d" >>"$LOG"
done

rm -f "$marker"
exit 0
```

설계상 지킨 것:
- 마커가 없으면 즉시 `exit 0` — 기본 동작은 "아무것도 안 함"
- 경로 `case` 매칭으로 `~/.claude/projects/*/<sid>.jsonl` 외에는 지우지 않는다
- 스크래치패드도 디렉터리 이름이 세션 id 와 정확히 같을 때만
- 무슨 일이 있어도 `exit 0` — 종료를 막지 않는다
- 지운 것은 `~/.claude/purge-sessions/.log` 에 남긴다

### 2. settings.json 등록

`~/.claude/settings.json` 의 `hooks.SessionEnd` 배열에 항목을 **추가**한다
(기존 `cc-hud-report.sh`, `session-recap.py end` 는 그대로 둔다).

```json
{
  "hooks": [
    { "type": "command", "command": "bash '/Users/sungwookkim/.claude/hooks/session-purge.sh'", "timeout": 10 }
  ]
}
```

### 3. 확인

```sh
# 문법
bash -n ~/.claude/hooks/session-purge.sh

# 마커 없을 때 아무 일도 없어야 한다
echo '{"session_id":"test-none","transcript_path":""}' | bash ~/.claude/hooks/session-purge.sh; echo "exit=$?"

# 마커가 있어도 projects 밖 경로는 건드리지 않아야 한다
mkdir -p ~/.claude/purge-sessions && touch ~/.claude/purge-sessions/test-safe
echo '{"session_id":"test-safe","transcript_path":"/tmp/not-a-transcript"}' | bash ~/.claude/hooks/session-purge.sh
ls /tmp/not-a-transcript 2>/dev/null   # 없어야 정상(애초에 안 만든 파일), 마커만 사라진다
```

## 주의

- **되돌릴 수 없다.** 지운 세션은 `--resume` / `--continue` 불가, 내용 조회 불가.
- recap 과 purge 는 같은 `SessionEnd` 에서 함께 돈다. 순서에 따라 방금 끝낸 세션이
  `claude-sessions.md` 에 한 번 더 남을 수 있지만, 다음 `SessionStart` 에서 사라진다.
- 세션이 **살아 있는 동안** transcript 를 지우는 건 의미가 없다 — Claude Code 가 턴마다 다시 쓴다.
  그래서 삭제 시점을 `SessionEnd` 로 잡았다.

## Claude 는 이 훅을 직접 설치하지 못한다 (2026-09-29 확인)

Claude Code 에 이 스크립트를 파일로 쓰게 하면 권한 분류기가 거부한다.

```text
Permission denied by auto mode classifier. Reason: [Session Transcript Tampering]
```

`Write` 툴, `cat > ... <<'EOF'` 힙독 둘 다 막혔다. transcript 삭제 로직을 심는 행위 자체가
가드레일 대상이다. 우회하지 말고 **사람이 직접 설치**한다 — 프롬프트에 `!` 를 붙여 실행하면
출력이 세션에 그대로 들어온다. 문서(이 파일)로 남기는 것은 막히지 않는다.
