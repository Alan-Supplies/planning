# gymboxx-lib migration CI/CD 진척 조사 (2026-10-12)

## 판단

Linear [프로젝트](https://linear.app/suppliesfitness/project/gymboxx-lib-migration-cicd-c38e3f85a59a)의 최신 마일스톤 표시값은 `28% / 8% / 8%`다. 새 이슈가 추가되면 비율이 내려가므로, 이 수치만으로 구현 진척을 판단하지 않는다. **#341은 모든 선행 엔티티 작업과 운영 DDL 확인을 마친 뒤 main으로 통합하는 마지막 단계**다. 현재 할 일로 앞당겨 세지 않는다.

### 한눈에 보는 진행 상태

| 분류 | 업무 흐름 | 판단 근거 | 다음 판정 시점 |
| --- | --- | --- | --- |
| **예상보다 잘 진행** | 6.0.0의 **dev 소비 검증** | 10/20 릴리스·소비처 전환 단계의 일부인 `6.0.0-dev.6` 발행과 app-server develop 병합·Jest 성공을 이미 확인했다. 정식 릴리스 완료를 뜻하지는 않는다 | 1단계 종료 뒤 정식 6.0.0 일정 확인 |
| **정상진행중** | **엔티티·DB 대조 도구** | [#355](https://github.com/suppliesfitness/gymboxx-lib/pull/355)의 `migration:check` 도구가 6.0.0 작업 브랜치에 병합됐고 [TECH-2640](https://linear.app/suppliesfitness/issue/TECH-2640/gymboxx-lib-ci-에-migrationcheck-를-넣는다)은 `in QA`다. PR에서 자동 실행하는 CI 연결은 남았다 | 10/21 baseline 결정과 비교용 DB 선택 확인 |
| **지연·정체 위험** | 10/14 **엔티티 운영 DB 정렬** | 코드·스택 PR은 많이 진행됐지만 운영 대비 diff 652문장이 새로 드러났다. 이를 정리할 12~15번 이슈 목표일은 **10/17**로, 마일스톤 목표일 10/14보다 늦다. 운영 DDL 확인도 대기 중이다 | 10/14 마일스톤 날짜 재계획 또는 범위 조정 |

현재 **지나간 기한은 없지만 10/14 계획과 10/17 하위 이슈 일정이 충돌한다.** 10/14에 1단계를 완료로 판정할 수 있는 범위를 다시 정하거나 마일스톤 날짜를 조정해야 한다. 10/23 baseline·CI 단계도 도구가 들어온 것과 CI 게이트가 켜진 것을 분리해 판정한다.

### baseline과 CI의 뜻

- **baseline:** 기존 운영 DB를 마이그레이션 관리의 출발점으로 인정하는 방식이다. 6.0.0 시점 스키마를 첫 마이그레이션으로 남길지, 빈 기준선을 만들고 기존 DB에는 적용 완료로 표시할지 [TECH-2638](https://linear.app/suppliesfitness/issue/TECH-2638/gymboxx-lib-마이그레이션-baseline-과-실행-주체방식을-정한다)에서 결정한다. 기존 테이블 생성 SQL을 운영에 다시 실행하지 않도록 실행 주체와 절차도 정한다.
- **CI 검사:** PR마다 엔티티와 기준 DB 스키마를 비교해 예상하지 못한 차이가 있으면 실패시키는 자동 검사다. `migration:check` 도구는 파일 생성·DDL 실행 없이 diff SQL을 출력하고 실패 코드를 반환한다. 도구는 스택에 들어왔지만 비교용 DB, 계정 전달, PR 자동 실행, 게이트 시작 시점이 [TECH-2640](https://linear.app/suppliesfitness/issue/TECH-2640/gymboxx-lib-ci-에-migrationcheck-를-넣는다)에 남아 있다. 운영 대비 diff 652문장이 있어 지금 게이트로 켜면 실패한다.

### 관리 기준

매일 개별 이슈 수 대신 **마일스톤 3개만** 갱신한다. 각 행에는 분류, 목표일, 완료를 막는 관문 1개, 다음 판정일을 적는다. `예상보다 잘 진행`은 미래 단계의 검증 증거가 계획보다 일찍 확보됐을 때, `정상진행중`은 목표일까지 관문을 통과할 경로가 확인될 때, `지연·정체`는 관문이 막혔거나 필요한 착수가 늦어졌을 때 쓴다. 퍼센트는 참고 수치로만 둔다.

## 판단 근거

| 단계 | Linear 표시 | 확인된 진척 | 남은 완료 조건 |
| --- | --- | --- | --- |
| 1. 엔티티 운영 DB 정렬 · 10/14 | 28% | 스택 PR [#343](https://github.com/suppliesfitness/gymboxx-lib/pull/343), [#345](https://github.com/suppliesfitness/gymboxx-lib/pull/345), [#346](https://github.com/suppliesfitness/gymboxx-lib/pull/346), [#348](https://github.com/suppliesfitness/gymboxx-lib/pull/348), [#349](https://github.com/suppliesfitness/gymboxx-lib/pull/349), [#350](https://github.com/suppliesfitness/gymboxx-lib/pull/350)이 6.0.0 작업 브랜치에 병합됐다. [TECH-2706](https://linear.app/suppliesfitness/issue/TECH-2706/gymboxx-lib-typeorm-으로-표현이-막힌-차이-정리-tech-2337-9번)에 dev DDL 4개 적용·확인 기록이 있다. 대조 도구로 남은 diff 652문장이 드러나 12~15번 작업이 추가됐다 | 열린 스택 작업 검증·통합, 운영 DDL 적용 확인, 652문장 정리. 마지막으로 main 대상 [#341](https://github.com/suppliesfitness/gymboxx-lib/pull/341) 리뷰·병합. 새 작업의 10/17 목표일과 10/14 마일스톤을 맞춰야 함 |
| 2. 6.0.0 릴리스·소비처 전환 · 10/20 | 8% | `6.0.0-dev.6` GitHub Packages 조회 확인. app-server develop [#1139](https://github.com/suppliesfitness/gymboxx-app-server/pull/1139) 병합 및 Jest 성공. [TECH-2338](https://linear.app/suppliesfitness/issue/TECH-2338/gymboxx-lib-엔티티를-운영-db-정본으로-정렬-600)은 `In Progress` | 정식 6.0.0 발행, app-server main과 [public-server](https://linear.app/suppliesfitness/issue/TECH-2637/gymboxx-public-server-에-gymboxx-lib-600-을-적용한다)·[payment-lambda](https://linear.app/suppliesfitness/issue/TECH-2339/gymboxx-payment-lambda-typeorm-03-entity-camel-전환) 전환 |
| 3. baseline·CI 검사 · 10/23 | 8% | [#355](https://github.com/suppliesfitness/gymboxx-lib/pull/355)로 `migration:check` 도구가 6.0.0 스택에 병합됐다. [TECH-2640](https://linear.app/suppliesfitness/issue/TECH-2640/gymboxx-lib-ci-에-migrationcheck-를-넣는다)은 `in QA` | [baseline·실행 방식](https://linear.app/suppliesfitness/issue/TECH-2638/gymboxx-lib-마이그레이션-baseline-과-실행-주체방식을-정한다), [dev 스키마](https://linear.app/suppliesfitness/issue/TECH-2639/gymboxx-dev-db-스키마를-운영과-맞춘다-32문장), 비교용 DB·계정 전달·PR 자동 실행·게이트 시작 시점 결정 필요. 652문장 diff를 먼저 정리해야 함 |

## 우선순위와 상태 기록

- [TECH-2632](https://linear.app/suppliesfitness/issue/TECH-2632/gymboxx-lib-숫자-enum-1개를-운영-db-에-맞춘다-tech-2337-7번)는 사용자 요청으로 Linear `Low`, 기한 10/14로 조정했다. 엔티티 수정 PR #351은 열려 있고 상태는 `in QA`다. 1단계 최종 통합에서는 빠뜨리지 않는다.
- 상위 [TECH-2337](https://linear.app/suppliesfitness/issue/TECH-2337/gymboxx-lib-migration-cicd)은 `Todo`인 반면 프로젝트는 `In Progress`다. 하위 작업과 PR 증거상 상위 상태가 실제 착수 상태를 반영하지 않는다. 조사에서는 프로젝트·하위 이슈·PR을 함께 보며, 상위 이슈 상태 정합화는 후속으로 남긴다.
- 가장 가까운 검증 관문은 남은 스택 작업의 QA와 운영 DDL 결과다. #341은 그 결과가 갖춰진 뒤의 최종 통합이다. 10/14 목표를 평가할 때 코드 작성, QA 통과, 운영 반영을 각각 분리한다.
