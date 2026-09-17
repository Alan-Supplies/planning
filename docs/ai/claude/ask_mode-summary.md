# ask 모드 — 쉽게 보는 버전

> 원문: [`ask_mode.md`](./ask_mode.md) — 구현 근거·실측 로그·설계 판단이 전부 들어 있다.
> 이 문서는 **쓰는 법과 주의점만** 추린 것이다. 고칠 일이 생기면 원문을 본다.

## 한 줄 요약

Claude Code 에서 **파일을 못 고치게 잠그는 토글**이다. Cursor 의 Ask 에 해당한다.
대화 맥락은 그대로 유지되므로, 질문하다가 바로 작업으로 넘어갈 수 있다.

## 쓰는 법

```text
/ask     ← 켜기 (한 번 더 누르면 끄기)
```

켜져 있으면 statusline 맨 앞에 노란 `ASK` 배지가 보인다.

켜는 순간 Claude 도 같이 안다. 편집을 시도했다 막히는 왕복 없이 바로 설명으로 답한다
(`/ask` 커맨드 본문이 그렇게 지시한다).

터미널에서도 된다. 세션 밖에서 미리 걸어두거나, 막혔을 때 푸는 용도다.

```sh
ask      # 켜기
unask    # 끄기
```

## 켜져 있을 때 무엇이 막히나

| | |
| --- | --- |
| **막힘** | 파일 편집(Edit/Write/NotebookEdit) · 쓰기성 쉘 명령(`rm` `mv` `cp` `touch` `mkdir` `tee` `sed -i` `>` 리다이렉트) · `git commit` 같은 작업 트리 변경 · `npm install` · `npx` · `python3 -c` |
| **통과** | `ls` `cat` `grep` `find` `jq` · `git log` `git status` `git diff` · `mysql -e "select ..."` · `echo` · `$TMPDIR` 로의 리다이렉트 |

막히면 Claude 는 파일을 고치는 대신 **"무엇을 어떻게 바꿔야 하는지" 말로만** 설명한다.

## 막혔는데 안 풀릴 때

터미널에서 `unask`. 훅을 타지 않으므로 어떤 상황에서도 풀린다.

`/ask` 로 끄는 것도 정상 동작한다 — 슬래시 커맨드는 가드를 타지 않는다(2026-09-18 실측).

## 알아둘 것 네 가지

1. **센티널은 저장소가 아니라 세션 cwd 기준이다.**
   `docs/git` 에서 Claude 를 띄웠다면 `docs/git/.claude/.ask` 가 만들어진다.
   저장소 루트에 만들면 안 걸린다.

2. **로컬 파일만 읽기 전용이다.** Notion·Linear·Slack 같은 MCP 쓰기 툴은 ask 모드에서도 동작한다.
   "전방위 읽기 전용"이 아니다.

3. **Cursor 는 영향받지 않는다.** Cursor 가 `~/.claude/settings.json` 을 읽어가는 탓에 한때 같이
   걸렸지만, 지금은 가드에서 제외했다.

4. **오탐이 있다.** 따옴표 없는 인자에 `cp`·`rm` 같은 단어가 들어가면(`grep -rn cp .`) 막힌다.
   따옴표를 씌우면 통과한다. ask 모드에서는 애매하면 막는 쪽으로 설계했다 —
   잘못 막혀도 설명으로 넘어갈 뿐이지만, 안 막히면 기능 자체가 무의미해지기 때문이다.

## 구성 요소

고칠 일이 생겼을 때 어디를 보면 되는지만.

| 무엇 | 어디 |
| --- | --- |
| 실제 차단 로직 | `~/.claude/hooks/ask-guard.sh` |
| 훅 등록 | `~/.claude/settings.json` 의 `hooks.PreToolUse` |
| 현재 모드 상태 | `<세션 cwd>/.claude/.ask` (있으면 ON) |
| `/ask` 커맨드 | `~/.claude/commands/ask.md` |
| 배지 표시 | `~/.claude/statusline-command.sh` |
| `ask`/`unask` alias | `~/.zshrc` |

## 안 될 때 확인하는 법

```sh
touch /tmp/ask-guard.debug   # 로그 켜기
tail -f /tmp/ask-guard.log   # deny / pass 가 찍힌다
rm /tmp/ask-guard.debug      # 끄기 (반드시)
```

로그는 **이 훅을 실행하는 모든 도구·세션이 함께 쓴다.** 다른 저장소의 Cursor 세션 기록까지 섞이니,
`cwd` 로 걸러서 봐야 한다. 켜둔 채 두면 명령 전문이 계속 쌓이므로 확인이 끝나면 끈다.
