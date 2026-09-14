# dev-smoke day/night 비교 결과 — 2026-09-12

**자동 채점 최종 결과는 day 80/100, night 90/100이다. 두 팀 모두 마스킹 결함으로 필수 gate가 FAIL이다.** Claude 팀 실행부터 독립 검증까지 완료했으며, 실제 dev 배포에 사용할 준비가 끝났다는 뜻은 아니다.

## 실행 결과

| 항목 | day | night |
|---|---|---|
| 최종 자동 기능 점수(v2) | 80/100 | 90/100 |
| 통과 항목 | 16/20 | 18/20 |
| 필수 gate | FAIL: path_guard, redaction | FAIL: redaction |
| 팀 자체 리뷰 | APPROVE | APPROVE |
| 평가자가 재실행한 자체 테스트 | 29/29 통과 | 70/70 통과 |
| 평가자가 재실행한 typecheck | 통과 | 통과 |
| Claude 작업 시간 | 10분 39초 | 22분 56초 |
| 역할 호출 | scout → builder → reviewer, 3회 | night-scout → night-builder → night-reviewer, 3회 |
| 실제 로그의 모델 | claude-sonnet-5 | claude-sonnet-5, claude-opus-5[1m] |
| CLI 보고 비용(정가 환산 추정치) | $1.7721 | $5.2679 |
| README / 로컬 CI workflow | 없음 / 없음 | 있음 / 있음 |
| 후보 커밋 | `9c9b51fda5efc64a673dd9307c802691709bb5b3` | `a3a327d63de7c6e039f950fa316c78cdb9350d2b` |

시간은 채점기 소요 시간이 아닌 Claude 팀의 최종 실행 로그 기준이다. 비용은 CLI가 보고한 `costBasis: list` 값이며 실제 청구액으로 해석하지 않는다. 신뢰 승인 전 중단된 실행은 팀 성과에서 제외했다. 승인 후에도 자동 권한 거부 이벤트가 day 4건·night 18건 있었으므로 시간 차이를 모델 자체 속도로 해석할 수 없다. 두 팀은 동시에 실행했고 모델·추론 설정을 포함한 구성 전체를 비교했다.

## 자동 채점 방식과 보정 이력

점수는 사람이 부여하지 않았다. [dev-smoke-local-20260912의 grade-v2.mjs](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/harness/grade-v2.mjs)가 실제 `npm run smoke` 프로세스를 실행하고 독립 모의 서버가 관측한 HTTP·사용자·리포트를 검사한다. [rubric.json](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/harness/rubric.json)의 20개 항목에 각각 5점, 필수 gate는 별도로 적용한다.

1. 미구현 시작 코드가 무조건 non-zero 종료해도 일부 입력 검증 점수를 받던 문제를 발견했다. 원 명세대로 오류에 해당 설정 키가 포함되어야 통과하도록 수정했다. 보정 후 시작 코드는 0점이다.
2. 최초 후보 채점(v1)은 day 30, night 90이었다. day의 성공 결과에서 필수 `reason`이 빠진 것 하나가 다른 기능의 증거까지 무효화하여 연쇄 감점되는 평가기 결함이 있었다.
3. v2는 전체 리포트 형식 검사는 그대로 유지하고, 다른 항목은 해당 항목에 필요한 필드만 독립적으로 검증한다. **후보 코드를 바꾸거나 실패 피드백을 주지 않고 동일한 v2를 양쪽에 적용했다.** 점수는 day 80, night 90으로 산출됐다.
4. v1·v2 각각 전체 평가를 두 번 실행했고 점수·항목별 합불·gate가 동일했다. 시간, 포트, UUID, 원문 실행 메타가 같은지는 결정성 기준에 포함하지 않았다. v2 평가기 자체 테스트는 6개 모두 통과했다.

사후 평가기 수정이 있었으므로 최초 결과를 숨기지 않는다. [보정 이력과 해시](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/harness/calibration-history.json), [v1 day 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/day/grade.json), [v1 night 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/night/grade.json)를 보존했다. 이 비교의 주 결과는 v2이며, 향후 비교도 같은 버전으로 실행해야 한다.

## 재현한 실패

### 두 팀 공통: 마스킹과 미커버 보고

- **day — 알려진 비밀번호가 일반 문자열에 섞이면 노출된다.** 모의 `/items` 응답의 `responseBody.echo`에 넣은 설정 비밀번호가 JSON·Markdown에 그대로 남았다. `password` 키는 가리지만 해당 비밀번호를 리터럴 마스킹 집합에 등록하지 않아 생기는 문제다. [재현 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/day/diagnosis.json), [마스킹 구현](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/day/src/report/mask.ts:46).
- **night — 응답 본문 속 URL query secret이 노출된다.** 요청 URL은 마스킹하지만 응답 객체의 문자열 URL은 일반 문자열로 처리한다. `responseBody.url`의 `token` query 값이 JSON·Markdown에 남았다. [재현 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/night/diagnosis.json), [문자열 처리](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/night/src/report/mask.ts:51).
- **두 팀 모두 — 인증 준비 실패로 `/notes`를 호출하지 못했을 때 미커버 목록에서 누락된다.** 테스트 결과의 실패 표시는 있으나, 호출하지 않은 엔드포인트를 별도로 보고해야 한다는 계약을 충족하지 못했다. [day 증거](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/day-v2/auth_error.report.json), [night 증거](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/night-v2/auth_error.report.json).

시험에는 synthetic 비밀번호·토큰만 사용했다. 진단 파일에는 유출 위치와 종류만 저장했고, 채점 증거 파일의 시험용 비밀값은 유출 판정 후 마스킹했다. 실제 자격 증명 유출을 관측한 것은 아니다.

### day 추가 실패와 산출물 누락

- 성공한 6개 결과에 `reason`이 없다. [선언에서 optional로 처리](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/day/src/report/recorder.ts:23)해 고정 리포트 계약과 달라졌다. v2에서는 해당 형식 항목만 감점했다.
- `//host/path` 형태의 인증 경로를 허용했다. 실제 모의 서버에서 이를 정상 경로처럼 사용해 전체 12개 HTTP 요청을 수행했다. 계약은 `/` 한 개로 시작하는 상대 경로만 허용한다. [경로 검사](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/day/src/config.ts:39), [자동 검사 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/day-v2/grade.json).
- README와 `.github/workflows/`가 없다. 이는 CLI 기능 100점 항목 밖의 **별도 산출물 미완료**다. 점수에 사후 가중치를 추가하지 않았다. night는 둘 다 작성했으나 원격 CI를 실제 실행한 것은 아니다.

## 항목별 점수

| 자동 검사 | day | night |
|---|---:|---:|
| 정상 스위트 실행 | 5/5 | 5/5 |
| 필수 리포트 형식 | 0/5 | 5/5 |
| 전체 HTTP 시도·원문 기록 | 5/5 | 5/5 |
| Markdown 리포트 | 5/5 | 5/5 |
| 사용자 격리 | 5/5 | 5/5 |
| 재실행 고유성 | 5/5 | 5/5 |
| 필수 설정 누락 | 5/5 | 5/5 |
| 잘못된 설정 | 5/5 | 5/5 |
| origin 차단 | 5/5 | 5/5 |
| 인증 경로 차단 | 0/5 | 5/5 |
| redirect 차단 | 5/5 | 5/5 |
| 시크릿 마스킹 | 0/5 | 0/5 |
| HTTP 오류 | 5/5 | 5/5 |
| 응답 필드 누락 | 5/5 | 5/5 |
| 응답 타입 오류 | 5/5 | 5/5 |
| 비정상 JSON | 5/5 | 5/5 |
| timeout | 5/5 | 5/5 |
| 빈 배열·0 값 이상 징후 | 5/5 | 5/5 |
| 미커버·스킵 보고 | 0/5 | 0/5 |
| 비멱등 POST 재시도 금지 | 5/5 | 5/5 |

## 해석과 다음 행동

이 한 과제에서는 night가 더 많은 요구사항을 충족했지만 시간과 CLI 보고 비용도 더 컸다. 두 팀 모두 자체 테스트와 리뷰에서 통과한 코드가 외부 마스킹 시험에서 실패했으므로, 팀의 `APPROVE`만으로 완료 판정하면 안 된다.

두 구현은 비교용 상태 그대로 보존했다. 다음 구현 작업에서는 공통 마스킹·미커버 결함과 day의 리포트/경로/산출물 누락을 수정한 뒤 같은 v2로 다시 평가해야 한다. 실제 dev 인증, Slack, 배포 dispatch, LLM 탐색은 아직 미구현·미검증 범위다. 이 한 번의 관측을 일반적인 에이전트 우열로 확대하지 않는다.

## 파일과 재실행

- [통합 기계 판독 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/comparison.json)
- [최종 day 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/day-v2/grade.json), [최종 night 결과](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/results/night-v2/grade.json)
- [day 구현](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/day/src/cli.ts), [night 구현](/Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912/night/src/cli.ts)
- [실험 조건·권한·설정 변경 기록](dev-smoke.eval.md)

```sh
cd /Users/swkim/workspace/crazywook/ai-teams-eval/dev-smoke-local-20260912
node harness/grade-v2.mjs ./day ./results/day-new
node harness/grade-v2.mjs ./night ./results/night-new
```

출력 디렉터리는 새 이름을 사용한다. 팀 자체를 다시 비교하려면 `base`의 동일 커밋에서 새 clone을 만들어야 한다. 완료된 후보를 시작 코드로 재사용하지 않도록 실행기에 검사를 추가했다.
