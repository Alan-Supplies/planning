# Silver · Gold 스키마 해설 (2026-10-19)

Bronze 까지 이해한 상태에서 Silver 와 Gold 를 **왜 이렇게 만드는지** 설명하는 문서다. Silver 는 이미 코드가 있어
(data-warehouse `dbt/models/gymboxx/`, `dbt/macros/cdc_current.sql`) 그 코드를 풀어 설명하고, Gold 는 이번에 처음
설계하는 안이다(마일스톤 2-2 의 초안 역할).

수치는 모두 **dev MySQL(`gymboxx`, 2026-10-19 조회)** 기준이다.

## 0. 큰 그림 — 층마다 답하는 질문이 다르다

| 층 | 위치 | 한 행의 의미 | 답하는 질문 |
| -- | -- | -- | -- |
| Bronze | S3 Parquet | DMS 가 본 **변경 1건** (I/U/D) | "무슨 일이 언제 있었나" |
| raw | BigQuery `raw_gymboxx` | Bronze 를 그대로 복사한 변경 1건 | (Bronze 와 같다. BigQuery 에서 읽기 위한 복사본) |
| Silver | BigQuery `silver_gymboxx` | 앱 DB 테이블의 **현재 행 1개** | "지금 DB 에 뭐가 있나" |
| Gold | BigQuery `mart_gymboxx` | **분석 질문의 단위** 1개 (세션 1개, 날짜 1개 …) | "일별 운동 완료율은?" |

비유하면 Bronze·raw 는 은행의 **거래 내역**, Silver 는 **현재 잔액**, Gold 는 **월별 지출 리포트**다. 거래 내역만
있으면 잔액을 매번 계산해야 하고, 잔액만 있으면 리포트를 매번 만들어야 한다. 층을 나누는 이유는 이 반복 계산을
한 번만 하고 그 규칙을 한 곳에 두기 위해서다.

## 1. Silver — "변경 로그를 현재 상태로 접는다"

### 1-1. 왜 필요한가

raw 에는 같은 `id` 가 여러 번 나온다. 세션 하나가 생기고(I), 운동을 끝내 `end_at` 이 채워지고(U), 나중에 지워지면(D)
행이 3개다. 게다가 full 스냅샷(어느 시점의 전체 복사)과 cdc(그 뒤 변경)가 섞여 있다. 분석하는 사람이 매번
"id 별로 마지막 변경을 골라라, D 면 빼라" 를 쓰게 하면 사람마다 다르게 쓰고 틀린다. Silver 는 그 규칙을 한 번
적용해 **앱 DB 와 같은 모양**으로 돌려놓는다.

앱 DB 와 같은 모양으로 두는 이유:

- 앱 개발자가 이미 아는 테이블이라 설명이 필요 없다.
- MySQL 과 행 단위로 대조할 수 있다(10/19 Athena 대조가 그것이다). 대조할 수 있어야 파이프라인을 믿을 수 있다.
- 업무 규칙(완료율 정의 같은)을 넣지 않으니 규칙이 바뀌어도 Silver 는 그대로다. 규칙은 Gold 의 몫이다.

### 1-2. grain — PK 하나에 현재 행 하나

`unique_key='id'` 와 `_models.yml` 의 `unique`·`not_null` 테스트가 이것을 보장한다. "grain" 은 **한 행이 무엇을
뜻하는가**다. grain 을 먼저 못박아야 `COUNT(*)` 가 무엇을 세는지 확실해진다.

### 1-3. 테이블과 컬럼

#### `silver_gymboxx.user_exercise_session` — 운동 세션 (출석 후 운동 1회)

| 컬럼 | MySQL 타입 | BigQuery 타입 | 뜻 | 메모 |
| -- | -- | -- | -- | -- |
| `id` | int unsigned | INT64 | 세션 PK | |
| `gym_id` | int NULL | INT64 | 지점. **NULL 이면 OUTSIDE**(지점 밖 운동) | dev OUTSIDE 9건 |
| `user_id` | int | INT64 | 회원 | |
| `access_history_id` | int | INT64 | 출석 기록 | 세션은 출석에서 시작된다 |
| `level` | int NULL | INT64 | 운동 레벨 | dev 242건 NULL |
| `purpose` | enum | STRING | 운동 목적 6종 | dev 242건 NULL |
| `rpe` | int unsigned NULL | INT64 | 체감 강도 | dev 182건 NULL |
| `started_at` | timestamp NULL | TIMESTAMP | 시작 | dev 29건 NULL |
| `end_at` | timestamp NULL | TIMESTAMP | 종료. **NULL 이면 미종료** | dev 98건 NULL |
| `is_deleted` | tinyint | INT64 | 소프트 삭제 | 앱 데이터라 Silver 가 지우지 않는다 |
| `created_at` | timestamp | TIMESTAMP | 행 생성 | |

#### `silver_gymboxx.user_exercise_session_history` — 세션 안의 운동 1개 (종목 1개)

| 컬럼 | MySQL 타입 | BigQuery 타입 | 뜻 | 메모 |
| -- | -- | -- | -- | -- |
| `id` | int unsigned | INT64 | PK | |
| `round_number` | int unsigned | INT64 | 세션 안 순서 | |
| `user_exercise_session_id` | int unsigned | INT64 | 소속 세션 | Gold 조인 키 |
| `exercise_id` | int | INT64 | 종목 | dev 종목 130개 |
| `machine_id` | int NULL | INT64 | 사용 머신 | |
| `weight_type` | enum('kg','lb') | STRING | 무게 단위 | |
| `is_done` | tinyint | INT64 | **운동 완료 여부** | PoC 지표의 근거 |
| `done_at` | datetime NULL | DATETIME? | 완료 시각 | ⚠️ 아래 "시간대" 참고 |
| `updated_at`, `created_at` | timestamp | TIMESTAMP | | |

**왜 타입이 바뀌나.** BigQuery 는 정수가 `INT64` 하나뿐이다(MySQL 의 int·tinyint·unsigned 구분이 없다). 그래서 Bronze
Parquet 의 `uint32`·`int8` 등이 모두 `INT64` 로 들어온다. enum 은 BigQuery 에 없어 `STRING` 이 된다.

**⚠️ 시간대.** dev MySQL 은 `time_zone = UTC` 다. `timestamp` 컬럼은 UTC 로 저장되므로 Silver 의 `TIMESTAMP` 도
UTC 다. 한국 날짜로 집계하려면 **Gold 에서 KST 로 바꿔야** 한다(Silver 는 원본 그대로 둔다). `done_at` 만
`datetime`(시간대 정보 없음)이라, 앱이 이 값을 UTC 로 쓰는지 KST 로 쓰는지 서버 코드에서 확인해야 한다.

**⚠️ Silver 에 없는 원천 컬럼.** 세션의 `updated_at`·`app_version`·`share_exported_at` 은 Silver 에 없다.
Glue 테이블 정의(platform-iac `stacks/data/glue/dev/main.tf`)부터 이 컬럼들이 빠져 있다. 마일스톤 §1 표의
"공유율·앱 버전" 지표는 이 컬럼을 Silver 에 추가해야 나온다. 추가하려면 raw 에 컬럼이 실제로 들어와 있는지 먼저 본다
(raw 는 컬럼 추가를 받는다 — README).

### 1-4. Silver 가 덧붙이는 메타 컬럼

| 컬럼 | 값 | 왜 남기나 |
| -- | -- | -- |
| `_op` | `I` / `U` | 이 행을 만든 마지막 변경 종류. `D` 는 지워지므로 남지 않는다(테스트로 확인) |
| `_commit_ts` | DMS 커밋 시각(TIMESTAMP) | "이 행이 원천에서 언제 마지막으로 바뀌었나". 증분 비교의 1순위 키 |
| `_load_rank` | full 0 · cdc 1 | 같은 시각이면 cdc 가 이기게 하는 비교 키 |
| `_bronze_date`·`_bronze_file`·`_bronze_row` | 원본 파일 위치 | 동점 깨기 + **어느 파일에서 왔는지 역추적** |

메타 컬럼에 `_` 를 붙이는 이유는 앱 컬럼과 섞이지 않게 하기 위해서다. Gold 는 이 컬럼들을 거의 쓰지 않는다.

### 1-5. 키 · 파티션 · 클러스터링

- **파티션 없음.** BigQuery 파티션은 "날짜별 서랍"이다. 조회 때 필요한 서랍만 열어 비용을 줄인다. 하지만 Silver 는
  수백~수천 행이라 전체를 읽어도 BigQuery 최소 과금(10MB) 안이다. 서랍을 나눠도 아낄 게 없고, 관리만 늘어난다.
- **`cluster_by=['id']`.** 클러스터링은 서랍 안을 `id` 순으로 정리해 두는 것이다. Silver 의 증분 실행은 매번
  `id` 로 기존 행을 찾아 MERGE 하므로 `id` 정렬이 MERGE 를 싸게 만든다. 운영 데이터처럼 커지면 효과가 생긴다.

### 1-6. CDC MERGE 정책 — 예시로 보기

세션 `id=7` 에 이런 일이 있었다고 하자.

| 순서 | 출처 | Op | `dms_commit_ts` | 내용 |
| -- | -- | -- | -- | -- |
| a | full 스냅샷(10/22) | I | 10-22 03:00 | `end_at` NULL |
| b | cdc | U | 10-22 05:10 | `end_at` 채워짐 |
| c | cdc | U | 10-22 05:10 | `rpe` 채워짐 (같은 트랜잭션) |
| d | cdc | D | 10-25 09:00 | 삭제 |

**규칙 1. 정렬 키 4개로 마지막 변경을 고른다** — `(dms_commit_ts, load_type, _bronze_file, _bronze_row)` 내림차순 첫 행.

- `dms_commit_ts`: 원천에서 바뀐 시각. 1순위인 건 당연하다.
- `load_type`(full < cdc): 스냅샷과 cdc 가 같은 시각이면 cdc 가 이긴다. 이 키가 없으면 파일 경로를 사전순으로
  비교하게 되는데, `full/…` 이 `cdc/…` 보다 뒤라 **스냅샷이 cdc 를 이겨 변경이 되돌아간다**.
- `_bronze_file`·`_bronze_row`: b 와 c 처럼 한 트랜잭션은 커밋 시각이 같다. DMS 는 파일에 순서대로 쓰므로 파일
  안 행 번호가 실제 순서다. 10/19 대조에서 33건 차이의 원인이 이 동점이었다.

→ d 가 마지막이다.

**규칙 2. 마지막이 `D` 면 행을 지운다.** dbt 의 merge 는 DELETE 를 못 하므로, 일단 D 행을 넣고 `post_hook` 의
`delete_source_deleted()` 로 지운다. D 행은 PK 외 컬럼이 비어 있을 수 있어 남겨 두면 안 된다.

**규칙 3. 소프트 삭제(`is_deleted=1`)는 지우지 않는다.** 앱이 "삭제됨" 표시만 한 것은 DB 에 행이 살아 있는 것이고,
그걸 뺄지는 분석 목적에 달렸다. 그래서 판단을 Gold 로 넘긴다. Silver 가 DB 와 다르면 대조가 깨진다.

**규칙 4. 증분은 최근 3일 cdc 만 다시 읽는다.** 매번 전체를 읽으면 비싸다. 3일인 이유는 raw 적재가 최근 3일
파티션을 통째로 다시 쓰기 때문이다(늦게 온 파일을 줍기 위해). "마지막으로 본 커밋 시각 이후" 로 자르지 않는 이유도
같다 — 늦게 들어온 파일에는 **이미 지난 커밋 시각**의 행이 있어서 시각으로 자르면 놓친다.

**규칙 5. 기존 행보다 더 새로운 것만 MERGE 한다.** CDC 가 변경을 놓치면(드리프트) 새 full 스냅샷으로 Silver 를 다시
만들어 바로잡는다. 그 뒤 3일 창 안의 **옛** cdc 변경이 교정된 행을 덮어쓰면 교정이 무의미해진다. 그래서 정렬 키로
비교해 더 새 것만 넣는다.

**알려진 구멍.** D 를 놓쳐 스냅샷에서 이미 사라진 행은 Silver 에 비교 대상이 없다. 그래서 3일 창 안에 그 행의
옛 I/U 가 있으면 되살아난다. D 누락, 옛 변경이 3일 안, 직전 full_refresh 세 조건이 겹칠 때만 생긴다.

### 1-7. full_refresh 는 언제 하나

증분은 "최근 3일만" 보므로, 그 밖의 일이 생기면 처음부터 다시 만든다(full_refresh = 최신 스냅샷 + cdc 전체).

- 새 full 스냅샷을 뜬 뒤 (마일스톤 1-2 가 이것)
- raw 에 3일보다 오래된 날짜를 다시 넣은 뒤

## 2. Gold — "질문에 답하는 모양으로 바꾼다"

### 2-1. 왜 Silver 위에 한 층 더 두나

"일별 세션당 평균 운동 완료율" 을 Silver 에서 바로 구하려면 매번 이렇게 해야 한다.

1. 세션과 운동을 조인한다.
2. 삭제된 세션을 뺀다.
3. UTC 를 KST 로 바꿔 날짜를 정한다(`end_at` 이 없으면 `started_at`).
4. 세션별 완료율을 구하고, 운동 0건 세션은 뺀다.
5. 날짜별로 평균한다.

규칙 5개를 사람마다 매번 쓰면 숫자가 사람마다 달라진다. Gold 는 이 규칙을 **한 번, 한 곳에** 적용한 결과를
테이블로 둔다. 지표 정의가 바뀌면 Gold 만 다시 만들면 된다(Silver 는 그대로).

### 2-2. 모양 — fact · dim · agg

| 종류 | 뜻 | 이번 모델 |
| -- | -- | -- |
| fact (`fct_`) | **일어난 일** 1건 1행. 숫자(측정값)와 다른 테이블을 가리키는 키를 가진다 | `fct_workout_session`, `fct_workout_exercise` |
| dim (`dim_`) | fact 를 **설명하는 것**(언제·누가·어디서). 잘 안 바뀐다 | `dim_date` |
| agg (`agg_`) | fact 를 **미리 집계**한 것. 자주 보는 질문을 빠르고 일관되게 | `agg_daily_session_exercise_completion`, `agg_user_workout` |

이 모양(가운데 fact, 주변 dim)을 스타 스키마라고 한다. BI 도구가 이 모양을 전제로 만들어져 있어서 드래그만으로
"날짜별 × 지점별 완료율" 같은 표가 나온다.

`dim_user`·`dim_gym` 이 없는 이유는 원천 `user`·`gym` 테이블이 아직 DMS 에 없고, 회원 정보는 개인정보라 마스킹 설계가
먼저이기 때문이다. 그래서 fact 에는 `user_id`·`gym_id` 숫자만 둔다. 나중에 dim 이 생기면 이 키로 붙는다.

### 2-3. 공통 규칙

| 규칙 | 결정 | 이유 |
| -- | -- | -- |
| 시간대 | 모든 날짜·시각을 **KST** 로 바꿔 둔다(`_kst` 접미) | DB 는 UTC 다. 한국 서비스의 "하루" 는 KST 자정 기준이다. UTC 로 자르면 오전 9시 이전 운동이 전날로 간다 |
| 운동 날짜 | `workout_date` = KST(`end_at`) → 없으면 KST(`started_at`) → 없으면 KST(`created_at`) | 끝난 날이 "운동한 날" 에 가깝다. `started_at` 도 29건 비어 있어 마지막 대체로 `created_at`(항상 있음)을 둔다. ⚠️ 2-1 의 2단계 정의에 3단계를 더한 것이라 PO 요청서에 반영한다 |
| 삭제 | `is_deleted=1` 세션은 Gold 에 **넣지 않는다** | 사용자가 지운 운동은 지표에서 빼는 게 자연스럽다(2-1 가정값). 남겨 두고 플래그로 거르게 하면 누군가 반드시 빼먹는다 |
| 물리화 | 모두 `table`, 매 실행 **통째로 다시 만든다** | 수천 행이라 다시 만드는 비용이 0 에 가깝다. 증분으로 만들면 "지표 정의 변경 시 과거 재계산" 을 따로 챙겨야 한다. 커지면 그때 증분으로 바꾼다 |
| 파티션 | `fct_*`·`agg_daily_*` 는 `workout_date`, 월 단위 | Gold 는 "지난 30일" 처럼 **날짜 범위로 조회**된다. 운영 규모에서 의미가 생긴다. dev 에선 습관을 맞춰 두는 것 |
| 클러스터링 | `user_id` | 날짜 다음으로 많이 거르는 조건이 "이 회원" 이다 |

### 2-4. `dim_date` — 날짜 1행

| 컬럼 | 예 | 이유 |
| -- | -- | -- |
| `date_kst` (PK) | 2026-10-19 | 조인 키 |
| `year`, `month`, `iso_week`, `day_of_week` | 2026, 10, 42, 1(월) | 주별·월별·요일별 집계를 SQL 없이 고르게 |
| `is_weekend` | false | 주말 운동 패턴 비교 |

**왜 따로 두나.** 세션이 없는 날은 fact 에 행이 없다. fact 만으로 일별 그래프를 그리면 그날이 **빠져서** 선이
이어져 버린다. `dim_date` 를 기준으로 붙이면 그날이 "세션 0" 으로 보인다. 범위는 원천 첫 세션 날짜부터 오늘까지다.

### 2-5. `fct_workout_session` — 세션 1행

grain: 삭제되지 않은 세션 1개. 행 수 = Silver `user_exercise_session` 의 `is_deleted=0` 행 수(dev 483).

| 컬럼 | 출처 / 계산 | 이유 |
| -- | -- | -- |
| `session_id` (PK) | `id` | |
| `user_id`, `gym_id` | 그대로 | 나중의 `dim_user`·`dim_gym` 조인 키 |
| `is_outside` | `gym_id IS NULL` | 지점 운동과 외부 운동은 지표 규칙이 다르다(원안 §9 R5). NULL 검사를 매번 쓰지 않게 이름을 붙여 둔다 |
| `workout_date` | 2-3 의 날짜 규칙 | 모든 일별 집계의 기준. 한 곳에서 정해야 숫자가 맞는다 |
| `started_at_kst`, `ended_at_kst` | KST 변환 | |
| `is_finished` | `end_at IS NOT NULL` | 미종료 세션(dev 20%)을 따로 볼 수 있게 |
| `duration_minutes` | `ended - started`, 둘 중 하나라도 없으면 NULL | 없는 값을 0 으로 채우면 평균 운동 시간이 낮아진다 |
| `purpose`, `level`, `rpe` | 그대로 | 목적별 완료율 같은 세분화. NULL 은 "미입력" 그대로 둔다 |
| `exercise_count` | 운동 행 수 | 완료율의 분모 |
| `done_exercise_count` | `is_done=1` 운동 수 | 완료율의 분자 |
| `exercise_completion_rate` | `done / count`, **count=0 이면 NULL** | 0/0 을 0% 로 두면 평균이 내려간다. NULL 은 SQL 의 `AVG` 가 자동으로 건너뛴다 |
| `has_exercise` | `exercise_count > 0` | "운동 없는 세션 비율" 보조 지표 |

**왜 세션 테이블에 운동 개수를 미리 넣나.** 완료율을 구할 때마다 운동 테이블과 조인하지 않게 하려는 것이다.
fact 에 "세션 단위로 의미 있는 숫자" 를 미리 계산해 두는 것이 Gold 의 일이다.

### 2-6. `fct_workout_exercise` — 운동 1행

grain: 삭제되지 않은 세션에 속한 운동 1개(dev 약 1,830).

| 컬럼 | 출처 | 이유 |
| -- | -- | -- |
| `exercise_row_id` (PK) | `id` | |
| `session_id` | `user_exercise_session_id` | `fct_workout_session` 으로 가는 키. `relationships` 테스트로 고아 행을 막는다 |
| `user_id`, `workout_date`, `is_outside` | 세션에서 가져온다 | 운동 단위 분석 때마다 세션과 조인하지 않게. fact 끼리 조인을 줄이는 흔한 방법이다 |
| `exercise_id`, `machine_id`, `round_number`, `weight_type` | 그대로 | 종목별·머신별 분석 |
| `is_done`, `done_at_kst` | 그대로 / 변환 | 종목별 완료율, 완료까지 걸린 시간 |

**왜 세션과 따로 두나.** "어떤 종목을 많이 하고, 어떤 종목을 자주 포기하나" 는 운동 단위 질문이다. 세션 테이블에
운동을 펼쳐 넣으면 세션 정보가 운동 수만큼 반복되고 세션 수를 셀 때 틀린다. grain 이 다르면 테이블을 나눈다.

### 2-7. `agg_daily_session_exercise_completion` — 날짜 1행 (PoC 지표)

| 컬럼 | 계산 |
| -- | -- |
| `workout_date` (PK) | `dim_date` 의 모든 날짜 |
| `session_count` | 세션 수 (없으면 0) |
| `active_user_count` | 그날 세션이 있는 회원 수 |
| `avg_exercise_completion_rate` | 그날 세션들의 `exercise_completion_rate` **평균** (NULL 제외) |
| `no_exercise_session_ratio` | `has_exercise = false` 비율 |
| `unfinished_session_ratio` | `is_finished = false` 비율 |

**"평균의 평균" 과 "전체 비율" 은 다르다.** 이 지표에서 가장 헷갈리는 부분이다.

- 세션 A: 운동 10개 중 10개 완료 → 100%
- 세션 B: 운동 2개 중 0개 완료 → 0%
- **세션당 평균**: (100% + 0%) / 2 = **50%** — 세션마다 한 표씩
- **전체 비율**: 10 / 12 = **83%** — 운동마다 한 표씩

dev 전체로는 세션당 평균 64.3%, 전체 비율 65.6%(1,200 / 1,830)다. 지표 이름이 "**세션당** 평균" 이므로 앞의 방식을
쓴다. "회원이 한 번 운동하러 와서 계획한 걸 얼마나 끝내나" 를 보는 지표라, 운동을 많이 하는 세션이 결과를 끌고
가지 않게 한다. 두 방식의 차이가 크면 PO 에게 함께 보여 줄 만하다.

### 2-8. `agg_user_workout` — 회원 1행

| 컬럼 | 계산 | 이유 |
| -- | -- | -- |
| `user_id` (PK) | | |
| `session_count` | 전체 세션 수 | 활동량 |
| `first_workout_date`, `last_workout_date` | 최소·최대 `workout_date` | 신규·이탈 판단의 재료 |
| `avg_exercise_completion_rate` | 회원 세션들의 평균 | 회원별 완료 성향 |
| `outside_session_ratio` | `is_outside` 비율 | 지점 밖 운동 비중 |

dev 회원 17명이라 지금은 작지만, 운영으로 가면 리텐션 분석의 출발점이 된다.

### 2-9. Silver → Gold 연결 (lineage)

```text
silver.user_exercise_session ──┬─► fct_workout_session ──┬─► agg_daily_session_exercise_completion ◄── dim_date
                               │          ▲              └─► agg_user_workout
silver.user_exercise_session_history ─────┤
                               └─────────► fct_workout_exercise
```

`fct_workout_session` 은 두 Silver 테이블을 모두 읽는다(운동 수를 세려고). `fct_workout_exercise` 는 세션에서
날짜·회원을 가져온다. 집계 테이블은 fact 만 읽고 Silver 를 직접 읽지 않는다 — 날짜·삭제 규칙이 fact 한 곳에만
있게 하려는 것이다.

### 2-10. 예시 — `fct_workout_session` 의 뼈대

```sql
with sessions as (
  select *
  from {{ source('silver_gymboxx', 'user_exercise_session') }}
  where is_deleted = 0
),
exercises as (
  select
    user_exercise_session_id as session_id,
    count(*) as exercise_count,
    countif(is_done = 1) as done_exercise_count
  from {{ source('silver_gymboxx', 'user_exercise_session_history') }}
  group by 1
)
select
  s.id as session_id,
  s.user_id,
  s.gym_id,
  s.gym_id is null as is_outside,
  date(coalesce(s.end_at, s.started_at, s.created_at), 'Asia/Seoul') as workout_date,
  datetime(s.started_at, 'Asia/Seoul') as started_at_kst,
  datetime(s.end_at, 'Asia/Seoul') as ended_at_kst,
  s.end_at is not null as is_finished,
  timestamp_diff(s.end_at, s.started_at, minute) as duration_minutes,
  s.purpose, s.level, s.rpe,
  coalesce(e.exercise_count, 0) as exercise_count,
  coalesce(e.done_exercise_count, 0) as done_exercise_count,
  safe_divide(e.done_exercise_count, e.exercise_count) as exercise_completion_rate,
  coalesce(e.exercise_count, 0) > 0 as has_exercise
from sessions s
left join exercises e on e.session_id = s.id
```

- `left join`: 운동이 0건인 세션(dev 169개)도 세션으로 남겨야 한다. `inner join` 이면 사라져 세션 수가 틀린다.
- `safe_divide`: 분모가 0 이거나 NULL 이면 에러 대신 NULL 을 돌려준다. 2-5 의 "0/0 은 NULL" 이 이 한 함수로 된다.
- `date(..., 'Asia/Seoul')`: UTC TIMESTAMP 를 KST 날짜로 자른다. 2-3 의 시간대 규칙이 여기서 적용된다.

## 3. 확인이 필요한 것

| 항목 | 왜 | 언제 |
| -- | -- | -- |
| `done_at`(datetime) 의 시간대 | 시간대 정보가 없는 타입이라 앱이 UTC/KST 중 무엇으로 쓰는지 코드로 확인해야 KST 변환이 맞다 | 2-2 설계 문서 전 |
| 날짜 규칙 3단계(`created_at` 대체) | 2-1 표는 2단계였다. PO 요청서에 추가 | 10/20 요청서 |
| 세션 `app_version`·`share_exported_at` | Silver 에 없다. 공유율·앱 버전 지표를 PoC 에 넣을지 | 2-2 전 |

## 참고

- data-warehouse `README.md` "BigQuery raw → Silver", `dbt/macros/cdc_current.sql`, `dbt/models/gymboxx/`
- platform-iac `docs/data-pipeline/2026-08-20-lake-bronze-s3-design.md` §4 — full ↔ cdc 경계
- [planing] `docs/datapipeline/plan/2026-10-19-gold-milestones.md` — 2-1 지표 정의, M2 Gold 설계
