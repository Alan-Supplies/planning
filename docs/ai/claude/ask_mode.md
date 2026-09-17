# Claude Code "ask 모드" 구현 지시서

> **쓰는 법만 필요하면 [`ask_mode-summary.md`](./ask_mode-summary.md) 를 본다.**
> 이 문서는 구현 근거·실측 로그·설계 판단까지 담은 as-built 원문이다.

> **상태: 구현 완료 (2026-09-18).** 0단계 검증 결과 **A안 확정** — `permissions.allow` 는 건드리지 않았다.
> 추가로 Bash 우회가 실측에서 뚫리는 것을 확인해 훅에 Bash 가드를 넣었다.
> 아래는 기획서가 아니라 **as-built 문서**다. 실제 적용된 파일 내용과 실측 결과를 그대로 담는다.
> **인터랙티브 검증 완료 (2026-09-18).** 4항목 확인 — "6단계: 검증" 참고.
> 그 과정에서 두 가지가 새로 확인됐다.
> ① 슬래시 커맨드의 `!` 실행은 PreToolUse 훅을 타지 않는다 → 자기해제 우려는 사라졌다.
> ② **Cursor 가 이 훅을 같이 실행한다** (Third-Party Imports, 기본 켜짐) → `cursor_version` 키로
> 제외해 Cursor 는 ask 모드의 영향을 받지 않는다. "남은 한계" 참고.

## 목표

Claude Code에는 Cursor의 Ask에 해당하는 읽기 전용 모드가 없다. plan 모드는 읽기 전용이지만 계획 산출을 강제해서 질문 용도로는 느리다. 세션 컨텍스트를 유지한 채 편집만 켜고 끌 수 있는 토글을 만든다.

| 요소 | 역할 | 실제 경로 |
| --- | --- | --- |
| PreToolUse 훅 | 실제 강제력. 센티널이 있으면 편집 툴 + 쓰기성 Bash 차단 | `~/.claude/hooks/ask-guard.sh` |
| 센티널 파일 | 현재 모드를 나타내는 상태 | `<세션 cwd>/.claude/.ask` |
| 슬래시 커맨드 | `/ask` 한 번으로 토글 | `~/.claude/commands/ask.md` |
| statusline | 현재 모드를 항상 표시 | `~/.claude/statusline-command.sh` |
| 셸 alias | 세션 밖에서 토글 / ask 모드로 시작 | `~/.zshrc` |

## 설계 제약

- SKILL.md의 `allowed-tools`는 강제력이 없다. 나열한 툴을 사전 승인할 뿐 나머지를 차단하지 않는다. 스킬로는 이 문제를 풀 수 없다.
- 서브에이전트의 `tools:`는 강제력이 있지만 별도 컨텍스트에서 돌고 결과가 요약돼 올라온다. 질문 후 그 맥락으로 이어서 작업하는 흐름이 끊긴다.
- 그래서 훅이 유일하게 "컨텍스트 유지 + 실제 강제력"을 동시에 만족한다.

## 0단계: 사전 검증 — 결과

**A안 확정.** allow 리스트를 건드리지 않는다.

가설이었던 "`permissions.allow`에 `Edit`이 있으면 PreToolUse 훅의 `permissionDecision`이 무시된다"는 **현재 버전에서 재현되지 않았다.**

allow 리스트 실태:

| 파일 | 편집 툴 |
| --- | --- |
| `~/.claude/settings.json` | `Write`, `Read`, `Edit` 통짜로 존재 (`NotebookEdit` 없음) |
| `planning/.claude/settings.local.json` | 없음 |

즉 이슈 조건에 정확히 해당하는 상태였는데도 차단됐다. 검증은 `claude -p` 헤드리스로 **새 세션**을 띄워 측정했다 — 훅 설정은 세션 시작 시 고정되므로 기존 세션에서는 검증할 수 없다.

```sh
# 센티널 ON + acceptEdits + allow에 Edit 있음
cd "$T/on" && claude -p "target.txt 의 내용을 CHANGED 로 바꿔라." \
  --permission-mode acceptEdits --model claude-haiku-4-5-20251001
# → "현재 ask 모드에서는 파일 수정이 불가능합니다"
# → target.txt = hello (미변경)
```

## 1단계: 훅 스크립트

경로: `~/.claude/hooks/ask-guard.sh`

```bash
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
```

실행 권한을 준다.

```bash
chmod +x ~/.claude/hooks/ask-guard.sh
```

### 디버그 로그

기본 꺼져 있다. 플래그 파일을 만들면 켜진다.

```bash
touch /tmp/ask-guard.debug   # ON
rm /tmp/ask-guard.debug      # OFF
tail -f /tmp/ask-guard.log
```

## 2단계: 훅 등록

`~/.claude/settings.json`의 `hooks`에 추가한다. 기존 `hooks` 키(`Stop`, `SessionEnd`, `SessionStart`)는 덮어쓰지 않고 병합한다.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash '/Users/swkim/.claude/hooks/ask-guard.sh'",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**`command`를 `bash '<절대경로>'` 로 호출하는 이유** — 아래 "알려진 함정"의 실행 비트 fail-open을 구조적으로 제거한다. 실행 비트가 빠져도 훅이 정상 동작한다. 같은 settings.json의 기존 `herdr-agent-state.sh` 훅도 이 형식이다. 틸드 확장은 신뢰하지 말고 절대 경로로 쓴다.

`.gitignore`에 추가한다.

```text
**/.claude/.ask
```

**`**/` 접두어가 필요한 이유** — gitignore는 슬래시가 포함된 패턴을 해당 gitignore 위치 기준으로 앵커링한다. `.claude/.ask` 만 쓰면 레포 루트만 잡히고, Claude를 하위 디렉토리(예: `docs/git`)에서 띄웠을 때 생기는 `docs/git/.claude/.ask` 는 안 잡힌다.

## 3단계: 슬래시 커맨드

경로: `~/.claude/commands/ask.md` — **프로젝트가 아니라 전역**에 뒀다. 훅과 alias가 이미 전역이라 한 군데로 모으는 편이 일관되고, 모든 저장소에서 똑같이 쓸 수 있다.

```markdown
---
allowed-tools: Bash(sh:*)
disable-model-invocation: true
description: 편집 차단 모드(ask 모드)를 토글합니다
---

!`sh -c 'if [ -f .claude/.ask ]; then rm -f .claude/.ask; echo "ask 모드 OFF — 편집 가능"; else mkdir -p .claude; touch .claude/.ask; echo "ask 모드 ON — 질문만 가능"; fi'`

위 출력이 **"ask 모드 ON"** 이면 지금부터 편집 차단 상태다.

- 파일 수정(Edit/Write/NotebookEdit)과 쓰기성 쉘 명령은 훅이 거부한다. **시도하지 말고** 분석·설명으로 답한다.
- 수정이 필요해 보이면 무엇을 어떻게 바꿔야 하는지 말로 제시한다.
- 읽기·조회는 평소대로 한다 — `ls` `cat` `grep` `find` `git log` `git diff` `select` 등은 막히지 않으니 위축될 필요 없다.

**"ask 모드 OFF"** 면 평소 모드다. 별도 제약 없이 작업한다.
```

기획서의 `&&`/`||` 한 줄 대신 `if`/`else` 를 썼다. `&&` 체인은 `rm` 이 실패하면 `||` 로 흘러 **센티널을 되레 만들어버리는** 경로가 있다.

`disable-model-invocation: true`가 중요하다. 모드 전환은 사용자만 할 수 있어야 하고, 모델이 스스로 껐다 켜면 가드의 의미가 없다.

주의: 슬래시 커맨드는 한 턴을 소비한다. 질문을 던지면서 동시에 모드를 켤 수는 없다.

### 본문의 지시문 — 사전 고지 (2026-09-18 추가)

`!` 실행 아래의 산문은 **그대로 모델에게 전달된다.** 처음에는 실행 한 줄뿐이라 이 통로를 쓰지
않았는데, 그러면 모델이 ask 모드를 아는 경로가 `"ask 모드 ON"` 출력 한 줄뿐이다.

훅은 강제력은 있지만 **사전 고지를 하지 못한다** — 거부 사유는 정의상 사후다. 그래서 모델은
편집을 한 번 시도했다가 거부당한 뒤에야 설명으로 전환한다. 툴 왕복이 한 번 낭비된다.

본문에 지시문을 넣으면 **토글하는 그 순간** 전달되므로 이 왕복이 사라진다. 비용은 0이고 고칠
파일도 하나다.

문구에서 신경 쓴 것 두 가지.

- **"시도하지 말고"** 를 명시한다. 금지만 적으면 다른 경로로 재시도한다 (거부 사유 문구와 같은 이유).
- **읽기는 평소대로 하라고 못 박는다.** "수정하지 마라"만 쓰면 조회·검색까지 소극적으로 굴어
  오히려 느려진다.

**이것으로 가드를 대신하지는 않는다.** 지시문은 *빨라지게* 하는 것이고 훅은 *보장*이다.
안내를 믿고 가드를 빼면 모델이 문구를 무시했을 때 막을 것이 없다.

한계: 대화가 길어져 컨텍스트가 요약되면 이 문구도 사라질 수 있다. 그때는 `UserPromptSubmit`
훅으로 매 턴 주입하는 방법이 있다 — 요약을 넘겨 확실하지만 매 턴 비용이 붙고, Cursor 쪽
(`beforeSubmitPrompt` 로 매핑된다) 제외를 또 해야 한다. 실제로 잊는 일이 생기면 그때 붙인다.

### 해소됨 — `/ask` 로 **끄는** 동작 (2026-09-18 실측)

한때 이런 우려가 있었다: 가드가 `rm`·`touch`·`mkdir` 을 전부 차단하므로, 슬래시 커맨드의 `!` 실행이
PreToolUse 훅을 타면 `/ask` 로 ask 모드를 **끌 수 없다**. 예외를 뚫자니 모델도 같은 Bash 명령으로
끌 수 있게 되어 `disable-model-invocation` 이 무력해진다 — 트레이드오프처럼 보였다.

**실측 결과 전제가 틀렸다. 슬래시 커맨드의 `!` 실행은 PreToolUse 훅을 타지 않는다.**

훅에 입력 JSON 원본을 찍는 줄을 임시로 넣고(`log "raw=$(... | jq -c .)"`) 인터랙티브 세션에서
`/ask` 를 ON → OFF 로 눌렀다. 두 번 모두 **로그에 단 한 줄도 남지 않았다.** 같은 시간대의 다른
Bash 툴 호출은 정상적으로 `raw=` 와 `pass` 를 남겼으므로 덤프 자체는 동작하고 있었다.

```text
02:09:04  raw={...} pass   ← 일반 Bash 툴 호출
   ↓  /ask ON, /ask OFF    ← 기록 없음
02:29:43  raw={...} pass   ← 일반 Bash 툴 호출
```

따라서 **가드에 예외를 뚫을 필요가 없다.** `/ask` 는 양방향 토글로 확정이고
`disable-model-invocation` 도 그대로 유효하다. 조사용 덤프 줄은 확인 후 제거했다
(모든 명령 전문이 로그에 남기 때문이다).

셸 alias `unask` 는 여전히 탈출구로 유효하다 — 훅을 타지 않으므로 어떤 상태에서도 풀린다.

## 4단계: statusline

모드가 눈에 보이지 않으면 토글형은 금방 헷갈린다. 이미 쓰던 `~/.claude/statusline-command.sh` 에 `[ASK]` 분기만 덧붙였다(교체하지 않았다).

```bash
# ask 모드(편집 차단) 표시 — 센티널은 세션 cwd 기준이다.
ask_info=""
if [ -f "$current_dir/.claude/.ask" ]; then
  ask_info=$(printf '\033[30;43m ASK \033[0m ')
fi
```

마지막 출력줄 맨 앞에 붙인다.

```bash
printf "%s\033[2m%s\033[0m \033[2m|\033[0m \033[34m%s\033[0m%s%s" "$ask_info" "$model" "$dir_name" "$git_info" "$usage_info"
```

렌더 결과 (합성 JSON 주입으로 확인):

```text
ask OFF   Opus 5 | sl-test | ctx 12% $0.42 session 8%
ask ON     ASK  Opus 5 | sl-test | ctx 12% $0.42 session 8%
                └ 검정 글자 / 노란 배경 배지 (30;43)
```

`current_dir` 는 기존 스크립트가 이미 `.workspace.current_dir` 로 뽑아 쓰고 있어 그대로 재사용했다. `settings.json` 의 `statusLine` 설정은 변경하지 않았다.

## 5단계: 셸 alias

세션 밖에서 토글하거나 아예 ask 모드로 세션을 시작할 때 쓴다. 훅을 타지 않으므로 **항상 동작하는 탈출구**이기도 하다.

```bash
alias ask='mkdir -p .claude && touch .claude/.ask && echo "ask ON"'
alias unask='rm -f .claude/.ask && echo "ask OFF"'
```

`mkdir -p` 는 `.claude` 가 없는 디렉토리에서 `touch` 가 실패하는 것을 막는다.

### 센티널은 레포가 아니라 **세션 cwd** 기준이다

훅도 statusline도 `$cwd/.claude/.ask` 만 본다. Claude를 `docs/git` 에서 띄웠다면 센티널도 `docs/git/.claude/.ask` 여야 한다. 레포 루트에 만들면 안 걸린다.

## 6단계: 검증

### 자동 검증 완료 — 훅 (헤드리스 새 세션, `--permission-mode acceptEdits`)

| 항목 | 결과 |
| --- | --- |
| 센티널 없이 파일 수정 요청 | 통과 — `CHANGED` 로 수정됨 |
| 센티널 있고 파일 수정 요청 | 통과 — 거부 + 사유가 모델에 전달돼 설명으로 전환 |
| 센티널 제거 후 수정 요청 | 통과 |
| ask 모드 + `echo CHANGED > target.txt` | 차단 |
| ask 모드 + `cat` heredoc 덮어쓰기 | 차단 |
| ask 모드 + `sed -i` | 차단 |
| ask 모드 + `cat target.txt` (읽기) | 통과 |
| 평소 모드 + `echo CHANGED > target.txt` | 통과 (영향 없음) |

Bash 가드 패턴 단위 테스트 30건 전부 통과. 통과 확인된 읽기 명령: `ls` `cat` `grep` `find` `jq` `mysql -e "select ..."` `git log/status/diff/branch` `echo hello` `ls > /dev/null` `cmd 2>&1` `python3 script.py` `echo x > $TMPDIR/...`

statusline 은 합성 JSON 주입으로 ON/OFF 양쪽 렌더를 확인했다.

### 인터랙티브 검증 — 완료 (2026-09-18)

`claude -p` 는 슬래시 커맨드를 실행하지 않고 세션 재개(`-c`)도 이어지지 않아, 아래는 실제
인터랙티브 세션에서 확인했다.

```bash
touch /tmp/ask-guard.debug   # 증거 수집 ON
```

| # | 확인할 것 | 결과 |
| --- | --- | --- |
| 1 | `/ask` 호출 시 statusline 노란 `ASK` 배지 | 화면 육안 확인 — 별도 이의 없었음 (로그로 남지 않는 항목) |
| 2 | 거부 이후 후속 질문의 맥락 유지 | **통과** — `Write` 가 `deny` 된 뒤에도 앞 대화가 그대로 이어졌다 |
| 3 | `/ask` 재호출로 끄기 | **통과** — 막히지 않는다. 훅 자체를 안 타기 때문이다 (3단계 참고) |
| 4 | 모델이 ask 모드를 해제하지 못함 | **통과** — `disable-model-invocation: true` 로 모델은 `/ask` 를 호출할 수 없다 |

2번의 실제 로그 (경로는 세션 cwd):

```text
2026-09-18T02:01:54 deny cwd=.../planning/docs/git tool=Write
```

```bash
cat /tmp/ask-guard.log
rm /tmp/ask-guard.debug  # 증거 수집 OFF
```

**로그는 이 훅을 쓰는 모든 도구·세션이 공유한다.** 디버그를 켜두면 다른 저장소에서 돌고 있는
Cursor 세션의 명령까지 같은 파일에 쌓이고, 두 프로세스가 동시에 append 하면 줄이 섞여 깨진다.
조사가 끝나면 플래그를 반드시 끈다. ("남은 한계" 참고)

## 알려진 함정

- **실행 비트 누락 시 fail-open.** 스크립트에 실행 권한이 없으면 훅이 실행되지 못하고 툴 호출은 그대로 통과한다. 경고만 뜨고 차단은 되지 않으므로 막힌 줄 알고 넘어가기 쉽다. → 2단계에서 `bash '<경로>'` 호출로 제거했다. statusline 스크립트도 `chmod +x` 확인.
- **exit code 의미.** exit 0 + stdout JSON으로 결정을 반환한다. exit 2는 JSON을 무시하고 무조건 차단한다. 여기서는 exit 0 경로만 쓴다.
- **구 형식 사용 금지.** PreToolUse에서 최상위 `{"decision": "block"}`은 폐기됐다. `hookSpecificOutput` 안에 `hookEventName`과 `permissionDecision`을 넣는다. PostToolUse는 형식이 다르니 스니펫을 서로 복사하지 말 것.
- **훅은 deny/ask 권한 규칙을 우회하지 못한다.** allow 결정도 `permissions.deny`에 걸린 항목은 뚫지 못한다.
- **Bash 우회는 이론이 아니라 실측으로 확인됐다.** 가드 이전, 편집 툴이 거부되자 모델은 곧바로 `echo CHANGED > target.txt` 로 우회했고 `cat` heredoc·`sed -i` 도 모두 통과했다. 근거가 된 allow 항목: `Bash(echo:*)`, `Bash(cat > *)`, `Bash(sed:*)`, `Bash(python3 *)`, `Bash(node:*)`, `Bash(npx:*)`. → 1단계 Bash 가드로 막았다.
- **allow 리스트에서 개별 항목을 빼는 방식은 쓰지 않는다.** `Bash(echo:*)` 하나를 빼도 `cat > *`·`sed:*`·`python3 *`·`node:*` 가 남아 효과가 없고, 평소 작업에서 `echo` 가 복합 명령의 하위 명령마다 검사되므로 불편만 커진다. 조이는 지점은 훅 한 곳으로 모은다.
- **acceptEdits 는 Bash를 커버하지 않는다.** acceptEdits 는 편집 *툴*(Edit/Write/NotebookEdit)만 자동승인하고, Bash 는 `permissions.allow` 의 Bash 규칙이 별도로 관장한다. 모드를 뭘로 두든 Bash 쓰기는 allow 리스트대로 간다.
- ~~**가드가 자기 자신의 해제를 막을 수 있다.**~~ → **해당 없음 (2026-09-18 실측).** 슬래시 커맨드의 `!` 실행은 PreToolUse 훅을 타지 않으므로 `/ask` 의 `rm` 은 가드 대상이 아니다. 3단계 참고.
- **`claude -p` 는 슬래시 커맨드를 실행하지 않는다.** ON/OFF 양방향 모두 무반응·무출력이었다. 슬래시 커맨드 검증은 인터랙티브로만 가능하다.
- **디버그 로그는 다른 도구와 공유된다.** `/tmp/ask-guard.log` 는 이 훅을 실행하는 모든 프로세스가 함께 쓴다. 로그를 해석할 때 "내 세션 것"이라고 단정하면 안 된다 — `cwd` 와 `session_id` 로 걸러야 한다. 실제로 이 가정 때문에 한 번 잘못된 결론을 냈다.
- **거부 사유 문구가 동작에 영향을 준다.** 이 텍스트는 모델에게 그대로 전달된다. 단순 금지 문구만 쓰면 다른 경로로 재시도하므로, 대안 행동(설명만 하라)까지 명시한다.

## 남은 한계

- **MCP 쓰기 툴은 걸리지 않는다.** matcher 는 툴 이름 기준이라 Notion·Linear·Slack 같은 MCP 쓰기 툴은 ask 모드에서도 동작한다. ask 모드는 "로컬 파일 읽기 전용"이지 전방위 읽기 전용이 아니다. 필요하면 matcher 에 해당 툴명을 추가한다.

### Cursor 가 이 훅을 같이 실행한다 (2026-09-18 발견 → 제외 처리 완료)

조사 중에 훅 입력을 덤프해 보니 로그 120줄 중 대부분이 이 세션이 아니라 **Cursor** 것이었다.

```json
{"model":"gpt-5.6-sol","tool_name":"Shell","cursor_version":"3.20.17",
 "hook_event_name":"preToolUse","cwd":"/Users/swkim/workspace/supplies/gymboxx-lib",
 "workspace_roots":["...gymboxx-app-server","...gymboxx-lib"]}
```

| 호출한 cwd | 건수 |
| --- | --- |
| `gymboxx-app-server` | 44 |
| `gymboxx-lib` | 36 |
| `planning/docs/git` (Claude Code 세션) | 8 |

`ask-guard` 를 등록한 설정은 **`~/.claude/settings.json` 하나뿐이다.** `~/.cursor/hooks.json` 에는
`sessionStart` 만 있고 ask-guard 는 없다. 즉 Cursor 3.20.17 이 Claude Code 의 `settings.json` 훅을
읽어서 실행한다.

여기서 나오는 한계 세 가지.

- **Cursor 에서는 Bash 가드가 작동하지 않는다.** Cursor 의 쉘 툴 이름은 `Bash` 가 아니라 `Shell` 이라
  가드의 `case` 문에서 `*)` 로 빠져 그냥 통과한다. 반면 `Write` 는 이름이 같아 **차단된다.**
  ask 모드가 Cursor 에서는 반쪽으로만 걸린다.
- **의도치 않은 차단이 가능하다.** `gymboxx-lib` 같은 다른 저장소에 `.claude/.ask` 센티널이 생기면
  그 디렉토리에서 돌던 Cursor 의 `Write` 도 같이 막힌다. `ask` alias 를 쓸 때 Claude Code 만
  조인다고 생각하면 안 된다.
- **로그가 인터리브돼 깨진다.** 두 프로세스가 같은 파일에 동시에 append 해서 JSON 한 줄이 중간에
  잘린 사례가 실제로 있었다.

#### 원인 — Cursor 의 의도된 기능이다

버그가 아니다. Cursor 의 **Third-Party Imports** 기능이 `.claude/settings.local.json`,
`.claude/settings.json`, `~/.claude/settings.json` 세 곳의 훅을 읽어간다. **기본값이 켜짐**이라
따로 설정한 적이 없어도 동작한다. `.cursorrules` 와는 별개 계층이다.

읽으면서 이름도 매핑한다 — 그래서 matcher 는 Claude Code 이름으로 쓰는데 스크립트에는 Cursor
이름이 도착한다. 이 어긋남이 "matcher 에는 걸리는데 `case` 문에서는 빠지는" 현상의 정체다.

| Claude Code | → Cursor |
| --- | --- |
| `PreToolUse` | `preToolUse` |
| `PostToolUse` | `postToolUse` |
| `UserPromptSubmit` | `beforeSubmitPrompt` |
| `Bash` | `Shell` |
| `Edit` | `Write` |
| `Glob` | (미지원) |

`Edit` → `Write` 매핑 때문에 Cursor 쪽 편집이 가드의 `Write` 분기에 걸렸고, `Bash` → `Shell` 매핑
때문에 쉘은 `*)` 로 빠졌다. 반쪽으로 걸린 이유가 이것이다.

#### 적용한 해결 — 스크립트에서 Cursor 를 제외한다

ask 모드는 Claude Code 전용 기능이므로 Cursor 호출에는 아예 관여하지 않는다.
`input=$(cat)` 직후에 둔다.

```bash
# Cursor 도 이 훅을 실행한다 — ~/.claude/settings.json 의 hooks 를 그대로 읽어간다.
# ask 모드는 Claude Code 전용 기능이므로 Cursor 의 호출에는 관여하지 않고 빠져나간다.
# 판별 키는 Cursor 만 보내는 cursor_version 이다 (Claude Code 의 입력에는 없다).
if printf '%s' "$input" | jq -e 'has("cursor_version")' >/dev/null 2>&1; then
  log "skip (cursor)"
  exit 0
fi
```

합성 JSON 주입으로 확인했다 (센티널 ON 상태).

| 입력 | 결과 |
| --- | --- |
| Cursor `Write` | 통과 (무출력) |
| Cursor `Shell` + `rm -rf x` | 통과 (무출력) |
| Claude Code `Write` | **deny** |
| Claude Code `Bash` + `rm -rf ...` | **deny** |
| Claude Code `Bash` + `cat foo` | 통과 |

#### 쓰지 않은 대안 — Cursor 토글 끄기

Cursor Settings → Agents → Third-Party Imports 의
"Include Third-Party Plugins, Skills, and Other Configs" 를 끄면 Claude Code 설정을 아예 안 읽는다.

**이 방법은 쓰지 않았다.** 토글은 훅만이 아니라 third-party plugin·skill 까지 통째로 끈다.
같은 `settings.json` 에 있는 `herdr-agent-state.sh` 의 SessionStart 훅도 함께 죽는다.
ask-guard 하나만 빼고 싶은 것이므로 스크립트 레벨 제외가 정밀하다.
Cursor 쪽에서 Claude 설정을 전부 끊고 싶어질 때를 위해 경로만 기록해 둔다.
- **오탐 2가지.** ①`grep -rn cp .` 처럼 따옴표 없는 인자에 `cp`·`rm` 같은 단어가 오면 걸린다(따옴표를 씌우면 통과). ②`git commit` 류가 전부 막힌다 — 의도한 동작이지만 ask 모드에서 커밋하려다 막히면 당황할 수 있다.
- 오탐 비용은 낮다고 판단했다. 잘못 막혀도 모델이 설명으로 전환할 뿐이고 `unask` 하면 된다. 반대로 미탐은 기능 자체를 무의미하게 만든다. 그래서 경계선은 거부 쪽으로 잡았다.

## 완료 기준

- [x] 0단계 검증 결과와 선택한 안(A안) 보고
- [x] 기존 `settings.json` 내용 보존 (`Stop`/`SessionEnd`/`SessionStart` 유지, JSON 파싱 확인)
- [x] Bash 우회 차단 및 읽기 명령 통과 확인
- [x] statusline 에 ask 모드 표시 (기존 스크립트 보존)
- [x] 6단계 인터랙티브 4항목 확인 (2026-09-18) — 2·3·4번 로그로 통과, 1번(배지)은 육안 확인
- [x] Cursor 대응 (2026-09-18) — `cursor_version` 키로 제외. Cursor 는 ask 모드의 영향을 받지 않는다
- [x] 사전 고지 (2026-09-18) — `/ask` 커맨드 본문에 지시문 추가. 편집 시도→거부 왕복 제거
- [ ] (필요해지면) `UserPromptSubmit` 훅으로 매 턴 주입 — 컨텍스트 요약을 넘겨 유지하고 싶을 때
