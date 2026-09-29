---
name: gymboxx-lib-version
description: gymboxx-lib 의 현재 버전 현황(main 정식·dev 라인·npm·app-server 핀·VERSIONS.md 괴리)을 실측으로 파악하고, 내 작업을 어떤 번호·어떤 기반 커밋으로 발행할지 추천한다. 태그는 만들지 않는다. Use when the user says lib 버전, gymboxx-lib 배포, lib 발행, 몇 버전으로 내야 해, dev 태그 뭐로, 다음 버전 번호, VERSIONS.md 갱신, 또는 gymboxx-lib 에 태그를 푸시하려 할 때.
---

# gymboxx-lib 버전 결정

목적은 **판단 자료와 추천**이다. 태그 생성·푸시·브랜치 생성은 하지 않고 명령만 제시한다.
작업자가 여럿이라 상태가 몇 시간 만에 바뀐다. 기억이나 VERSIONS.md 를 믿지 말고 매번 스크립트로 잰다.

## 워크플로

### 1. 현황 측정

```bash
bash ~/.claude/skills/gymboxx-lib-version/scripts/status.sh <스크래치패드>/lib-status.md
```

- 30초 안팎 걸린다. 리포트 파일을 읽는다. `git fetch` 외에는 아무것도 바꾸지 않는다.
- 경로를 바꾸려면 `LIB_DIR`, `APP_DIR` 환경변수를 쓴다.
- `⚠️ npm 조회 실패`가 나오면 점유 번호에서 npm 이 빠진 것이다. 추천 전에 사용자에게 알린다.

### 2. 작업 확인

추천하려면 두 가지가 필요하다. 대화나 리포트 7절(로컬 작업 브랜치)로 알 수 없으면 묻는다.
- **채널**: main 정식인지, app-server develop 테스트용 dev 인지
- **실을 커밋**: 어느 브랜치의 어떤 커밋인지. 7절의 "dev 팁에 없는 커밋"이 후보다.

### 3. 추천

아래 규칙으로 번호, 기반 커밋, 명령 순서를 정한다.

### 4. VERSIONS.md 갱신안

리포트 6절의 괴리와 이번 추천 번호를 반영한 행 수정안을 보여준다. 직접 고치지 않는다.
브랜치 의도, 담당자, 보류 커밋 같은 사람이 쓴 메모 열과 절은 그대로 둔다.
사본이 브랜치마다 다르다. 6절이 어느 사본을 읽었는지 밝히므로, 갱신안을 어느 브랜치에 올릴지도 함께 적는다.

## 버전 규칙

### 점유 번호
태그, npm 발행 버전, 원격 브랜치 package.json, VERSIONS.md 표를 합친 것이다(리포트 5절).
이 안의 번호는 쓰지 않는다. 같은 번호를 두 곳이 태그로 푸시하면 나중 쪽이 npm 409 를 받는다.

### main 정식 `X.Y.Z`
- base=main PR 이 머지된 뒤 main 에서 태그를 단다. 피처 브랜치 이름은 `feature/*` 이다.
- 엔티티, 컬럼, enum, SQL 을 추가하면 minor, 수정만 있으면 patch 다. 필드 삭제나 이름 변경 같은
  파괴적 변경은 major 인지 사용자에게 묻는다(4.39.0 은 `FoodOptionGroup.options` 를 지우고도 minor 로 나갔다).
- minor 가 dev 라인이 쓰는 `X.Y.0` 과 같으면, 발행 후 dev 라인은 `X.(Y+1).0-dev.0` 으로 넘어간다고 알린다.

### dev `<main 다음 minor>.0-dev.N`
- dev 라인은 **한 줄**이다. app-server develop 은 환경이 하나라 갈래를 나누면 누군가의 컬럼이 빠진다.
- 기반은 **라인 팁 태그**다. develop 핀이 팁보다 뒤처져 있어도 팁 위에 쌓는다. 대신 리포트 4절의
  "함께 들어오는 커밋"을 보여준다. develop 을 올리면 남의 변경도 들어가기 때문이다.
- 리포트 3절에 main 커밋이 있으면 `origin/main` 을 머지한다. 이 브랜치는 main 으로 가지 않으니
  섞여도 새지 않는다. 충돌이 나면 풀지 말고 파일 목록을 사용자에게 넘긴다.
- 내 커밋은 cherry-pick 한다. main PR 용 `feature/<작업>`(base=main)은 따로 둔다.
- 번호는 라인의 점유된 최대 N+1 이다(리포트 요약의 "다음 dev 번호").
- 라인 태그가 없으면 `origin/main` 위에서 `.0-dev.0` 으로 시작한다.

### 손대지 않는 것
- `package.json` 버전을 손으로 바꾸거나 `npm version` 을 실행하지 않는다. publish workflow 가 태그 이름으로 bump 하고 커밋을 푸시한다.
- 이미 발행된 번호로 붙여 둔 SQL 파일명(`src/sqlv4`)은 바꾸지 않는다.

## 푸시 전 함정

1. **husky pre-push**: 태그를 푸시할 때 **로컬** 브랜치가 `main`/`feature/*` 가 아니면 막힌다. 이 훅은
   `core.hooksPath=.husky` 인 클론에서만 돈다(내 클론은 켜져 있고, `dev-only/*` 에서 태그를 푸시한 작업자는 꺼져 있는 것으로 보인다). 그래서 dev 브랜치도
   로컬 이름은 `feature/dev-<작업>` 으로 만들고, 원격에는 `dev-only/<작업>` 으로 푸시한다.
2. **버전 커밋이 엉뚱한 브랜치로 간다**: `publish.yaml` 은 태그 커밋을 포함하는 원격 브랜치 가운데
   **알파벳 순 첫 번째**에 bump 커밋을 푸시한다. 태그 달 커밋에 대해 `git branch -r --contains <sha>` 를 돌려
   의도한 브랜치가 첫 줄인지 확인하라고 안내한다. main 태그라면 main 팁에서 딴 `chore/*`, `fix/*` 같은
   브랜치가 main 보다 앞설 수 있다.

## 명령 템플릿

dev:
```bash
git fetch origin --tags
git switch -c feature/dev-<작업> <dev 팁 태그>
git merge origin/main                     # 리포트 3절에 커밋이 있을 때만
git cherry-pick <커밋...>
git push origin feature/dev-<작업>:dev-only/<작업>
git branch -r --contains HEAD             # origin/dev-only/<작업> 하나만 나와야 한다
git tag <다음 dev 번호> && git push origin <다음 dev 번호>
```
이어서 app-server develop 의 `@suppliesfitness/gymboxx-lib` 핀을 그 번호로 올린다.

main (PR 머지 후):
```bash
git switch main && git pull
git branch -r --contains HEAD             # 첫 줄이 origin/main 인지 확인
git tag <다음 번호> && git push origin <다음 번호>
```

## 출력 형식

짧게 쓴다.
1. 현황 3~5줄: main 최신, dev 팁, develop 핀, main 누락분 유무
2. 추천 한 줄: `dev <번호> — <기반> 위에 <커밋 n개>` 또는 `main <번호> (minor|patch) — <이유 한 구절>`
3. 명령 블럭: 위 템플릿을 실제 값으로 채운 것
4. 경고: 함께 들어오는 남의 커밋, 머지 충돌 가능성, 함정 점검 결과
5. VERSIONS.md 갱신안: 바뀌는 행만
