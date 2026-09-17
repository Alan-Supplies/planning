# ask 모드 설치 가이드 (다른 머신)

> ask 모드가 뭔지, 어떻게 쓰는지는 [`../ask_mode-summary.md`](../ask_mode-summary.md) 를 본다.
> 이 문서는 **새 머신에 까는 방법**만 다룬다. 구현 근거는 [`../ask_mode.md`](../ask_mode.md).

## 설치 방식

이 디렉토리의 파일을 `~/.claude` 로 **심볼릭 링크**한다. 복사하지 않는다.

실물이 저장소 한 곳에만 있으므로 `git pull` 하면 모든 머신에 반영되고, 문서와 실제 파일이
어긋나는 일이 없다. 실제로 훅은 운영 중에 두 번 바뀌었다 (Cursor 제외, 디버그 로그).

## 사전 조건 두 가지

- **이 저장소가 클론돼 있을 것** — `git@github.com:Alan-Supplies/planning.git`
- **`jq` 가 설치돼 있을 것** — 훅이 입력 JSON 파싱에 쓴다.

`jq` 는 특히 중요하다. 없으면 **에러 없이 조용히 무력화된다** — `cwd` 가 빈 문자열이 되어
센티널을 못 찾고, 훅은 그냥 통과시킨다. 막힌 줄 알고 편집하다 사고 난다.

```sh
jq --version || brew install jq
```

## 설치

```sh
cd ~/workspace/supplies/planning && git pull
bash docs/ai/claude/ask-mode/install.sh
```

스크립트가 하는 일:

| 단계 | 내용 |
| --- | --- |
| 1 | `ask-guard.sh` · `ask.md` · `statusline-command.sh` 를 `~/.claude` 로 링크 (기존 실물 파일은 `.bak.<타임스탬프>` 로 백업) |
| 2 | `~/.zshrc` 에 `ask`/`unask` alias 추가 (이미 있으면 건너뜀, 백업 생성) |
| 3 | `settings.json` 에 넣을 내용을 **출력만** 한다 |
| 4 | `.gitignore` 확인 안내 |

**`settings.json` 은 스크립트가 건드리지 않는다.** 기존 훅(`Stop`·`SessionStart` 등)을 망칠
위험이 있어 자동 병합하지 않는다. 아래를 직접 넣는다.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash '/Users/<사용자>/.claude/hooks/ask-guard.sh'",
            "timeout": 10
          }
        ]
      }
    ],
    "statusLine": {
      "type": "command",
      "command": "bash '/Users/<사용자>/.claude/statusline-command.sh'"
    }
  }
}
```

- 이미 `hooks` 키가 있으면 **`PreToolUse` 항목만 끼워넣는다.** 통째로 덮으면 다른 훅이 죽는다.
- **틸드(`~`)는 확장되지 않는다.** 절대 경로로 쓴다.
- `statusLine` 은 `hooks` 밖 최상위 키다. 위 예시는 편의상 같이 적었다.

넣은 뒤 JSON 이 깨지지 않았는지 확인한다.

```sh
jq . ~/.claude/settings.json >/dev/null && echo "JSON OK"
```

마지막으로 저장소 `.gitignore` 에 센티널 제외가 있는지 본다 (이 저장소에는 이미 있다).

```text
**/.claude/.ask
```

`**/` 가 필요하다. `.claude/.ask` 만 쓰면 저장소 루트만 잡히고, 하위 디렉토리에서 Claude 를
띄웠을 때 생기는 센티널은 안 잡힌다.

## 성공 기준

**훅 설정은 세션 시작 시 고정되므로 새 세션에서 확인한다.**

1. 링크가 걸렸는가
   ```sh
   ls -l ~/.claude/hooks/ask-guard.sh   # → .../planning/docs/ai/claude/ask-mode/ask-guard.sh
   ```
2. 새 Claude Code 세션에서 `/ask` 를 누르면
   - `ask 모드 ON — 질문만 가능` 출력과 함께 **지시문이 따라 나온다**
   - statusline 맨 앞에 노란 `ASK` 배지가 뜬다
3. 그 상태에서 파일 수정을 시켜보면 — 편집을 시도하지 않고 설명으로 답한다
4. `/ask` 를 다시 누르면 배지가 사라지고 수정이 된다

3번이 안 되면 (편집이 그냥 되면) `jq` 설치 여부와 `settings.json` 의 훅 경로부터 본다.

## 롤백

```sh
bash docs/ai/claude/ask-mode/install.sh --uninstall
```

링크만 지운다. 백업해 둔 원래 파일(`*.bak.*`)은 직접 되돌린다. `.zshrc` 의 alias 와
`settings.json` 의 훅 등록도 직접 지운다 — 스크립트가 넣은 것을 되돌리는 건 위험해서 하지 않는다.

## 자주 막히는 곳

- **`jq` 미설치** → 조용히 무력화. 위 사전 조건 참고.
- **틸드 경로** → `settings.json` 에서 `~` 는 확장되지 않는다. 절대 경로로 쓴다.
- **실행 비트** → `command` 를 `bash '<경로>'` 형태로 호출하므로 실행 권한이 없어도 동작한다.
  직접 `'<경로>'` 로만 쓰면 권한 없을 때 **경고만 뜨고 그냥 통과**하니 형식을 바꾸지 않는다.
- **센티널 위치** → 저장소 루트가 아니라 **세션 cwd** 기준이다. `docs/git` 에서 띄웠으면
  `docs/git/.claude/.ask` 다.
- **Cursor** → 회사컴에도 Cursor 가 있으면 `~/.claude/settings.json` 훅을 같이 읽어간다
  (Third-Party Imports, 기본 켜짐). 훅에 제외 처리가 들어 있어 영향은 없다. 자세한 건 원문 참고.

## 이 디렉토리의 파일

| 파일 | 설치 위치 |
| --- | --- |
| `ask-guard.sh` | `~/.claude/hooks/ask-guard.sh` |
| `ask.md` | `~/.claude/commands/ask.md` |
| `statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `install.sh` | (설치 스크립트 자체) |
| `INSTALL.md` | (이 문서) |

`statusline-command.sh` 는 ask 모드 전용이 아니라 **모델·경로·브랜치·사용량까지 표시하는 전체
statusline** 이다. 링크하면 그 머신의 기존 statusline 을 대체한다(백업은 남는다).
