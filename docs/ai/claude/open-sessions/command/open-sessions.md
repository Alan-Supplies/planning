---
description: 지금 열려 있는 Claude Code 탭의 진행 상태와 닫기 안전도
allowed-tools: Bash(python3 *)
argument-hint: "[--all] [--no-net]"
---

아래는 지금 살아 있는 탭을 훑은 결과다. 훅이 아니라 즉석 조회다.

!`python3 "$HOME/.claude/skills/open-sessions/scripts/open_sessions.py" $ARGUMENTS`

이 내용을 **요약하지 말고 그대로** 보여줘. 그룹과 순서가 판정 결과다.
맨 위에 한 줄만 덧붙여라 — `지금 닫지 마라` 그룹이 있으면 그것부터 짚는다.
파일을 고치거나 탭을 대신 닫지 마라. 판단 재료만 준다.

판정 기준·한계는 `~/.claude/skills/open-sessions/SKILL.md` 에 있다.
