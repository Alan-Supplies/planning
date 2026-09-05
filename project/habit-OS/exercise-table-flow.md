# 운동 세션 — 테이블 변경 중심 흐름

> 범위: **출석(게이트 통과) → 부위 선택 → 운동 추천 생성(`POST /exercise-recommendation`) → 운동 종류 담기 → 세트 기록 → 운동 종료**
> 추천은 **생성(#18)** 만 다룬다 — 대체 추천(#19)과 만족도 설문(#20)은 이 흐름의 대상이 아니다.
> 기준 코드
> · 기록: [user-exercise.controller.ts](../src/modules/user-exercise/user-exercise.controller.ts) / [.service.ts](../src/modules/user-exercise/user-exercise.service.ts) / [.dao.ts](../src/modules/user-exercise/user-exercise.dao.ts)
> · 추천: [exercise-recommendation.service.ts](../src/modules/exercise-recommendation/exercise-recommendation.service.ts) / [.dao.ts](../src/modules/exercise-recommendation/exercise-recommendation.dao.ts) / [README.md](../src/modules/exercise-recommendation/README.md)
> · 설문: [survey.service.ts](../src/modules/survey/survey.service.ts) / [survey.dao.ts](../src/modules/survey/survey.dao.ts)
> 엔티티 원본: `node_modules/@suppliesfitness/gymboxx-lib/src/entity/`
> 스키마 상세는 [exercise-tables.md](./exercise-tables.md), 화면·API 호출 순서는 [exercise-flow.md](./exercise-flow.md) 참조

---

## 0. 등장 테이블 (그룹별)

### 출석

| 테이블 | 역할 | app-server 쓰기 |
|---|---|---|
| `access_history` | 출석(게이트 통과) 이력 | ❌ **읽기 전용** (외부 시스템이 INSERT) |
| `workout` | 레거시 운동부위 기록 | DELETE 만 (세션 생성 시 정리) |

### 운동기록

| 테이블 | 역할 | 쓰기 | 트리거 |
|---|---|---|---|
| `user_exercise_metadata` | 유저 운동 목적/레벨 (1행/유저) | UPSERT | 온보딩 설문 |
| `user_exercise_session` | 세션 헤더 (출석 ↔ 세션) | INSERT / UPDATE | 부위 확인, 시작·종료 PATCH |
| `user_exercise_session_body_part` | 세션 ↔ 선택 부위 | INSERT / DELETE | 부위 선택·수정 (**전체 교체**) |
| `user_exercise_session_history` | 세션에 담은 **운동 종류** | INSERT / UPDATE / DELETE | 담기·수정·순서변경·삭제 |
| `user_exercise_set_history` | 운동별 세트(횟수·중량) | INSERT / DELETE | 세트 저장 (**전체 교체**) |

### 추천

| 테이블 | 역할 | 쓰기 | 트리거 |
|---|---|---|---|
| `exercise_recommendation_log` | 추천 1회의 입력 스냅샷 | INSERT | `POST /exercise-recommendation` |
| `exercise_recommendation_log_body_part` | 그때 선택된 부위 | INSERT | 위와 동일 |
| `exercise_recommendation_log_exercise` | 그때 추천된 운동 | INSERT | 위와 동일 |

`survey_submit_id` 를 채우는 만족도 설문(#20)과 쓰기가 없는 대체 추천(#19)은 이 문서 범위 밖이다.

### 설문 (온보딩 — 추천 생성의 선행 조건)

| 테이블 | 역할 | 쓰기 |
|---|---|---|
| `user_survey_submit` | 온보딩 설문 제출 1건 | INSERT |
| `user_survey_submit_answer` | 답변 N건 | INSERT |
| `survey_v2` / `survey_question` / `survey_option` | 설문 정의 | ❌ 읽기 전용 |

### 마스터 (전 구간 읽기 전용)

| 테이블 | 이 플로우에서의 쓰임 |
|---|---|
| `exercise` | 운동 종류. `user_exercise_session_history.exercise_id` 의 대상 |
| `body_part` / `exercise_body_part` | 부위 목록, 운동↔부위 매핑 |
| `machine` / `exercise_machine` / `gym_machine` / `machine_brand` | 기구 후보 산출 (QR, 기구 선택 모달, 지점 보유 기구) |
| `exercise_function` | **추천 계산 전용** (기능성 태그) — 기록에는 남지 않는다 |
| `exercise_body_part_detail` / `body_part_detail` | **추천 계산 전용** (보조근 스코어링) |

### 핵심 규칙 4개

1. **출석 → 세션 → 운동 → 세트** 4단 계층. 상위 키 없이 하위 행은 생기지 않는다.
2. 조인·세트 테이블은 부분 갱신이 아니라 **DELETE ALL + INSERT(전체 교체)**.
3. 세션의 시각·스냅샷 컬럼(`started_at`, `end_at`, `rpe`, `level`, `purpose`)은 INSERT 시 비어 있고 **나중에 PATCH로 UPDATE** 된다.
4. **추천 로그와 운동기록은 서로를 참조하지 않는다.** 추천으로 담았는지 검색으로 담았는지 DB만 보고 알 수 없다.

---

## 1. 단계별 테이블 변경

### S0. 출석 (게이트 통과)

| 테이블 | 연산 |
|---|---|
| `access_history` | **INSERT 1건** — `user_id`, `gym_id`, `method`, `type`, `membership_type`, `barcode`, `created_at` |

**app-server 밖에서 일어난다.** 이 레포에는 `AccessHistoryEntity` 저장 코드가 없고 조회만 있다 ([dao:94](../src/modules/user-exercise/user-exercise.dao.ts#L94)).
이 행의 `id` = 앱의 `accessHistoryId` → 세션 생성의 필수 입력.

### S1. 온보딩 설문 — 추천의 선행 조건

`POST /user/{u}/exercise-session/survey/onboarding` (#9) — [service:160](../src/modules/user-exercise/user-exercise.service.ts#L160)

| 순서 | 테이블 | 연산 |
|---|---|---|
| 1 | `user_exercise_metadata` | **UPSERT** (`user_id` 충돌 기준 → `purpose`, `level`) |
| 2 | `user_survey_submit` | **INSERT 1건** |
| 3 | `user_survey_submit_answer` | **INSERT N건** |

세 개가 **한 트랜잭션**이다 — 설문 저장이 실패하면 메타데이터도 롤백된다.
답변에서 `purpose`/`level` 을 파싱해 넣는다(`parseUserExerciseMetadata`).

> 이 단계를 건너뛰면 **추천 #18 이 400 (`User exercise metadata is required`)** 으로 막힌다 ([service:180](../src/modules/exercise-recommendation/exercise-recommendation.service.ts#L180)). 기록 자체(세션 생성·운동 담기)는 메타데이터 없이도 된다.

### S2. 부위 선택 확인 — 세션 생성 / 부위 교체

**신규** `POST /user/{u}/exercise-session` (#10) — [service:272](../src/modules/user-exercise/user-exercise.service.ts#L272)

| 순서 | 테이블 | 연산 |
|---|---|---|
| 1 | `access_history` | SELECT (없으면 400 `Access history not found`) |
| 2 | `workout` | **DELETE** — 같은 `access_history_id` 의 레거시 행 ([dao:83](../src/modules/user-exercise/user-exercise.dao.ts#L83)) |
| 3 | `user_exercise_session` | **INSERT 1건** |
| 4 | `user_exercise_session_body_part` | **INSERT N건** (세션 cascade) |

```
user_exercise_session (INSERT)
  user_id            = 토큰 유저
  gym_id             = accessHistory.gym.id      ← 출석에서 복사 (컬럼 자체는 nullable)
  access_history_id  = body.access_history_id
  is_deleted         = 0
  created_at         = now (≈ 출석 시각)
  ─────── 이하 전부 비어 있음 ───────
  started_at  → 운동 시작 PATCH
  end_at      → 운동 종료 PATCH   ★ 종료 판정 컬럼
  rpe         → 강도 입력 PATCH
  level       → PATCH 시 user_exercise_metadata 에서 복사
  purpose     → PATCH 시 user_exercise_metadata 에서 복사
```

**기존 세션(부위만 수정)** `PUT .../exercise-session/{s}/body-part` (#11) — [dao:332](../src/modules/user-exercise/user-exercise.dao.ts#L332)

| 테이블 | 연산 |
|---|---|
| `user_exercise_session_body_part` | 트랜잭션: 해당 세션 행 **DELETE ALL → INSERT N건** |

`body_part_id_list` 가 빈 배열이면 **DELETE만** 하고 끝 → 부위 0개 세션. 세션 본체(`gym_id`, `access_history_id`)는 안 건드린다.

### S3. 추천 계산 — `POST /exercise-recommendation` (#18)

[service:44](../src/modules/exercise-recommendation/exercise-recommendation.service.ts#L44) → 계산은 `./recommendator` 파이프라인(필터 → 스코어러 → 얼로케이터 → 셀렉터)이 **전부 in-memory** 로 수행한다.

**읽는 테이블** — 파이프라인 입력을 한 번에 로드한다

| 테이블 | 로드 위치 | 쓰임 |
|---|---|---|
| `user_exercise_metadata` (+ `user`) | [dao:50](../src/modules/exercise-recommendation/exercise-recommendation.dao.ts#L50) | `purpose`, `level`, `gender` — 없으면 400 |
| `body_part` | [dao:37](../src/modules/exercise-recommendation/exercise-recommendation.dao.ts#L37) | `body_part_id` → `BODY_PART` 변환 (하나라도 못 찾으면 400) |
| `gym_machine` (ACTIVE) | [dao:69](../src/modules/exercise-recommendation/exercise-recommendation.dao.ts#L69) | 지점 보유 기구 id 집합 |
| `exercise` (ACTIVE) + relation 4종 | [dao:90](../src/modules/exercise-recommendation/exercise-recommendation.dao.ts#L90) | 후보 풀 전체 |
| ↳ `exercise_machine` | 같은 쿼리 | 보유 기구 매칭 필터 |
| ↳ `exercise_body_part` (+`body_part`) | 같은 쿼리 | 부위 매칭 / CARDIO 제외 |
| ↳ `exercise_function` | 같은 쿼리 | **기능성 풀 분리** + 목적 적합도 점수 |
| ↳ `exercise_body_part_detail` (+`body_part_detail`) | 같은 쿼리 | 보조근 점수 |
| `exercise` + `exercise_machine`/`machine`/`gym_machine`/`machine_brand` | `getGymExerciseList(gymId)` | 응답에 지점 기구 정보를 붙이는 2차 조회 |

`exercise_function` 은 여기서만 개입한다 — 태그(`FAT_LOSS`/`ENDURANCE`/`MOBILITY`/`BALANCE`/`RECOVERY`)가 1개 이상이면 일반 부위 풀에서 빼고 기능성 풀로 보내며([candidate-pool.filter.ts:67](../src/modules/exercise-recommendation/recommendator/filter/candidate-pool.filter.ts#L67)), 기능성 루틴 선정([functional-routine.selector.ts:115](../src/modules/exercise-recommendation/recommendator/selector/functional-routine.selector.ts#L115))과 목적 적합도 점수([functional-compatibility.scorer.ts:41](../src/modules/exercise-recommendation/recommendator/scorer/functional-compatibility.scorer.ts#L41))에 쓰인다.

**쓰는 테이블** — 계산이 끝난 뒤 로그 3건, 한 트랜잭션 ([dao:135](../src/modules/exercise-recommendation/exercise-recommendation.dao.ts#L135))

```
exercise_recommendation_log             INSERT 1건
  user_id, user_gender, user_level, user_purpose   ← 그 시점 스냅샷
  gym_id, available_time
  survey_submit_id = NULL                         ← 만족도 설문 제출 시 UPDATE
  created_at
exercise_recommendation_log_body_part   INSERT × 선택 부위 수   (복합 PK)
exercise_recommendation_log_exercise    INSERT × 추천 운동 수   (복합 PK)
```

응답의 `exercise_recommendation_log_id` 는 이후 만족도 설문(#20)에서만 쓰인다 — 이 흐름에서는 그 뒤를 따라가지 않는다.

> 대체 추천 `POST /exercise-recommendation/simple` (#19) 은 **쓰기가 전혀 없는 순수 조회**라 이 흐름에서는 제외한다. 로그를 남기는 추천은 #18 하나뿐이다.

**저장되지 않는 것** (추천 재현·분석의 한계)

| 항목 | 상태 |
|---|---|
| `seed` | ❌ 미저장. 없으면 `{userId}_{YYYYMMDDHHmmss}` 로 생성되지만 로그에 남지 않아 **결과 재현 불가** |
| 일반 루틴 / 기능성 루틴 구분 | ❌ `_log_exercise` 에 합쳐서 INSERT. 어느 루틴 소속인지 안 남는다 |
| 선정 근거 (기능성 태그, 점수, 세트/시간 배분) | ❌ 전부 미저장 |
| 어느 세션에서 추천받았는지 | ❌ `user_exercise_session_id` 컬럼 없음 |
| 추천 → 실제로 담았는지 | ❌ 연결 컬럼 없음. `user_exercise_session_history` 와 대조는 `exercise_id` + 시각 추정뿐 |

### S4. 운동 종류 담기 — `POST .../{s}/history` (#12)

QR 스캔 · 검색 추가 · 추천 결과 담기 · 운동 변경 — **4경로 전부 이 엔드포인트로 수렴**한다.
[service:431](../src/modules/user-exercise/user-exercise.service.ts#L431) → [dao:355](../src/modules/user-exercise/user-exercise.dao.ts#L355)

| 순서 | 테이블 | 연산 |
|---|---|---|
| 1 | `user_exercise_session` | SELECT (userId+sessionId 소유 검증, 없으면 400) |
| 2 | `user_exercise_session_history` | **INSERT N건** (`history_list` 길이만큼 한 번에) |

```
user_exercise_session_history (1건당)
  user_exercise_session_id = {s}
  exercise_id              = 선택한 운동 종류     ★ "운동 종류" 확정 지점
  round_number             = 클라이언트 계산값 (앱 로컬 순서 기준)
  weight_type              = 'kg' | 'lb' (EXERCISE_WEIGHT_TYPE)
  machine_id               = QR 경로는 확정 / 검색은 기구 1개일 때만 / 그 외 NULL
  ─────── 기본값 ───────
  is_done    = 0
  done_at    = NULL
  updated_at = NULL
  created_at = now
```

- 이 시점에 `user_exercise_set_history` 는 **한 건도 생기지 않는다.**
- 추천에서 담았더라도 **추천 로그와의 연결 컬럼은 없다.**
- `round_number` 중복/연속성을 서버가 검증하지 않는다.

### S5. 대시보드 편집 — 순서 변경 / 삭제 / 운동 변경

| 동작 | 테이블 연산 |
|---|---|
| 순서 변경 (#16) | `user_exercise_session_history.round_number` **일괄 UPDATE** (트랜잭션 + 세션 행 `pessimistic_write`) ([dao:426](../src/modules/user-exercise/user-exercise.dao.ts#L426)) |
| 삭제 (#17) | 트랜잭션: 세션 행 락 → `user_exercise_set_history` **DELETE** → `user_exercise_session_history` **DELETE** → 후순위 `round_number` **UPDATE(-1)** ([dao:489](../src/modules/user-exercise/user-exercise.dao.ts#L489)) |
| 운동 변경 | **INSERT(대체 운동) → DELETE(기존)** 순서. 앱이 두 API를 잇는 구조라 중간 실패 시 중복이 남는다 |

### S6. 세트 기록 · 운동 완료

| 동작 | 테이블 연산 |
|---|---|
| 기구 선택/해제, kg↔lb (#13) | `user_exercise_session_history` **부분 UPDATE** (`undefined` 필드 제거 후 UPDATE, 남는 게 없으면 쿼리 스킵) ([dao:462](../src/modules/user-exercise/user-exercise.dao.ts#L462)) |
| 세트 저장 (#14) | `user_exercise_set_history` 트랜잭션 **DELETE ALL → INSERT N건** ([dao:523](../src/modules/user-exercise/user-exercise.dao.ts#L523)) |
| 운동 완료 (#13) | `user_exercise_session_history` **UPDATE** `is_done`, `done_at` |

- 세트는 `(user_exercise_session_history_id, set_number)` 복합 PK. 하나만 고쳐도 전체 배열이 다시 올라와 **행이 새로 만들어진다.**
- `MINUTE` 단위 운동은 `weight = NULL`, `count` 가 **초 단위**.
- `done_at` 은 **클라이언트가 보낸 값만** 저장된다. 서버가 자동으로 찍지 않아 `is_done=1 & done_at=NULL` 이 가능하다 ([request.dto:85-102](../src/modules/user-exercise/dto/user-exercise.request.dto.ts#L85-L102)).

### S7. 운동 종료

앱의 **[운동 종료] 버튼**과 **DB 상 종료**가 분리되어 있다.

**S7-1. [운동 종료] 버튼 — 분기별 쓰기**

| 분기 | 테이블 변경 |
|---|---|
| 미완료 없음 | **쓰기 없음** (로컬 세션만 정리) |
| [완료하고 종료] | `user_exercise_session_history` **UPDATE × 미완료 수** (`is_done=1`). 운동마다 개별 PATCH 병렬 호출 → **각각 별개 트랜잭션**, 일부만 성공 가능 |
| [삭제하고 종료] | **쓰기 없음** — DELETE를 호출하지 않는다. 앱 표현은 "삭제"지만 `is_done=0` 행이 DB에 그대로 남는다 |

**S7-2. 강도(RPE) 입력 = 실제 종료** — `PATCH /user/{u}/exercise-session/{s}` ([service:327](../src/modules/user-exercise/user-exercise.service.ts#L327))

한 트랜잭션에서 `user_exercise_session` 을 **두 번 UPDATE**:

```
1) UPDATE rpe, end_at        ← 요청 바디 (전부 optional)
2) UPDATE level, purpose     ← user_exercise_metadata 재조회 후 복사
                               (메타데이터가 없으면 이 UPDATE 는 스킵)
```

- `end_at` 이 채워진 행이 "종료된 세션". 별도 상태 컬럼이 없다.
- `end_at` 은 **클라이언트가 보낸 시각** 그대로. 서버 시각으로 덮지 않는다.
- **멱등하지 않다** — 종료 여부를 검사하지 않아 재호출 시 `end_at`/`rpe` 가 덮어써진다.
- 순서 검증(`end_at > started_at`) 없음. DTO는 `@IsDateString()` + `rpe` 1~10 범위만 본다.
- 시작 PATCH와 종료 PATCH가 같은 경로라, 스냅샷(`level`/`purpose`)이 **종료 시점 값으로 다시 덮어써진다.**

**S7-3. 종료 시 하지 않는 일**

| 기대할 수 있는 처리 | 실제 |
|---|---|
| 총 운동시간·운동수·세트수·볼륨 저장 | ❌ 컬럼 없음. 조회 시 매번 계산 ([service:109-118](../src/modules/user-exercise/user-exercise.service.ts#L109-L118)) |
| 미완료 운동(`is_done=0`) 정리 | ❌ 그대로 남는다 |
| history 0건 빈 세션 정리 | ❌ 빈 세션도 종료된다 |
| `done_at` 보정 | ❌ 서버가 안 채운다 |
| `is_deleted` 활용 | ❌ 1로 바꾸는 코드가 없다 |
| 추천 로그와 결과 대조 | ❌ 연결 컬럼이 없어 불가 |
| 챌린지·배지·포인트 반영 | ❌ 없다. `UserExerciseSessionEntity` 참조는 `user`/`workout` 조회뿐 |
| 푸시·SQS 발행, 도메인 로그 | ❌ 없다 |

**종료는 세션 헤더 한 행의 UPDATE로 끝난다.** 뒤처리는 전부 조회 시점 계산에 맡겨져 있다.

---

## 2. 시간순 쓰기 타임라인

```
[게이트 통과]
  access_history                          INSERT   ← 외부 시스템

[온보딩 설문]  (추천 #18 의 선행 조건)
  user_exercise_metadata                  UPSERT  ┐
  user_survey_submit                      INSERT  ├ 한 트랜잭션
  user_survey_submit_answer               INSERT ×N ┘

[부위 선택 화면]
  (쓰기 없음 — body_part / recent 조회만)

[확인] · 신규
  workout                                 DELETE   같은 access_history_id
  user_exercise_session                   INSERT   시각·스냅샷 컬럼은 전부 NULL
  user_exercise_session_body_part         INSERT ×N (cascade)

[확인] · 기존 세션 (부위만 수정)
  user_exercise_session_body_part         DELETE ALL → INSERT ×N  (트랜잭션)

[운동 시작]
  user_exercise_session                   UPDATE   started_at
                                          UPDATE   level, purpose ← metadata 복사

[추천 생성]  POST /exercise-recommendation  (#18)
  ※ 입력 SELECT: user_exercise_metadata, body_part, gym_machine,
                 exercise + exercise_machine / exercise_body_part /
                 exercise_function / exercise_body_part_detail
  exercise_recommendation_log             INSERT 1건  (user_level·user_purpose 스냅샷)
  exercise_recommendation_log_body_part   INSERT ×N   ┐ 한 트랜잭션
  exercise_recommendation_log_exercise    INSERT ×N   ┘
  ※ seed·기능성 태그·루틴 구분·세션 연결은 저장되지 않는다

[운동 담기]  QR / 검색 / 추천 / 변경
  user_exercise_session_history           INSERT ×N   is_done=0, done_at=NULL, 세트 없음
                                          ※ 추천 로그와 연결하는 컬럼은 없다

[대시보드 편집]
  user_exercise_session_history           UPDATE round_number 일괄        (순서 변경)
  user_exercise_set_history               DELETE  →
  user_exercise_session_history           DELETE  →
  user_exercise_session_history           UPDATE round_number -1(후순위)  (삭제, 트랜잭션)

[운동 변경]  ※ 추가 → 삭제 순서
  user_exercise_session_history           INSERT (대체) → DELETE (기존) + round_number 보정

[상세 · 세트 입력]
  user_exercise_session_history           UPDATE machine_id / weight_type
  user_exercise_set_history               DELETE ALL → INSERT ×세트수   (반복)

[운동 완료 체크]  운동별
  user_exercise_session_history           UPDATE is_done, done_at

[운동 종료] 버튼
  · 미완료 없음      쓰기 없음
  · 완료하고 종료    user_exercise_session_history UPDATE × 미완료 수 (개별 트랜잭션)
  · 삭제하고 종료    쓰기 없음 — is_done=0 행이 그대로 남는다

[강도(RPE) 입력 = 실제 종료]
  user_exercise_session                   UPDATE rpe, end_at             ★
                                          UPDATE level, purpose (스냅샷 재적용)
  ※ 이후 정리 없음 — 집계 저장·미완료 정리·타 도메인 반영 전부 없다
```

---

## 3. 컬럼이 채워지는 시점

### `user_exercise_session`

| 컬럼 | INSERT (#10) | 시작 PATCH | 종료 PATCH (#15) |
|---|---|---|---|
| `user_id` / `access_history_id` / `gym_id` | ✅ | — | — |
| `created_at` (≈ 출석 시각) | ✅ | — | — |
| `is_deleted` | ✅ `0` | — | — |
| `started_at` | ❌ NULL | ✅ | — |
| `end_at` | ❌ NULL | — | ✅ ★ 종료 판정 |
| `rpe` | ❌ NULL | — | ✅ |
| `level` / `purpose` | ❌ NULL | ✅ (metadata 복사) | ✅ (덮어씀) |

### `user_exercise_session_history`

| 컬럼 | INSERT (#12) | PATCH (#13) | round-number (#16) | DELETE (#17) |
|---|---|---|---|---|
| `exercise_id` / `user_exercise_session_id` | ✅ | — | — | 행 삭제 |
| `round_number` | ✅ (앱 계산값) | — | ✅ | 후순위 -1 |
| `weight_type` | ✅ | ✅ (kg↔lb) | — | — |
| `machine_id` | 경로에 따라 ✅/NULL | ✅ (선택/해제) | — | — |
| `is_done` | ❌ `0` | ✅ | — | — |
| `done_at` | ❌ NULL | 클라이언트가 보낼 때만 ✅ | — | — |
| `updated_at` | ❌ NULL | ✅ (자동) | ✅ (자동) | — |

### `exercise_recommendation_log`

| 컬럼 | INSERT (#18) |
|---|---|
| `user_id` / `user_gender` / `user_level` / `user_purpose` | ✅ 그 시점 스냅샷 |
| `gym_id` / `available_time` | ✅ |
| `created_at` | ✅ |
| `survey_submit_id` | ❌ NULL (이후 만족도 설문에서 채워짐 — 범위 밖) |
| seed / 루틴 구분 / 점수 | 컬럼 자체가 없음 |

---

## 4. 트랜잭션 경계와 락

| 작업 | 트랜잭션 | 락 |
|---|---|---|
| 온보딩 설문 (#9) | ✅ metadata UPSERT + 설문 INSERT | — |
| 세션 생성 (#10) | ❌ **없음** — `workout` DELETE 와 세션 INSERT 가 각각 커밋 | — |
| 부위 교체 (#11) | ✅ DELETE + INSERT | — |
| 추천 생성 (#18) | ✅ 로그 3테이블 INSERT | — |
| 운동 담기 (#12) | ❌ (단일 `save` 배열) | — |
| 운동 PATCH (#13) | ❌ (단일 UPDATE) | — |
| 순서 변경 (#16) | ✅ | 세션 행 `pessimistic_write` |
| 운동 삭제 (#17) | ✅ 세트 DELETE → history DELETE → round_number 보정 | 세션 행 `pessimistic_write` |
| 세트 저장 (#14) | ✅ DELETE ALL + INSERT | — |
| 세션 PATCH (#15) | ✅ 본체 UPDATE + 스냅샷 UPDATE | — |

`round_number` 를 건드리는 경로(#16, #17)는 **모두 부모 세션 행을 `pessimistic_write` 로 먼저 잠근다** — 동시 수정 직렬화로 데드락을 피하는 의도적 설계다.

---

## 5. 제약 · 무결성 관찰

### 기록

| 대상 | 내용 |
|---|---|
| `user_exercise_session` | `access_history_id` 유니크 제약이 없고 서버도 기존 세션을 찾지 않는다 → 같은 출석에 **세션 여러 건 INSERT 가능**. "출석 1건 = 세션 1건"은 앱이 로컬 id를 기억해 지키는 규칙일 뿐 |
| `user_exercise_session` | 부위만 고르고 이탈하면 history 0건 **빈 세션**이 남는다. 정리 로직 없음 |
| `user_exercise_session` | `is_deleted` 를 1로 바꾸는 코드가 없다 (세션 삭제 경로 미구현) |
| `user_exercise_session_history` | `round_number` 유니크·연속성 미검증. 앱이 보낸 값을 그대로 INSERT |
| `user_exercise_session_history` | `is_done` 과 `done_at` 이 독립 → `is_done=1 & done_at=NULL` 가능 |
| `workout` DELETE | 세션 INSERT 와 트랜잭션이 분리되어, 세션 INSERT 실패 시 **레거시 기록만 지워진 상태**가 된다 |
| 소유권 검증 | #12~#17 은 모두 `getUserExerciseSessionById(userId, sessionId)` 로 소유 확인 (없으면 400) |
| 입력 방어 | `access_history_id` 가 `NaN`/미존재면 세션 생성에서 400 — 테이블에는 아무것도 남지 않는다 |

### 추천

| 대상 | 내용 |
|---|---|
| 재현성 | `seed` 가 로그에 없어 **같은 추천을 재현할 수 없다.** 미지정 시 `{userId}_{초단위시각}` 으로 생성 |
| 추적성 | 추천 로그 ↔ `user_exercise_session`/`_history` 를 잇는 컬럼이 없다 → "추천대로 운동했는가" 분석 불가 |
| 루틴 구분 | 일반/기능성 루틴을 `_log_exercise` 에 합쳐 넣어 구분이 사라진다 |
| 마스터 의존 | 추천 결과는 그 시점 `exercise`/`exercise_function`/`gym_machine` 상태에 의존한다. 마스터가 바뀌면 과거 추천의 근거를 복원할 수 없다 |
| 저장 실패 | 로그 3건은 한 트랜잭션이지만 **응답 직전에 저장**된다. 저장이 실패하면 계산까지 끝낸 추천이 응답 없이 버려진다 |

---

## 6. ERD (이 플로우 범위)

```
── 출석 · 기록 ──
access_history ─1:N─ user_exercise_session ─1:N─ user_exercise_session_history ─1:N─ user_exercise_set_history
      │                      │                          │        │
  (외부 INSERT)              │                      exercise   machine
      │                      └─1:N─ user_exercise_session_body_part ─N:1─ body_part
      │
      └─1:1─ workout (레거시, 세션 생성 시 DELETE)

user ─1:1─ user_exercise_metadata ──(세션 PATCH 시 값 복사)──> user_exercise_session.level / purpose

── 마스터 (읽기 전용) ──
exercise ─1:N─ exercise_body_part        ─N:1─ body_part
exercise ─1:N─ exercise_body_part_detail ─N:1─ body_part_detail   ← 추천 전용
exercise ─1:N─ exercise_machine          ─N:1─ machine ─1:N─ gym_machine
exercise ─1:N─ exercise_function (functional_tag)                 ← 추천 전용, 기록에 안 남음

── 추천 (기록 테이블과 연결 컬럼 없음) ──
exercise_recommendation_log ─1:N─ exercise_recommendation_log_exercise  ─N:1─ exercise
                            └1:N─ exercise_recommendation_log_body_part ─N:1─ body_part
   └ survey_submit_id → user_survey_submit  (만족도 설문 제출 시 채워짐, 범위 밖)

── 온보딩 설문 ──
user_survey_submit ─1:N─ user_survey_submit_answer     (+ user_exercise_metadata UPSERT 동반)
```
