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
