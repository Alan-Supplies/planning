# Claude Code 세션 목적·완료 정리

## 목표

프로젝트에서 열린 Claude Code 세션이 **무엇을 하려 했는지**, **끝났는지**를 손이 안 가게 남긴다.
Cursor 새 탭에서 Claude Code를 켜고, 탭에는 `/exit`가 없어서 그냥 닫는 흐름을 전제로 한다.

산출물:
- `$PROJECT/local/claude-sessions.md` — 프로젝트가 `local/`을 쓰거나 `.gitignore`에 `local`이 있을 때
- `~/.claude/projects/<경로를-/로-치환>/session-recap.md` — 항상

형식은 훑는 용도라 **줄 사이 빈 줄을 넣지 않는다.**

## 새 컴퓨터에 설치

이 폴더의 두 파일이 설치 원본이다.

| 파일 | 역할 |
|---|---|
| `session-recap.md` | 동작 설명과 설치 지시 |
| `session-recap.py` | 실제 훅 스크립트 |

새 컴퓨터에서 이 저장소를 받은 뒤 Claude Code에 다음과 같이 요청한다.

> `docs/ai/claude/session-manage/session-recap.md`를 읽고, 같은 폴더의
> `session-recap.py`를 사용해 이 컴퓨터의 Claude Code에 설치해줘.
> 기존 `~/.claude/settings.json` 설정과 훅은 덮어쓰지 말고 보존하고,
> 설치 후 실제 동작까지 검증해줘.

Claude는 다음 설치 절차를 수행해야 한다.

1. `python3`가 실행 가능한지 확인한다.
2. `~/.claude/hooks/`, `~/.claude/commands/` 디렉터리를 만든다.
3. 이 폴더의 `session-recap.py`를 `~/.claude/hooks/session-recap.py`로 복사한다.
4. 아래 내용으로 `~/.claude/commands/sessions.md`를 생성하거나 갱신한다.
5. `~/.claude/settings.json`의 기존 내용을 읽고, 아래 세 훅을 기존 배열에 **중복 없이 병합**한다.
6. JSON 문법이 유효한지 확인한다.
7. 프로젝트 루트에서 `python3 ~/.claude/hooks/session-recap.py print`를 실행해 수동 동작을 확인한다.
8. 새 Claude Code 탭을 열어 `SessionStart`와 다음 답변의 `Stop` 훅을 확인한다.

`~/.claude/commands/sessions.md` 내용:

```markdown
---
description: 이 프로젝트 Claude 세션 목적·완료 여부 정리
allowed-tools: Bash(python3 *)
---

아래는 방금 다시 그린 세션 정리입니다. 훅이 이미 파일을 유지하므로 이 명령은 확인용이다.

!`python3 "$HOME/.claude/hooks/session-recap.py" print`

이 내용을 요약하지 말고 **표/목록 그대로** 보여줘. 파일을 수정하거나 다른 도구를 쓰지 마.
미완·부분·진행중이 있으면 맨 위에 한 줄만 짚어줘.
```

### 설치 안전 규칙

- `~/.claude/settings.json` 전체를 이 컴퓨터의 설정으로 교체하지 않는다.
- 기존 `hooks`의 `PreToolUse`, `Stop`, `SessionEnd`, `SessionStart` 및 다른 이벤트를 삭제하지 않는다.
- 같은 `session-recap.py` command가 이미 있으면 두 번 추가하지 않는다.
- 설치 원본은 이 폴더의 파일이며, 생성 결과인 각 프로젝트의 `session-recap.md`를 설치 원본으로 사용하지 않는다.
- 훅은 fail-open이다. 설치 실패가 Claude Code 사용이나 도구 실행을 막도록 바꾸지 않는다.
- 스크립트는 사용자 홈을 `Path.home()`과 `$HOME`으로 찾으므로 컴퓨터별 `/Users/<name>` 절대경로를 넣지 않는다.
- 설정은 Claude Code 프로세스 시작 시 읽히므로 이미 열린 탭이 아니라 **새 탭에서 검증**한다.

### 세션 기록 동기화 범위

설치는 같은 기능을 재현하지만 집 컴퓨터의 과거 세션을 회사 컴퓨터로 복제하지는 않는다.

- 원문은 각 컴퓨터의 `~/.claude/projects/<slug>/*.jsonl`에 로컬로 존재한다.
- 프로젝트 절대경로가 다르면 `<slug>`도 달라져 서로 다른 프로젝트 기록으로 취급된다.
- `$PROJECT/local/claude-sessions.md`는 결과 캐시이며 원문을 대체하지 않는다.
- 과거 기록까지 이어 보려면 jsonl을 별도로 안전하게 동기화해야 한다. 기본 설치 범위에는 포함하지 않는다.

## 왜 스킬이 아닌가

스킬은 모델이 description을 보고 호출할지 고른다. 세션이 끝났다고 실행되지 않고, 잊히거나 다른 일에 밀린다.
Cursor 스킬(`.cursor/skills`)과 Cursor `sessionEnd` 훅은 Cursor 에이전트에만 걸린다. 새 탭 Claude Code는 `entrypoint: cli`라 **`~/.claude/settings.json` 훅만** 탄다.

공식 `/receipts`, `/session-report`는 토큰·사용량용이다. 목적·완료는 안 나온다.

## 자동의 실체

탭을 닫을 때 `SessionEnd`를 믿으면 안 된다. Cursor 탭은 그냥 꺼진다.

그래서 **Stop**(답 한 번 끝날 때마다)이 본체다. 마지막 답 시점의 상태가 파일에 남는다. 탭을 닫아도 그 파일이 남는다.

| 이벤트 | 역할 |
|---|---|
| Stop | 매 턴 해당 프로젝트 jsonl을 다시 그려 파일을 갱신. 승인·모델 호출 없음 |
| SessionEnd | 닫힐 때 한 번 더. 없어도 Stop이 이미 갱신함 |
| SessionStart | 죽은 세션 백필. 미완·부분·진행중만 다음 탭 컨텍스트에 넣음. 묻기 전에는 나열하지 않음 |
| `/sessions` | 확인용. 훅이 이미 유지하므로 습관이 필수는 아님 |

Stop에 프롬프트 훅을 넣지 않는다. 매 턴 모델을 한 번 더 부르게 된다.

이미 열린 탭은 훅을 모른다. 설정은 프로세스 시작 때 읽는다. **다음 탭부터** 동작한다.

## 파일

| 경로 | 역할 |
|---|---|
| `~/.claude/hooks/session-recap.py` | 추출·판정·렌더. `start` / `stop` / `end` / `print` |
| `~/.claude/commands/sessions.md` | `/sessions` — `print` 결과를 그대로 보여 줌 |
| `~/.claude/settings.json` → `hooks` | Stop / SessionEnd / SessionStart 에 스크립트 연결 |

원본 세션은 `~/.claude/projects/<slug>/*.jsonl`이다. slug는 프로젝트 절대경로의 `/`를 `-`로 바꾼 값이다.
예: `/Users/swkim/workspace/supplies/gymboxx-lib` → `-Users-swkim-workspace-supplies-gymboxx-lib`

프로젝트 `local/`은 gitignore에 둔다. 세션 정리는 커밋하지 않는다.

## 설정

기존 `hooks` 키를 덮어쓰지 말고 병합한다. `ask_mode.md`의 PreToolUse와 같이 산다.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$HOME/.claude/hooks/session-recap.py\" stop",
            "timeout": 15
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$HOME/.claude/hooks/session-recap.py\" end",
            "timeout": 15
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$HOME/.claude/hooks/session-recap.py\" start",
            "timeout": 20
          }
        ]
      }
    ]
  }
}
```

훅은 JSON을 stdout에 돌려주고 `suppressOutput: true`다. 실패해도 Claude를 막지 않는다 (fail-open).
한 경로 쓰기가 막혀도 다른 경로는 시도한다. 샌드박스가 `~/.claude/projects` 쓰기를 막아도 프로젝트 `local/`만 살아 있으면 된다.

수동 재생성:

```bash
python3 ~/.claude/hooks/session-recap.py print
```

프로젝트 루트에서 실행한다. cwd로 jsonl 위치를 찾는다.

## 판정

jsonl에서 `aiTitle`, 첫 사용자 메시지(목적), 마지막 사용자/assistant, `gitBranch`, `pr-link`를 뽑는다.
`isMeta`, tool_result, `/extra-usage` 같은 잡음은 버린다. 실제 사용자 턴이 없으면 세션 자체를 생략한다.

| 상태 | 언제 |
|---|---|
| 진행중 | `~/.claude/sessions/*.json`의 pid가 살아 있음 |
| 완료 | 사용자가 적용/푸시 했다고 했거나, 마지막 답에 완료 표시이고 질문이 없거나, 2턴 이상이고 후속 질문이 없음 |
| 미완 | 마지막 답이 질문으로 끝남 |
| 부분 | 작업은 있었고 다음 조치 제안만 남음. 또는 한 턴으로 끝남 |

휴리스틱이다. 100%가 아니다. 근거를 한 줄 붙인다.

## 빈 결과로는 덮어쓰지 않는다 (2026-09-22 수정)

새 탭이 열릴 때 `local/claude-sessions.md`가 `기록된 세션이 없다.` 한 줄로 초기화되는 버그가 있었다.

원인은 두 가지가 겹친 것이다.

1. 세션 목록을 `transcript_path`의 부모 디렉터리 **한 곳**에서만 모았다. 그 경로가 slug 디렉터리와
   다르면(새 탭·리줌·워크트리) 목록이 비어 버린다.
2. 목록이 비어도 그대로 렌더해서 파일을 덮어썼다. jsonl을 읽지 못한 경우(권한·샌드박스)도 마찬가지였다.

지금은 이렇게 동작한다.

- `transcript_path`의 부모와 cwd slug 디렉터리를 **둘 다** 훑어 세션 id로 합친다.
- 세션이 하나도 없거나 읽기 실패가 성공보다 많은 회차는 **신뢰할 수 없는 회차**로 보고 기존 파일을
  그대로 둔다. stderr에 `keep existing recap (sessions=… scanned=… unreadable=…)`를 남긴다.
- 파일이 아직 없을 때만 빈 결과라도 새로 만든다.

즉 **정보를 줄이는 방향으로는 덮어쓰지 않는다.** 훅이 실패해도 마지막으로 성공한 기록이 남는다.

## 알려진 함정

- **cwd가 프로젝트 루트가 아니면 갱신되지 않는다.** jsonl은 git 루트의 slug 아래에 있다. 훅이 하위
  디렉터리 cwd로 돌면 목록이 비는데, 이제는 파일을 지우지 않고 그냥 건너뛴다. 재생성은 레포 루트에서.
- **완료 판정은 마지막 문장에 의존한다.** 버전 정리처럼 실질은 끝났는데 마지막이 "푸시 명령이 뭐지?"면 예전엔 부분으로 남았다. 지금은 후속 질문 없이 끝나면 완료로 본다.
- **Cursor 에이전트 대화는 이 목록에 안 들어간다.** Claude Code jsonl만 본다.
- **`$HOME`은 statusline과 같은 방식이다.** `ask_mode.md`는 틸드를 신뢰하지 말라고 한다. 여기 command는 `$HOME`을 쓴다. 훅이 셸을 타지 않으면 깨지므로 그때는 절대 경로로 바꾼다.

## 완료 기준

- 새 Claude Code 탭에서 한 턴 답하면 `local/claude-sessions.md`가 빈 줄 없이 갱신된다.
- 탭을 그냥 닫아도 그 상태가 남는다.
- 다음 탭 SessionStart가 미완만 컨텍스트에 넣고, 사용자가 묻기 전에는 나열하지 않는다.
- `/sessions`는 같은 파일을 다시 그려 보여 준다.
- 기존 `settings.json`의 다른 훅(ask-guard 등)이 유지된다.
