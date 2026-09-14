# dev-smoke 과제로 day/night 비교

## 목적과 현재 상태

과제는 [dev-smoke.test.md](dev-smoke.test.md)이며, 사용자가 첫 비교 범위를 **로컬 모의 API로 구현·검증**으로 선택했다. 실행 엔진은 설치된 Claude Code CLI다.

**비교 실행과 독립 채점을 완료했다. 최종 자동 점수는 day 80/100, night 90/100이며, 필수 gate는 두 팀 모두 FAIL이다.** [최종 결과와 결함](dev-smoke.eval.result.md)에 실행 증거·평가기 수정 이력·해석을 기록했다.

독립 채점기 v2의 자체 테스트는 6개 모두 통과했다. 가짜 통과 리포트 거부, 미구현 시작 코드 0점, 리포트 형식 오류의 다른 항목 중복 감점 방지를 확인했다. 두 후보를 v2로 각각 두 번 채점해 점수·항목별 합불·gate의 동일성도 확인했다.

실험 경로: `/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912`

## 이번 과제의 범위

- 설정 검증, 인증, HTTP 기록·마스킹, 테스트 사용자 생성, 조회 4개, 쓰기 2개, JSON/Markdown 리포트, 자체 테스트, 타입 검사.
- 조회용 사용자 1명과 쓰기별 사용자 2명을 분리하고 매 실행마다 새로 생성한다. 삭제 API는 만들지 않는다.
- 모의 URL·인증·엔드포인트 계약은 실험용 입력으로 명시한다. 실제 dev의 미정값을 대체하지 않는다.
- 실제 dev·Slack 전송·배포 dispatch·LLM 탐색은 구현/연동 여부와 미검증 사유를 따로 남긴다. 이번 비교에서 실제 호출하지 않는다.
- CI는 로컬 테스트/typecheck용 workflow를 작성한다. 실제 원격 CI 실행은 이번 검증과 구분한다.

정확한 CLI·환경변수·응답·리포트 인터페이스는 실험 폴더의 `shared/BENCHMARK.md`에 동결되어 있다. 두 팀에 동일한 사본을 제공했다.

## 비교 조건

| 항목 | 조건 |
|---|---|
| 시작 코드 | 동일 커밋의 로컬 clone 2개, remote 없음 |
| 의존성 | 동일 lockfile, 팀별 node_modules 사본 |
| 오케스트레이터 | 양쪽 `sonnet`, effort `low`; 실제 해석된 모델은 실행 로그에 기록 |
| 역할별 모델 | 기존 day/night 설정 유지; `inherit`는 실행 시 부모 모델 상속 |
| 과정 | 실제 Claude scout → builder → reviewer, 원본의 호출 상한 5회 유지 |
| 실행 횟수 | 팀별 1회; 한 번의 결과로 일반적인 우열을 결론 내리지 않음 |
| 외부 평가 | 팀과 분리된 평가자가 자체 mock으로 CLI 재실행 |
| 원격 반영 | push·PR·배포 없음 |

원본 팀 폴더는 수정하지 않는다. 실험용 복사본에서는 night-reviewer의 merge conflict를 night 쪽 내용으로 정리하고, `NEEDS_HUMAN`의 판단 기준·반환 형식을 기존 안전 경계와 연결했다. 에이전트 파일은 검색 가능한 평면 디렉터리에 배치하고 `Sonnet` 별칭을 `sonnet`으로 정규화했다. 원본 해시와 변경 내역은 `manifest.json`, 원본 사본은 `snapshot/`에 남겼다.

이는 원본 설정 그대로의 재현이 아니라 **기록된 최소 수정이 있는 팀 구성 비교**다.

## 채점

[score.md](score.md)의 결정성·독립 판정·측정 실패 분리 원칙을 적용한다. strict 전환 과제가 아니므로 `introducedErrors`나 AST 문법 개수를 기능 점수로 사용하지 않는다.

`harness/rubric.json`은 후보 구현을 보기 전에 동결했다. 20개 기능 그룹 × 5점, 총 100점이다. 각 그룹은 여러 시나리오를 포함할 수 있으며 전부 통과해야 해당 점수를 받는다. 최초 채점 후 리포트 형식 오류가 다른 그룹을 연쇄 감점시키는 평가기 결함을 수정했다. 기준과 가중치는 유지하고, 원본 v1·최초 점수와 수정본 v2·최종 점수를 모두 보존했다.

- 정상 실행, 리포트 형식, 모든 HTTP 시도 기록, Markdown 원문
- 사용자 격리, 반복 실행의 사용자·runId 고유성
- 필수 설정 누락, 잘못된 설정, origin·인증 경로·redirect 차단
- 비밀번호·토큰·쿠키 및 중첩/문자열 데이터의 마스킹
- HTTP 오류, 응답 필드 누락/타입 오류, 비정상 JSON, timeout
- 빈 배열·0 값의 이상 징후, 미커버/스킵 보고, 비멱등 POST 재시도 금지

origin·경로·redirect·마스킹·사용자 격리는 별도의 필수 gate다. 높은 부분 점수가 gate 실패를 상쇄하지 않는다. 코드에 실행되지 않는 삭제 기능이 숨어 있는지, 자체 테스트가 실제 동작을 검증하는지는 추가 소스 리뷰로 확인한다.

`APPROVE`는 팀의 주장이다. 외부 채점 결과, 자체 테스트 재실행, typecheck 결과와 대조한다. 실제 dev 동작 보존이나 전체 원 명세의 완료를 주장하지 않는다.

시간·모델별 토큰·재작업 횟수·사람 개입·HANDOFF는 기능 점수와 별도로 보고한다. CLI의 비용 수치는 실제 청구액과 구분한다. 적절한 HANDOFF와 구현 실패, 환경 실패도 구분한다.

## 실행과 산출물

실험 폴더에서:

```sh
node harness/grade-v2.mjs ./day ./results/day-new
node harness/grade-v2.mjs ./night ./results/night-new
```

`run_teams.py`는 실제 두 팀 실행에 사용한 실행기다. 신뢰 승인이 없거나 후보가 이미 시작 커밋에서 변경되었으면 모델을 호출하기 전에 종료한다. 팀 실행을 재현하려면 `base`에서 새 clone을 준비한다. 완료된 후보는 위 채점 명령으로 재검증할 수 있다. 이전 실행 로그는 보존하며 평가에는 새 출력 디렉터리를 사용한다.

- `manifest.json`: 기준 커밋, 입력 해시, 설정 수정 및 준비 작업 내역
- `commands.json`, `logs/`: 실제 Claude 명령, 프롬프트, 이벤트, 실패 사유
- `day/`, `night/`: 구현과 팀별 handoff
- `harness/`: 모의 서버, 독립 채점기, 자체 검증
- `results/`: 외부 채점과 시나리오별 리포트

준비 중 최초 npm 설치가 의도한 실험 폴더 대신 `/Users/swkim`을 package prefix로 사용했다. 추가한 직접 개발 의존성 4개는 제거했고 이후 모든 설치는 실험용 package 디렉터리에서 수행했다. 홈의 package-lock과 전이 의존성은 설치 전 사본이 없어 원래 바이트/버전까지 복구했다고 주장하지 않는다. 해당 경위는 `manifest.json`에도 기록했다.

## 초기 환경 문제와 해결 이력

최초 실행은 새 폴더의 신뢰 승인이 없어 중단했다. 이후 사용자가 두 폴더를 대화형 Claude에서 신뢰 승인했고, 실행기가 이를 읽기 전용으로 확인한 뒤 재개했다. 현재 추가 승인이 필요한 상태가 아니다. 당시 승인에 사용한 명령은 다음과 같다.

```sh
cd /Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/day && claude
cd /Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/night && claude
```

최초 거부된 동작은 day의 `git switch -c feat/dev-smoke-local-mvp`, night의 `Skill(night-team)`과 브랜치 생성이었다. Claude가 보고한 이유는 승인 창이 없는 비대화형 세션에서 승인 필요 동작이 요청되었다는 것이다. 이 초기 환경 실패는 팀 점수에 넣지 않았다. 재개 후 발생한 개별 도구 거부와 검증 대체 경로는 실행 로그·팀 리뷰에 남아 있다.
