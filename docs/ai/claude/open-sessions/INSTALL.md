# /open-sessions 설치 가이드 (다른 머신)

> 이 도구가 **무엇을 어떻게 판정하는지**는 [`skill/SKILL.md`](skill/SKILL.md) 에 있다.
> 이 문서는 **새 머신에 까는 방법**만 다룬다.

지금 열려 있는 Claude Code 탭이 각각 어디까지 진행됐고 닫아도 되는지 보여준다.
과거 세션 전체 이력을 보는 `/sessions`([`../session-manage/`](../session-manage/)) 와는 다르다 —
이쪽은 **살아 있는 탭만** 본다.

## 설치 방식

이 디렉토리의 파일을 `~/.claude` 로 **심볼릭 링크**한다. 복사하지 않는다.

실물이 저장소 한 곳에만 있으므로 `git pull` 하면 모든 머신에 반영되고, 문서와 실제 파일이
어긋나는 일이 없다. `ask-mode` 와 같은 규약이다.

## 사전 조건

- **이 저장소가 클론돼 있을 것** — `git@github.com:Alan-Supplies/planning.git`
- **`python3` 3.7 이상** — 표준 라이브러리만 쓴다. 별도 패키지 설치가 없다.
  (3.7 은 `from __future__ import annotations` 때문에 필요하다. macOS 기본 python3 로 충분하다.)
- **`gh` (선택)** — PR 상태를 보려면 필요하다. 없으면 PR 칸만 비고 나머지는 그대로 동작한다.

`gh` 는 `PATH` 에 없어도 `/opt/homebrew/bin/gh` · `/usr/local/bin/gh` 를 찾아본다.
그래도 없으면 조용히 건너뛴다 — 설치가 실패하지는 않는다.

## 설치

```sh
cd ~/workspace/supplies/planning && git pull
bash docs/ai/claude/open-sessions/install.sh
```

스크립트가 하는 일:

| 단계 | 내용 |
| --- | --- |
| 1 | `python3` 확인, `gh` 유무 보고 |
| 2 | `skill/` 을 `~/.claude/skills/open-sessions` 로, `command/open-sessions.md` 를 `~/.claude/commands/` 로 링크 (기존 실물은 `.bak.<타임스탬프>` 로 백업) |
| 3 | 스크립트를 실제로 한 번 돌려 동작 확인 |

`settings.json` 은 건드리지 않는다. 이 도구는 훅을 쓰지 않아 등록할 것이 없다.

## 설치 후 — 바로 안 뜬다

Claude Code 는 **스킬·명령 목록을 세션 시작 때 읽는다.** 깐 직후 기존 탭에서는 안 보이고,
새 탭을 열어도 확장이 다시 스캔하기 전이면 안 보인다.

- VSCode: `Cmd+Shift+P` → `Developer: Reload Window`
- CLI: `claude` 를 새로 띄운다

그 다음 `/open-sessions` 로 확인한다. 리로드가 귀찮으면 스크립트를 직접 불러도 결과는 같다.

```sh
python3 ~/.claude/skills/open-sessions/scripts/open_sessions.py
```

## 왜 둘(skill + command)로 까는가

| 경로 | 역할 |
| --- | --- |
| `~/.claude/skills/open-sessions/` | 스킬 — "이 탭 닫아도 돼?" 같은 말에 모델이 알아서 꺼내 쓴다 |
| `~/.claude/commands/open-sessions.md` | 슬래시 명령 — `/open-sessions [--all] [--no-net]` 로 직접 부른다 |

둘은 **같은 스크립트를 부르므로 결과가 같다.** 굳이 나눈 이유는 환경마다 스킬 스캔이 늦게
붙는 경우가 있어서다. 명령 쪽은 `commands/` 만 읽으면 되므로 더 확실하게 뜬다.
하나만 원하면 `install.sh` 의 `TARGETS` 에서 해당 줄을 지운다.

## 쓰는 법

```sh
/open-sessions              # 현재 폴더의 열린 탭 (~1초)
/open-sessions --all        # 모든 프로젝트 (탭 20개 기준 3~4초)
/open-sessions --no-net     # git/gh 생략, 즉시
```

`--cwd <경로>` 로 다른 폴더를, `--json` 으로 판정 전 원자료를 낼 수 있다.

## 롤백

```sh
bash docs/ai/claude/open-sessions/install.sh --uninstall
```

링크만 지운다. 저장소 파일과 `.bak.*` 백업은 그대로 두니 필요 없으면 직접 정리한다.

## 이 도구가 읽는 것 — 옮길 때 알아둘 것

| 경로 | 쓰임 |
| --- | --- |
| `~/.claude/sessions/*.json` | 살아 있는 탭 목록 (pid·cwd·이름·busy/waiting/idle) |
| `~/.claude/projects/<slug>/<sessionId>.jsonl` | 각 탭의 대화 기록 — 진행 상태 판정의 근거 |

**머신마다 기록이 따로 논다.** 저장소를 공유해도 세션 기록은 따라오지 않으니, 다른 머신에
깔면 그 머신에서 연 탭만 보인다. 읽기 전용이라 아무것도 고치거나 종료하지 않는다.
