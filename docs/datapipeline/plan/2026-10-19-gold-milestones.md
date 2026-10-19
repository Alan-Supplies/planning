# Gold(Mart) 완료까지 마일스톤 (2026-10-19)

Silver 적재가 2026-10-19 에 dev 에서 돌기 시작했다. 이 문서는 그 다음 구간인 **Gold(`mart_gymboxx`) 완료**까지를
작업 단위로 쪼개고, 각 작업의 공수와 그 근거를 적는다. 작업 하나는 **최대 1일**이다. 1일을 넘길 것 같은 일은
여기서 미리 둘로 나눴다.

기존 일정([planing] `docs/plans/261016-DW-Airflow-최종일정-초안.md`, 2026-10-16)은 PoC 완료를 11/20 으로 잡았다.
그 일정의 "Airflow 기반(10/26~10/30)" 과 "Raw 적재(11/2~11/6)" 가 10/19 에 이미 끝났으므로 여기서 다시 잡는다.
**목표일은 11/10, 기존 목표 11/20 까지 영업일 7일이 버퍼**다.

## 1. 완료의 정의

"최종 Gold 완료" 는 Linear [TECH-868](https://linear.app/suppliesfitness/issue/TECH-868) (Gold 스키마 설계)과
[TECH-869](https://linear.app/suppliesfitness/issue/TECH-869) (Gold 적재 파이프라인)의 완료 기준을 **dev PoC 범위에서**
전부 충족한 상태다.

| 이슈 | 완료 기준 (Linear 본문 그대로) | 이 문서의 작업 |
| -- | -- | -- |
| TECH-868 | GOLD MART 목록 확정 · MART 별 Grain/Metric 정의 · SILVER → GOLD Mapping 문서화 | M2 |
| TECH-869 | SILVER → GOLD 자동화 · 주요 dbt test 통과 · Metric 검증 · Airflow 자동 실행 성공 | M3, M4 |

여기에 10/16 일정이 PoC 종료 기준으로 둔 **E2E 실측**(합성 변경 → Mart 반영 지연, 연속 배치 3회 성공, 의도적 실패 후
복구 1회, 재실행 중복 0건)을 더한다. 이 수치가 운영 전환 판단의 입력이다.

### 범위

- 원천: `gymboxx-dev` 합성 데이터. 테이블은 `user_exercise_session`, `user_exercise_session_history`,
  **`user_exercise_set_history`** 3개. 세 번째는 아직 DMS 에 없다(M1 에서 추가). PoC 지표
  "일별 세션당 평균 세트 완료율" 이 세트 테이블 없이는 계산되지 않는다(PoC 진행상황 2026-08-18 결정 4번).
- Gold 모델: `dim_date`, `fct_workout_session`, `fct_workout_set`, `agg_daily_session_set_completion`,
  `agg_user_workout`. 원안(`supplies-data-plan.md` §7-2)의 `fact_workout` 을 세션·세트 두 grain 으로 나눈 것이다.
- 범위 밖: `dim_user`·`dim_gym`(원천 `user`·`gym` 이 DMS 에 없고 PII 라 마스킹 설계가 선행돼야 한다), 운영 데이터
  전환(원안 §7-1 의 L3 진입 조건 5개와 법무·보안 승인이 별도 관문), 다른 도메인(주문·출석·푸시).

## 2. 공수 산정 근거 — 이 프로젝트의 실측

추정이 아니라 **같은 레포에서 같은 사람이 한 비슷한 일의 실제 소요**를 기준으로 잡았다. 시각은 PR 생성 → 머지(UTC).

| 비교 대상 | 규모 | 실제 소요 | 이 문서에서 쓰는 단위 |
| -- | -- | -- | -- |
| data-warehouse#1 with-aws-env + 스모크 DAG | +67줄 | 10/07 09:32 → 15:46, **6시간** | 스크립트·DAG 소규모 변경 = 0.5일 |
| data-warehouse#2 raw 적재 DAG + 로더 | +356줄 | 설계(#528)와 같은 날 10/16 착수, 10/19 오전 검증·머지. 주말 제외 **약 1.5일** | 적재 로직 신규 = 1일 + 검증 0.5일 |
| data-warehouse#3 Silver 모델 2개·macro·DAG | +224줄 | 10/19 01:14 → 05:48, **4.5시간** + bootstrap 검증 1시간 | dbt 모델 1~2개 = 0.5~1일 |
| data-warehouse#4 DAG 파라미터 수정 | +10줄 | **2분** | 사소한 수정은 공수로 세지 않는다 |
| platform-iac#516 ECR 리포·OIDC 롤 | +184줄 | **39분** | tf 리소스 추가(복제 가능) = 0.25일 |
| platform-iac#519 Airflow 진입 경로·시크릿 4종 | +130줄 | **6시간 45분** | tf 에 외부 시스템 연동이 섞이면 = 0.5~1일 |
| platform-iac#528 raw dataset + 적재 설계 문서 | +190줄 | 10/16 하루 작성, 10/19 머지 | 설계 문서 1건 = 1일 |
| platform-iac#532 설계 문서 정정 | +69줄 | **52분** | 문서 보강 = 0.25일 |
| platform-gitops#196 Airflow 3 배포 | — | 10/07 → 10/16, **9일**(다른 업무 병행, 10/16 일정은 5일 배정) | 배포·인프라는 대기가 길다. 이 문서엔 이 급의 일이 없다 |
| Silver ↔ Athena 행 수 대조·차이 원인 분석 | — | 10/19, **1시간 이내**(D 행·동점 원인까지) | 대조 1건 = 0.25~0.5일 |
| 운동기록 TECH-997~1001 산정 | — | 이슈당 1~3일, 8영업일(`일정산출보강.md`) | 하루 단위 산정의 선례 |

여기서 나온 규칙:

1. **코드 200~350줄 규모의 DAG·로더·모델 묶음 1건 = 0.5~1일.** 검증은 따로 0.25~0.5일.
2. **platform-iac 리소스 추가 1건 = 0.25~0.5일.** 기존 블록을 복제하는 일은 0.25일, 외부 연동이 섞이면 0.5일.
3. **설계 문서 1건 = 1일.** 단 내용이 이미 코드·README 에 있어 모으기만 하면 0.5일.
4. **대기가 있는 일은 대기를 공수에 넣는다.** raw 적재는 매시, DMS cdc 파일은 5분(`CdcMaxBatchInterval=300`),
   DMS full load 는 수 분. "다음 정기 실행 확인" 이 끼면 최소 1시간이 비는데, 그 시간엔 다른 작업을 한다.
5. **외부 결정(PO)은 공수가 아니라 시한이다.** 요청을 먼저 보내고 답이 오기 전까지는 가정값으로 진행한다.

## 3. 마일스톤과 작업

작업 번호는 `M-n` 이다. 공수는 영업일 기준이고 1일을 넘는 작업은 없다.

### M0. Silver 마무리 (10/20 ~ 10/21, 1.5일)

이번 주는 gymboxx-lib 6.0.0 소비처 전환(10/20 관문)이 있어 DW 에는 작은 일만 둔다.

#### 0-1. 열린 PR 머지와 raw 파티션 만료 확인 (0.25일)

- 대상: data-warehouse#5(raw 파티션 만료 180/90일), platform-iac#535(Athena 뷰 한계 문서).
- 통과 기준: #5 머지 후 첫 정기 실행에서 `bq show` 로 4개 테이블의 파티션 만료가 걸린 것을 확인.
- 근거: #4 가 PR → 머지 2분. 머지 뒤 매시 실행 1회를 기다리는 시간이 공수의 대부분이다.

#### 0-2. TECH-866 Silver 스키마 문서 (1일)

- 산출물: 이 폴더에 Silver 설계 문서. grain(PK 당 현재 행 1개), 키, 파티션·클러스터링(`cluster_by=id`), CDC MERGE 정책
  (정렬 키 4개, `Op='D'` 삭제, 증분 3일 창, 더 새 변경만 MERGE), 동점 규칙(`_bronze_row`), 알려진 한계(D 누락 + 옛 변경 +
  full-refresh 겹침, prod replica lag).
- 통과 기준: TECH-866 완료 기준 4개(ERD/Schema, grain, Key/Partition/Clustering, CDC Merge 정책)에 각각 절이 있다.
- 근거: 내용은 이미 README "BigQuery raw → Silver" 절, `dbt/macros/cdc_current.sql` 주석, 레이크 설계 §4·§5 에 흩어져
  있다. 새로 정하는 게 아니라 모으는 일이라 규칙 3 의 0.5일이지만, 3개 테이블 ERD 와 타입 표(`uint32`→`INT64`,
  `timestamp[ms]`→`TIMESTAMP`)를 처음 적으므로 1일로 둔다.

#### 0-3. Linear 정리 (0.25일)

- TECH-865(실행 환경)·TECH-2559(gitops Airflow)는 10/16 배포로 사실상 끝났다. 증거 링크를 달고 Done 처리.
- TECH-866 In Progress, TECH-868·869 를 Cycle 8 에 배정. TECH-867 의 남은 항목("CDC 정상 반영" 실측)은 1-3 에서
  닫는다고 댓글.
- 근거: 상태 전환과 링크 작업뿐이다.

### M1. Bronze 재가동과 범위 확장 (10/22 ~ 10/26, 3일)

`user_exercise_set_history` 를 DMS 에 넣고, 멈춰 있는 CDC 를 다시 돌린다. 둘을 한 번에 하는 이유는 **CDC 를 새로 시작하면
어차피 새 full 스냅샷이 필요**하기 때문이다(레이크 설계 §4 "full ↔ cdc 경계": 스냅샷 시각 이전 cdc 는 스냅샷에 진다).

> ⚠️ `dev-gymboxx-cdc` 는 2026-08-28 에 멈췄다. 52일이 지나 MySQL binlog 가 남아 있을 가능성이 낮으므로 resume 이 아니라
> **새 시작**으로 간주한다. 그래서 1-2 의 full 스냅샷이 1-1 보다 뒤여야 한다.

#### 1-1. platform-iac: DMS 매핑·Glue 테이블·뷰 SQL 에 set_history 추가 (1일)

- 변경: `stacks/data/dms/dev/main.tf` 의 테이블 목록에 1항목(selection rule 은 `for t in` 으로 생성된다).
  `stacks/data/glue/dev/main.tf` 에 cdc·full 테이블 2개(지금 4개 테이블이 355줄이라 테이블당 약 90줄 복제).
  `scripts/sql/user_exercise_set_history_current.sql`(기존 뷰 복제, 컬럼만 교체).
- 통과 기준: CI apply 성공, DMS 태스크 매핑에 3개 테이블, Glue 에 테이블 6개.
- 근거: 규칙 2. tf 리스트 1항목과 복제 2벌은 각 0.25일(#516 39분)이지만, DMS 태스크는 매핑을 바꾸면 중지·수정·재시작이
  필요해(#519 급의 외부 연동) 합쳐 1일로 둔다.

#### 1-2. CDC 새 시작 + full 스냅샷 3개 테이블 + `_current` 뷰 재생성 (0.5일 + 대기)

- 절차: `scripts/dms-full-load`(날짜 계산 → BucketFolder 교체 → reload → 완료 대기 → 파일 확인) → cdc 태스크 시작 →
  `scripts/athena-run view` 로 뷰 3개 재생성 → dev DB 에 합성 변경 1건을 내고 5분 안에 `cdc/<table>/<오늘>/` 에 파일이
  생기는지 확인.
- 통과 기준: `full/<새 날짜>/` 에 3개 테이블 파일, cdc 날짜 폴더에 오늘 파일, Athena `*_current` 3개 조회 성공.
- 근거: 스크립트가 절차를 자동화해 두었고 08-28 스냅샷(1,116행·335행)은 수 분이면 끝났다. CDC 검증은 08-24 에 이미 한
  절차의 반복이다. 이 스냅샷이 #5 가 경고한 "08-28 스냅샷 11/26 만료" 도 해소한다.

#### 1-3. Silver 에 set_history 모델 추가 + 3개 테이블 full_refresh + 대조 (1일)

- 변경: `dbt/models/gymboxx/_sources.yml` 에 2줄, `user_exercise_set_history.sql`(기존 모델과 같은 꼴, macro 재사용),
  `_models.yml` 테스트. raw 는 S3 폴더를 자동 발견하므로 손댈 것이 없다(README).
- 절차: 다음 정기 raw 실행에서 `user_exercise_set_history_cdc/_full` 생성 확인 → 머지 → `silver_gymboxx` 를
  `full_refresh: true` 로 실행(새 스냅샷이 base 가 되도록, README 규칙) → Athena `op <> 'D'` 행 수와 대조 → 1-2 의 합성
  변경이 Silver 에 반영됐는지 확인.
- 통과 기준: 3개 테이블 행 수가 Athena non-D 와 같다. 합성 변경 1건이 Silver 에 보인다(TECH-867 "CDC 정상 반영" 증거).
- 근거: #3 이 모델 2개·macro·DAG 를 4.5시간에 했고 여기선 모델 1개다(규칙 1 의 0.5일). raw 매시 실행 대기와 full_refresh,
  대조(규칙 "대조 1건 0.25일")를 더해 1일.

### M2. Gold 설계 — TECH-868 (10/27 ~ 10/29, 3일)

#### 2-1. 지표 정의 확정 (1일, PO 합의)

PoC 지표 "일별 세션당 평균 세트 완료율" 은 정의가 값을 좌우한다. 아래 5개를 PO 와 확정하고 문서에 남긴다.
**요청은 10/20 에 보내고** 답이 없으면 괄호의 가정값으로 2-2 이하를 진행한다.

| 결정 | 가정값(추천) | 이유 |
| -- | -- | -- |
| 세트 완료 판정 | `user_exercise_set_history.done_at IS NOT NULL`. 과거 NULL 행은 `created_at` 으로 대체 | 세트 테이블에 완료 플래그가 없다. `done_at` 은 TECH-999 가 "세트 수행 시각" 으로 추가한 컬럼이고 과거 행은 NULL 이다 |
| 세션의 분모 | 세션에 기록된 세트 전체. 세트 0건 세션은 분모에서 제외하고 "세트 없는 세션 비율" 을 보조 지표로 분리 | 0/0 을 0% 로 넣으면 평균이 왜곡된다 |
| 날짜 기준 | 세션 `end_at` 의 KST 일자, NULL 이면 `started_at` | 데이터 Warehouse 장기 플랜 §6 "시간" 과 KST 공통화(P0-03) 방침 |
| 제외 조건 | `user_exercise_session.is_deleted = 1` 제외 | Silver 는 소프트 삭제를 앱 데이터로 보존한다(README) |
| GYM / OUTSIDE | `gym_id IS NULL` 을 OUTSIDE 로 구분해 컬럼으로 둔다. 지표에선 둘 다 포함 | 원안 §9 R5 "source 분리" — 북극성 지표와 규칙이 다르므로 컬럼으로 남겨 뒤에서 고른다 |

- 근거: 10/16 일정의 선행관계 4번("11/9 까지 PO 결정")을 앞당긴 것이다. 인프라 스택 이슈 7번도 "착수 전에 합의" 라고
  적었다. 작업자의 공수는 요청서·정의 표 작성 반나절이고 나머지는 답변 대기다.

#### 2-2. Gold 설계 문서 (1일)

- 산출물: 이 폴더에 Gold 설계 문서. 모델 5개의 grain·컬럼·키, fact/dim 결정(dim 은 `dim_date` 만), 집계 기준(2-1),
  스냅샷 여부(없음 — Silver 가 현재 상태를 보존), 파티션(`fct_*` 는 일자, `agg_daily_*` 는 일자)·클러스터링(`user_id`),
  네이밍(`mart_gymboxx`, `fct_`/`dim_`/`agg_` 접두), Silver → Gold lineage 표.
- 통과 기준: TECH-868 완료 기준 3개(MART 목록, grain/metric, mapping)가 각각 절로 있다.
- 근거: 규칙 3 의 1일. #528 설계 문서(190줄)가 하루였고, 여기엔 원안 §7-2 의 `fact_workout` 정의와 화이트보드 정리
  (`DW-구조-정리.md` §5)가 있어 백지가 아니다.

#### 2-3. 검증 쿼리 + `mart_gymboxx` dataset (1일)

- 검증 쿼리(0.5일): 2-1 정의 그대로 dev MySQL 에서 직접 계산하는 SQL 과 BigQuery Mart 를 읽는 SQL 을 `.probe` 로 작성.
  표본은 일자 5개·사용자 5명. 3-4 가 이걸 그대로 돌린다.
- platform-iac(0.5일): `stacks/data/bigquery/dev/bigquery.tf` 에 `mart_gymboxx` dataset 과 dbt SA `dataEditor` 블록
  (raw 블록 약 25줄 복제), CI apply.
- 통과 기준: probe 의 MySQL 쪽이 값을 내고, `bq ls` 에 `mart_gymboxx`.
- 근거: dataset 은 규칙 2 의 0.25일(#528 의 dataset 부분이 그 꼴)이고 여유를 둬 0.5일. 검증 쿼리는 10/19 Athena 대조 쿼리
  작성이 1시간 안이었지만 지표 정의 5개를 SQL 로 옮기므로 0.5일.

### M3. Gold 구현 — TECH-869 전반 (10/30 ~ 11/4, 4일)

#### 3-1. dbt 레이어 구조와 dataset 라우팅 (1일)

- 변경: `models/gymboxx/`(Silver) 옆에 `models/gold/{intermediate,marts}/`. 경로별 `+schema` 와
  `generate_schema_name` macro 재정의(dbt 기본은 `<target>_<custom>` 으로 이어 붙여 `silver_gymboxx_mart_gymboxx` 가 된다).
  `sources.yml` 에 Silver 를 source 로 등록하고 `freshness`(`_commit_ts` 기준 경고 25시간·오류 49시간).
- 통과 기준: `dbt ls --select gold` 가 빈 모델이라도 `mart_gymboxx` 를 대상으로 렌더된다. `dbt source freshness` 가 돈다.
- 근거: #3 의 프로젝트 설정 부분이 반나절이었다. 여기에 schema macro 와 freshness 가 더해져 1일. 이걸 3-2 와 섞으면 하루를
  넘긴다.

#### 3-2. `fct_workout_session` · `fct_workout_set` (1일)

- 변경: Silver 3개 테이블을 조인해 세션 1행(사용자·지점·KST 시작/종료·운동 수·세트 수·완료 세트 수·총 볼륨·운동 시간·
  OUTSIDE 여부)과 세트 1행(세션·운동·세트 번호·횟수·중량·수행 시각·완료 여부). 테스트: `unique`·`not_null`·
  `relationships`(세트 → 세션), `accepted_values`.
- 통과 기준: `dbt build --select gold` 통과. 세션 수가 Silver `user_exercise_session`(`is_deleted=0`)과 같다.
- 근거: 규칙 1. #3 의 모델 2개가 4.5시간이었지만 그건 macro 호출 한 줄짜리였다. 여기는 조인·KST 변환·파생 컬럼이 있어 1일.

#### 3-3. `dim_date` · `agg_daily_session_set_completion` · `agg_user_workout` (1일)

- 변경: 날짜 차원(일·주·월, KST), 일별 집계(세션 수·세트 완료율 평균·세트 없는 세션 비율), 사용자별 집계(운동 횟수·마지막
  운동일). 2-1 의 edge case(세트 0건, `end_at` NULL)를 테스트로 고정.
- 통과 기준: `dbt build --select gold` 통과. 2-1 표의 가정값이 모델 설명(`description`)에 적혀 있다.
- 근거: 집계 SQL 자체는 작다. 공수는 edge case 테스트와 설명 작성이다. 규칙 1 의 0.5일에 여유를 둬 1일.

#### 3-4. Metric 검증 (1일)

- 절차: 2-3 probe 로 MySQL 직접 계산 값과 Mart 값을 표본(일자 5개·사용자 5명)에서 대조. 불일치는 원인(정의 차이 /
  시간대 / Silver 지연 / 버그)을 분류해 문서화하고, 버그면 고친다.
- 통과 기준: 표본 전체 일치, 또는 불일치마다 원인과 결정이 적혀 있다(TECH-869 "Metric 검증 완료").
- 근거: 10/19 Silver ↔ Athena 대조에서 행 수 1건·33건 차이의 원인(D 행, 같은 트랜잭션 동점)을 찾는 데 1시간이 걸렸다. 지표는
  정의 차이가 더 자주 나오고, 고치고 다시 돌리는 왕복이 있어 1일.

### M4. 자동화와 운영성 — TECH-869 후반 (11/5 ~ 11/9, 3일)

#### 4-1. `gold_gymboxx` DAG (0.5일)

- 변경: `silver_gymboxx` 의 task 에 `outlets=[Asset("silver_gymboxx")]`, 새 DAG 가 그 Asset 으로 `dbt build --select gold`.
  `full_refresh` 파라미터. Silver 와 DAG 를 나누는 이유는 Gold 만 full_refresh 할 때가 있어서다(지표 정의 변경).
- 통과 기준: raw → silver → gold 가 Asset 체인으로 한 번에 이어져 세 DAG 가 success.
- 근거: `dags/silver_gymboxx.py` 가 50줄이고 Asset 체인은 10/19 에 이미 동작을 확인했다. 복제에 가깝다.

#### 4-2. dbt docs·lineage 게시 + freshness task (0.5일)

- 변경: CI(main push)에서 `dbt docs generate` 산출물을 GitHub Pages 로 게시. `gold_gymboxx` DAG 앞에
  `dbt source freshness` task.
- 통과 기준: lineage 그래프에서 raw → Silver → Gold 가 보인다. freshness 가 Silver 지연 시 경고로 끝난다.
- 근거: 규칙 "스크립트·DAG 소규모 변경 0.5일"(#1 급). `docs generate` 는 BigQuery 연결이 필요해 CI 러너의 WIF(ADC) 경로를
  쓴다 — 이미 #297 에서 만든 경로라 새 인증 작업은 없다.

#### 4-3. 실패 알림과 재처리 runbook (1일)

- 변경: 세 DAG 의 `on_failure_callback` → Slack. webhook 은 platform-iac 시크릿 + gitops worker env(#519 와 같은 경로).
  README 에 runbook: 실패 유형별(raw 날짜 재적재 `dates`, Silver/Gold `full_refresh`, 스냅샷 재생성) 수동 재처리 절차.
- 통과 기준: 의도적으로 실패시킨 task 가 Slack 에 도착한다. runbook 대로 재처리해 복구된다.
- 근거: #519(시크릿 4종) 6시간 45분이 가장 가까운 선례다. 알림 코드는 작지만 시크릿이 두 레포를 거친다.
  **TECH-3065(task 로그 S3 보존)** 는 별도 이슈이고 이 일정에 넣지 않는다. 먼저 되면 4-4 의 실패 분석이 쉬워진다.

#### 4-4. E2E 실측 (1일)

- 절차: dev MySQL 에 합성 변경(insert·update·delete 각 1건 이상) → DMS → S3 → raw(매시) → Silver → Gold 반영까지 시각을
  3회 기록. 의도적 실패 1회(예: Silver 테스트 실패) 후 복구. 같은 창을 두 번 돌려 중복 0건. BigQuery 바이트 스캔으로
  1일 비용 추정.
- 통과 기준: 10/16 일정의 PoC 종료 기준 그대로 — 연속 3회 성공, 복구 1회, 중복 0건, 지연·비용 수치.
- 근거: 매시 배치라 1회 측정에 최대 1시간을 기다린다. 3회 + 실패 복구 1회면 반나절이 대기이고 나머지가 기록이다.

### M5. PoC 종료 판정 (11/10, 1일)

#### 5-1. 완료 증거 정리 (0.5일)

- TECH-868·869 완료 기준마다 증거 링크(문서·PR·실행 ID·probe 결과) 댓글. README 의 구조 절에 Gold 추가. Linear Done.
- 근거: 0-3 과 같은 성격의 정리 작업.

#### 5-2. 결과 보고와 운영 전환 관문 입력 (0.5일)

- 산출물: 지연·비용·한계 1쪽. 한계는 이미 알려진 것들이다 — full 스냅샷 월 1회 수동(레이크 설계 §10), D 누락 + 옛 변경 +
  full-refresh 겹침(README), prod replica lag(레이크 설계 §4 미해결), task 로그 미보존(TECH-3065), PII 마스킹 미설계.
- 근거: 10/16 일정의 "11/23~11/27 운영 전환 설계 관문" 이 이 문서를 입력으로 받는다. 새로 조사하는 항목은 없다.

## 4. 달력

영업일 기준, 공휴일 없음. 괄호는 공수.

| 날짜 | 작업 | 비고 |
| -- | -- | -- |
| 10/20 (화) | 0-1 (0.25) · 0-3 (0.25) · **2-1 요청 발송** | 나머지는 lib 6.0.0 소비처 전환 관문 |
| 10/21 (수) | 0-2 TECH-866 문서 (1) | |
| 10/22 (목) | 1-1 platform-iac set_history (1) | CI apply |
| 10/23 (금) | 1-2 CDC 새 시작·스냅샷 (0.5+대기) | 대기 중 1-3 의 모델 파일 작성 |
| 10/26 (월) | 1-3 Silver set_history + full_refresh + 대조 (1) | TECH-867 "CDC 정상 반영" 닫힘 |
| 10/27 (화) | 2-1 지표 정의 확정 (1) | PO 답변 시한. 미답이면 가정값 |
| 10/28 (수) | 2-2 Gold 설계 문서 (1) | TECH-868 |
| 10/29 (목) | 2-3 검증 쿼리 + mart dataset (1) | CI apply |
| 10/30 (금) | 3-1 dbt 레이어 구조 (1) | |
| 11/2 (월) | 3-2 fct 2개 (1) | |
| 11/3 (화) | 3-3 dim·agg 3개 (1) | |
| 11/4 (수) | 3-4 Metric 검증 (1) | |
| 11/5 (목) | 4-1 gold DAG (0.5) · 4-2 docs·freshness (0.5) | |
| 11/6 (금) | 4-3 알림·runbook (1) | 시크릿 2개 레포 |
| 11/9 (월) | 4-4 E2E 실측 (1) | |
| 11/10 (화) | 5-1 (0.5) · 5-2 (0.5) | **목표일** |
| 11/11 ~ 11/20 | 버퍼 7일 | 기존 목표 11/20 유지 |

공수 합계 14.75일, 달력 15영업일. 버퍼 7일은 공수의 47% 다. 10/16 일정에서 Airflow 배포가 배정 5일 대비 9일(180%)
걸렸던 것을 기준으로 잡았다. 버퍼를 다 쓰는 경우는 2-1 합의 지연과 1-2 의 DMS 재시작 문제다.

## 5. 선행관계와 결정 시한

1. **10/20 2-1 요청 발송.** 10/27 까지 답이 없으면 가정값으로 진행하고 문서에 "결정 필요" 로 남긴다. 나중에 정의가 바뀌면
   Gold `full_refresh` 한 번으로 재계산된다 — 그래서 Silver 가 아니라 Gold 에서 정의를 적용한다.
2. **1-1 → 1-2 → 1-3 은 순서가 고정이다.** 매핑 추가 전에 스냅샷을 뜨면 세트 테이블이 빠지고, 스냅샷 전에 Silver 를
   full_refresh 하면 base 가 08-28 로 남는다.
3. **2-3 의 dataset 이 3-1 보다 먼저** 적용돼야 한다. 3-1 이 `mart_gymboxx` 를 대상으로 렌더하기 때문이다.
4. **4-3 의 webhook 시크릿**은 platform-iac → gitops 두 PR 이 필요하다. 11/5 에 먼저 올려 11/6 에 쓴다.
5. 1-2 에서 CDC 가 새 시작이 안 되는 경우(binlog·권한)는 TECH-862 의 절차(`binlog` 설정 확인)로 돌아간다. 이때 버퍼를 쓴다.

## 6. 이 일정이 전제하는 것

- 작업자 1명. platform-iac·gitops 의 CI apply 와 PR 머지는 본인이 한다.
- `gymboxx-dev` 와 DMS 복제 인스턴스가 계속 쓸 수 있다. dev DB 에 합성 변경을 낼 권한이 있다(1-2, 4-4).
- 이번 주 lib 6.0.0 소비처 전환이 10/20 관문대로 끝난다. 밀리면 M0 가 하루 뒤로 간다.
- 운영 전환은 이 문서 밖이다. 11/10 결과 보고가 10/16 일정의 "11/23~11/27 운영 전환 설계 관문" 의 입력이 된다.

## 참고

- [planing] `docs/plans/261016-DW-Airflow-최종일정-초안.md` — 재조정 전 일정
- [planing] `project/데이터자산화/인프라-스택-구현-이슈.md` — 이슈 8건 분해(6·7·8번이 이 문서의 M2~M4)
- [planing] `project/데이터자산화/PoC-진행상황.md` — PoC 지표 결정(2026-08-18)
- [planing] `docs/datapipeline/DW-구조-정리.md` §5 — fact/dim 후보와 예상 지표
- [planing] `archive/운동기록데이터화/일정산출보강.md` — 하루 단위 산정 선례
- platform-iac `docs/data-pipeline/2026-08-20-lake-bronze-s3-design.md` §4·§10 — full ↔ cdc 경계, 정기 스냅샷
- platform-iac `docs/data-pipeline/2026-10-16-bronze-to-bigquery-load-design.md` — raw 적재 계약
- README "BigQuery raw → Silver" — Silver 규칙과 한계
