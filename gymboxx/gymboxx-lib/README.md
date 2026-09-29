# gymboxx-lib 버전 결정 스킬

gymboxx-lib 의 버전 현황을 실측하고, 내 작업을 어떤 번호와 기반 커밋으로 발행할지 추천하는 Claude Code 스킬이다.
작업자가 여럿이라 VERSIONS.md 가 금방 어긋나서 만들었다(2026-09-29). 태그는 만들지 않는다.

## 설치

```bash
bash ~/workspace/supplies/planing/gymboxx/gymboxx-lib/install.sh
```

- `~/.claude/skills/gymboxx-lib-version` 에 이 디렉터리의 `skill/gymboxx-lib-version` 을 링크한다. 이 레포를 pull 하면 스킬도 갱신된다.
- 필요한 것: gymboxx-lib·gymboxx-app-server 클론, GitHub Packages 를 읽을 수 있는 npm 토큰.
  클론 경로가 `~/workspace/supplies/` 아래가 아니면 `LIB_DIR`·`APP_DIR` 를 export 한다.
- Claude Code 에서 "lib 버전 뭘로 내야 해?" 라고 물어 호출되는지 확인한다.

## 규칙 요약

정본은 [SKILL.md](skill/gymboxx-lib-version/SKILL.md) 다.
- main 정식은 PR 머지 후 main 에서 `X.Y.Z` 로 낸다. 추가 변경은 minor, 수정은 patch 다.
- dev 는 한 줄로 이어지는 `<main 다음 minor>.0-dev.N` 라인의 팁 위에 쌓는다. main 누락분이 있으면 머지하고, 내 커밋은 cherry-pick 한다.
- 태그, npm, 브랜치 package.json, VERSIONS.md 에 이미 있는 번호는 쓰지 않는다.
