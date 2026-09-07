# 최고 기록 종류 관리 방식 변경 명세 — 참조 테이블에서 enum으로

> 원천 문서: [04. 측정 방식](04_측정_방식.md) · [12. 개인 최고 기록 이력](12_개인_최고_기록_이력.md) · [14. 선택·변경된 사항](14_선택_변경된_사항.md) · [17. 테이블·컬럼 명세](17_테이블_컬럼_명세와_ERD_근거.md)
> 작성 2026-09-03
> 이 문서는 2026-08-21 "기록 종류를 참조 테이블로 관리" 결정을 뒤집는다.

## 1. 결정

|항목|종전(2026-08-21)|변경안|
|---|---|---|
|기록 종류 관리|`personal_record_type` 참조 테이블|이력 테이블의 `record_kind` enum|
|신설 테이블 수|2개(`personal_record_type` + 이력)|1개(이력만)|
|종목별 측정 방식 선언|`exercise.measure_type enum(3종)`|`exercise` 불리언 플래그 3종(`has_weight`·`has_duration`·`has_reps`)|
|종류별 표기명·단위·정렬|참조 테이블 컬럼|서버 상수 + 메타 API|
|종류별 유효 범위|참조 테이블 `min_value`/`max_value`|서버 상수(검증 전용·노출 안 함)|

### 변경 근거

**enum은 참조 테이블이 있어도 사라지지 않는다.** 서버는 종류마다 계산이 다르다 — 최고 중량은 `weight` 비교, 최고 반복 수는 `count` 비교, 단일 세트 최고 훈련량은 `weight × count` 비교다. 이 분기의 키가 코드 상수로 반드시 존재하고, 참조 테이블을 두면 그 테이블의 `code` 컬럼과 서버 상수를 다시 대조하게 된다. 즉 참조 테이블은 enum을 대체하는 선택지가 아니라 enum 위에 얹는 선택 레이어다. 얹을 이유가 생길 때 얹는다.

**성립 규칙은 플래그가 더 잘 담는다.** `personal_record_type.applies_to_measure` 는 enum 단일값이라 "무게도 있고 시간도 있는" 종목(웨이티드 플랭크 등)을 표현하지 못하고 AND 조건도 쓸 수 없다. 플래그 3종은 둘 다 된다. §12가 참조 테이블을 택한 가장 큰 근거가 이 항목이었으므로, 근거가 플래그 쪽으로 넘어갔다.

**"대량 테이블 열거형 확장 비용" 근거는 성립하지 않는다.** MySQL 8에서 enum 목록 **끝에** 값을 추가하는 것은 저장 크기가 바뀌지 않는 한(255개 이하 → 1바이트) 테이블 재구성 없이 INPLACE로 끝난다. 행 수와 거의 무관하다. §12에 적힌 이 근거는 삭제 대상이다.

**되돌릴 수 있는 결정이다.** 세트 이력이 전건 남아 있으므로 최고 기록 테이블은 파생 캐시다. 어느 형태를 골라도 세트에서 재계산해 다른 형태로 옮길 수 있다. 되돌리기 어려운 것은 세트 대리키와 무게 저장 정책뿐이며 둘은 이미 확정되어 있다(3장 참조).

## 2. 실측 — 계획 문서와 현재 스키마의 차이

개발 DB `gymboxx` 조회 (2026-09-03). **계획 문서가 여러 항목에서 이미 낡았다.**

|§|계획 문서의 안|개발 DB 실측|판정|
|---|---|---|---|
|4|`exercise.measure_type enum('WEIGHT_REPS','REPS','DURATION')` 신설|**컬럼 없음** · 대신 `has_weight tinyint NOT NULL`(기존) · `training_type enum('MUSCLE','CARDIO','MOBILITY')` · `weight_role enum('LOAD','ASSIST')` 신설됨|다른 방식으로 해결됨 · `measure_type` 신설 취소|
|4 부수|`count` 가 횟수·초 겸용이라 세트 단독 해석 불가|`duration_second int unsigned NULL` 분리 완료 · `count` 주석이 "횟수(시간 측정 종목은 `duration_second` 로 이관. **과거 행에는 초값이 그대로 잔존**)"|해결 · 단 과거 행 오염 잔존(8장)|
|9|`weight_unit enum('kg','lb')` + `weight_kg` 생성열 신설|`weight decimal(10,7)` 주석이 "중량(kg 고정. 입력 단위는 저장하지 않는다)"|정책으로 해결 · 컬럼 신설 불필요|
|10|`id` 대리키 · `performed_at` · `created_at` · `updated_at` 신설|`id int unsigned` · `done_at` · `created_at` · `updated_at` **모두 존재**|완료 · 시각 컬럼명은 `performed_at` 이 아니라 `done_at`|
|11|`user_exercise_set_history.rpe tinyint unsigned` 신설|컬럼 없음|미착수|
|12|`personal_record_type` + `user_personal_record_history` 신설|`%record%` 패턴 테이블 0건|미착수 · 본 문서로 형태 변경|

### 개발 DB 수치

|대상|값|
|---|---|
|`exercise`|275행 · `has_weight=1` 188 / `has_weight=0` 87|
|`exercise.weight_role`|**값 0건** — 컬럼만 있고 전 행 NULL|
|`exercise.unit`|`SET` 252 · `MINUTE` 23|
|`exercise.training_type`|`CARDIO` 13 · `MOBILITY` 7 · 나머지 `MUSCLE`|
|`user_exercise_set_history`|1,039행 · `count>0` 1,039 · `weight>0` 971 · `duration_second` 값 있음 38 · `done_at` 값 있음 **0**|

개발 DB는 표본이 작다. §12의 시작 종류 선정 근거였던 301,572행·95.8% 수치는 운영 기준이며, **운영 스키마와 분포는 이번에 확인하지 못했다**(접속 권한 거부 · 8장).

## 3. 신설·변경할 것

### 3-1. `exercise` — 플래그 2종 추가

`has_weight` 는 이미 있으므로 2개만 추가한다.

```sql
ALTER TABLE exercise
  ADD COLUMN has_duration tinyint(1) NOT NULL DEFAULT 0
    COMMENT '시간 측정 여부(세트의 duration_second 를 채우는 종목)' AFTER has_weight,
  ADD COLUMN has_reps tinyint(1) NOT NULL DEFAULT 0
    COMMENT '반복 수 측정 여부(세트의 count 를 횟수로 채우는 종목)' AFTER has_duration;
```

백필과 검수가 끝난 뒤 CHECK 제약을 건다.

```sql
ALTER TABLE exercise
  ADD CONSTRAINT chk_measure CHECK (has_weight + has_duration + has_reps >= 1);
```

이 제약이 플래그 전환의 **유일한 퇴보를 막는 장치**다. `measure_type` 은 `NOT NULL` 단일값이라 "아무것도 측정하지 않는 종목"이 구조적으로 불가능했으나, 불리언 3개로 쪼개면 셋 다 0인 행이 만들어진다. 그런 종목은 세트에 채울 값이 없고 최고 기록도 성립하지 않는다.

초기 부여는 `unit` 을 근거로 한다. 트레이너 검수 전 임시안이며 **이 문서 작성 중 실행하지 않았다.**

```sql
-- 검수 전 임시안 · 실행 보류
UPDATE exercise
   SET has_duration  = (unit = 'MINUTE'),
       has_reps = (unit = 'SET');
```

검수 지점 — `unit='MINUTE'` 23종 중 횟수도 세는 종목(인터벌·서킷 계열)이 있으면 두 플래그가 모두 1이 된다. 그 종목이 존재하는지가 6장 `MAX_SET_VOLUME` 정의의 전제다.

### 3-2. `user_personal_record_history` — 이력 테이블 신설

```sql
CREATE TABLE user_personal_record_history (
  id              bigint unsigned NOT NULL AUTO_INCREMENT,
  user_id         int unsigned    NOT NULL COMMENT '회원',
  exercise_id     int             NOT NULL COMMENT '종목',
  record_kind     enum('MAX_WEIGHT','MAX_REPS','MAX_SET_VOLUME','MAX_DURATION') NOT NULL
                  COMMENT '기록 종류 · 표기명·단위·유효 범위는 서버 상수가 규정',
  record_value    decimal(12,4)   NOT NULL COMMENT '기록 값 · 단위는 종류가 규정',
  weight          decimal(10,7)   NULL     COMMENT '근거 세트의 중량(kg)',
  reps            int unsigned    NULL     COMMENT '근거 세트의 횟수',
  duration_second int unsigned    NULL     COMMENT '근거 세트의 수행 시간(초)',
  source_set_id   int unsigned    NULL     COMMENT '근거 세트 · 초기 적재분은 NULL',
  achieved_at     timestamp       NOT NULL COMMENT '달성 시각',
  is_approximate  tinyint(1)      NOT NULL DEFAULT 0 COMMENT '달성 시각이 근사값인지',
  is_current      tinyint(1)      NOT NULL DEFAULT 1 COMMENT '현재 최고값 여부',
  created_at      timestamp       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  current_key     varchar(64) GENERATED ALWAYS AS
                    (IF(is_current = 1, CONCAT_WS('-', user_id, exercise_id, record_kind), NULL)) STORED
                  COMMENT '부분 고유 제약용 · 과거 행은 NULL이라 중복 허용',
  PRIMARY KEY (id),
  UNIQUE KEY uk_current (current_key),
  KEY idx_history (user_id, exercise_id, record_kind, achieved_at),
  KEY idx_rank (exercise_id, record_kind, is_current, record_value),
  CONSTRAINT fk_pr_user     FOREIGN KEY (user_id)       REFERENCES user (id),
  CONSTRAINT fk_pr_exercise FOREIGN KEY (exercise_id)   REFERENCES exercise (id),
  CONSTRAINT fk_pr_set      FOREIGN KEY (source_set_id) REFERENCES user_exercise_set_history (id)
) COMMENT='개인 최고 기록 이력 · 갱신은 기존 행 수정이 아니라 행 추가';
```

- `record_type_id` 외래키가 `record_kind` enum으로 바뀐 것이 참조 테이블 안과의 유일한 구조 차이다.
- `weight_kg` 를 `weight` 로 고친 이유 — 세트의 무게가 이미 kg 고정이라 환산 컬럼이라는 이름이 사실과 다르다.
- `duration_second` 를 추가한 이유 — 근거 세트가 시간 종목일 때 값을 남길 자리가 필요하다. 계획 문서에는 없었다.
- 갱신 시 이전 행의 `is_current` 를 0으로 내리고 새 행을 넣는다. `current_key` 가 NULL이 되어 고유 제약이 풀린다.
- `user.id` · `exercise.id` · `user_exercise_set_history.id` 의 실제 타입에 맞춰 위 자료형을 최종 확인해야 한다(8장).

### 3-3. 플래그 컬럼 명명 근거

`is_repeatable` 을 검토했으나 `has_reps` 로 정했다. 개발 DB 전수 조회(2026-09-03) 결과 이 스키마의 접두 관행이 갈려 있다.

|접두|건수|용례|의미|
|---|---|---|---|
|`has_`|4|`gym.has_shower_booth` · `gym.has_sportswear` · `trainer.has_pt_subscription` · `exercise.has_weight`|대상이 X를 **보유**한다|
|`is_`|42|`is_deleted` · `is_done` · `is_primary` · `is_read` · `is_required` …|대상의 **상태·분류**|

값 컬럼을 채우는지를 뜻하는 `is_` 컬럼은 한 건도 없다. 근거 세 가지.

1. `has_weight` 의 직계 형제다 — 같은 테이블·같은 역할(값 컬럼을 채우는가)·같은 축이므로 접두가 같아야 한다. `has_weight`·`is_repeatable`·`has_duration` 이 섞이면 세 컬럼이 한 축이라는 것이 이름에서 보이지 않는다.
2. `is_repeatable` 은 "세트를 여러 번 할 수 있는"으로 읽히고 그건 모든 운동에 해당한다. 실제 의미는 "횟수를 센다"이므로 `has_reps` 가 정확하다.
3. `is_` 를 값 보유에 쓰는 전례가 이 스키마에 없다.

남는 불일치 — 플래그는 `has_reps` 인데 세트의 값 컬럼은 `count` 다.

|플래그|세트 값 컬럼|일치|
|---|---|---|
|`has_weight`|`weight`|일치|
|`has_duration`|`duration_second`|일치(단위 접미는 값 컬럼에만 붙인다)|
|`has_reps`|`count`|**불일치**|

`has_count` 로 맞추지 않는 이유 — `count` 자체가 나쁜 이름이다. SQL 함수명과 겹쳐 조회마다 백틱이 필요하고, 과거에 횟수와 초를 겸용했던 이력이 붙은 이름이다. 그 이름을 플래그로 전파하는 대신 `count` → `reps` 개칭을 별건으로 남긴다(8장).

## 4. `record_kind` 값과 성립 조건

|`record_kind`|표기명|단위|성립 조건|비교 대상|
|---|---|---|---|---|
|`MAX_WEIGHT`|최고 중량|kg|`has_weight = 1`|세트 `weight`|
|`MAX_REPS`|최고 반복 수|회|`has_reps = 1`|세트 `count`|
|`MAX_SET_VOLUME`|단일 세트 최고 훈련량|kg·회|`has_weight = 1 AND has_reps = 1`|세트 `weight × count`|
|`MAX_DURATION`|최장 지속 시간|초|`has_duration = 1`|세트 `duration_second`|

성립 조건은 **DB가 강제하지 못한다.** MySQL CHECK 제약은 같은 행만 참조하므로 이력 테이블에서 `exercise` 의 플래그를 볼 수 없다. 서버 검증 + 주기 감사 쿼리로 막는다. 참조 테이블 안에서도 동일한 한계였다 — 외래키만으로는 "이 종목에 이 종류가 성립하는가"를 강제할 수 없다. 이 항목은 손실이 아니다.

감사 쿼리:

```sql
-- 성립하지 않는 종류로 쌓인 기록 검출
SELECT r.id, r.exercise_id, r.record_kind
  FROM user_personal_record_history r
  JOIN exercise e ON e.id = r.exercise_id
 WHERE (r.record_kind = 'MAX_WEIGHT'     AND e.has_weight = 0)
    OR (r.record_kind = 'MAX_REPS'       AND e.has_reps = 0)
    OR (r.record_kind = 'MAX_SET_VOLUME' AND (e.has_weight = 0 OR e.has_reps = 0))
    OR (r.record_kind = 'MAX_DURATION'   AND e.has_duration = 0);
```

## 5. 표기명·단위는 서버가 단일 출처

프론트에 표기 맵을 두지 않는다. 근거 두 가지.

**배포 경로** — 표기명 오타 하나를 고치는 데 프론트는 앱 심사와 사용자 업데이트가 걸리고, 서버는 배포 한 번으로 끝나며 구버전 앱에도 즉시 반영된다. 참조 테이블을 없애면서 잃는 "런타임 조정 가능"이 여기서 대부분 회복된다.

**소비자가 프론트만이 아니다** — 푸시 문구("최고 중량 갱신"), 주간·월간 리포트, 어드민, DW·BI 대시보드가 모두 표기명을 쓴다. 프론트 리소스에 두면 이 맵이 3~4곳에 복제되고 화면마다 다른 문구가 나온다.

```jsonc
// GET /v1/meta/personal-record-kinds  (앱은 캐시)
[
  { "code": "MAX_WEIGHT",     "label": "최고 중량",             "unit": "kg",    "sortOrder": 1 },
  { "code": "MAX_REPS",       "label": "최고 반복 수",          "unit": "회",    "sortOrder": 2 },
  { "code": "MAX_SET_VOLUME", "label": "단일 세트 최고 훈련량", "unit": "kg·회", "sortOrder": 3 },
  { "code": "MAX_DURATION",   "label": "최장 지속 시간",        "unit": "초",    "sortOrder": 4 }
]
```

기록 조회 응답은 `code` 만 내려보내고 프론트가 이 메타로 매핑한다. `sortOrder` 를 서버가 주면 화면마다 순서가 갈리지 않는다.

메타 API가 필요한 두 번째 이유는 **아직 달성하지 않은 종류의 빈 슬롯**이다. 개인 기록 화면에서 "최고 중량 — 기록 없음"을 보여주려면 이력에 없는 종류까지 알아야 하고, 기록 응답에 표기명을 인라인으로 끼워 넣는 방식으로는 이 화면이 만들어지지 않는다.

|메타|위치|
|---|---|
|`code`|enum — DB·API 계약|
|표기명 · 단위 · 정렬 순서|서버 상수 → 메타 API|
|성립 조건|`exercise` 플래그(DB)|
|유효 범위|서버 상수(검증 전용·노출 안 함)|
|프론트|표기명 보유 안 함 · 메타 응답 캐시|

## 6. 초기 적재

|단계|내용|
|---|---|
|대상|`user_exercise_set_history` 전건에서 회원×종목×종류별 최고값 1건씩|
|`achieved_at`|`done_at` 이 있으면 그 값 · 없으면 소속 세션의 `started_at` 으로 근사하고 `is_approximate = 1`|
|`source_set_id`|근거 세트의 `id` — 세트 대리키가 이미 있으므로 초기 적재분도 채울 수 있다(계획 문서는 NULL로 두기로 했으나 전제가 바뀌었다)|
|`is_current`|전부 1 — 초기 적재는 종류별 1건뿐|

**개발 DB `done_at` 이 0건이므로 사실상 전건이 근사값이 된다.** 클라이언트가 이 값을 전송하기 시작한 뒤에 적재하면 근사 비율이 줄어든다. 적재 시점 선택이 데이터 품질에 직접 영향을 준다.

`MAX_REPS` 적재에는 오염 위험이 있다. `count` 주석대로 **과거 행에는 초값이 그대로 남아 있어서**, `unit='MINUTE'` 종목의 과거 세트를 그대로 넣으면 "60초"가 "60회" 최고 기록으로 들어간다. 적재 쿼리에서 `has_reps = 1` 조건이 아니라 `has_duration = 0 AND has_reps = 1` 조건으로 걸러야 하고, 두 플래그가 모두 1인 종목은 과거 행을 아예 제외한다.

## 7. 나중에 참조 테이블이 필요해지는 조건

아래 중 하나라도 성립하면 그때 얹는다. 지금은 하나도 성립하지 않는다.

|조건|왜 그때는 필요한가|
|---|---|
|종류가 10종을 넘음|서버 상수 목록이 코드 리뷰로 관리하기 어려워지는 규모|
|유효 범위를 운영에서 조정해야 함|배포 없이 값을 바꿔야 하면 DB가 답|
|트레이너·기획이 종류를 직접 등록|어드민 화면이 붙으려면 행이어야 함|

마이그레이션 경로 — `personal_record_type` 을 신설하고 `code` 에 enum 값을 그대로 적재한 뒤, 이력 테이블에 `record_type_id` 를 추가해 병행 운영하다 전환한다. `record_kind` enum은 서버 분기 키로 남으므로 제거하지 않는다. 이력 데이터를 재적재할 필요가 없는 경로다.

## 8. 확인·결정이 남은 것

|항목|성격|없으면 막히는 것|
|---|---|---|
|운영 스키마 배포 상태|조사|이 문서의 실측이 전부 개발 DB 기준 · `duration_second`·`id`·`done_at` 이 운영에 있는지 미확인(접속 권한 거부) · 초기 적재 쿼리 확정 불가|
|`user.id` 등 FK 대상 컬럼 타입|조사|3-2 DDL의 자료형 확정 불가|
|`MAX_DURATION` 을 시작 종류에 포함할지|결정|§12는 "세트에 시간 컬럼이 없음"을 근거로 제외했으나 `duration_second` 가 생겨 근거가 소멸 · enum 끝 추가는 INPLACE라 나중에 넣어도 됨|
|`has_duration = 1 AND has_reps = 1` 종목의 존재 여부와 `MAX_SET_VOLUME` 정의|결정 · 트레이너 검수|3-1 백필 확정 불가 · 6장 적재 조건 확정 불가|
|`weight_role = 'ASSIST'` 종목의 `MAX_WEIGHT` 취급|결정|어시스트 장력은 부하가 아니라 부하 경감이므로 값이 클수록 약한 기록 · 값 0건이라 지금 결정 가능|
|`user_exercise_set_history.count` → `reps` 개칭|조사 · 별건|플래그(`has_reps`)와 값 컬럼(`count`) 이름 불일치가 지속 · 읽기·쓰기 앱 코드 전수 조사가 선행이며 §01 `exercise_function` 과 같은 성격의 작업|
|다국어 로드맵|결정|있으면 5장 결론이 바뀜 — 표기명이 프론트 i18n 리소스로 가고 서버 생성물만 서버 번역 리소스를 따로 갖는다|
|`exercise.unit`·`training_type`·`weight_role` 과 플래그 3종의 역할 정리|결정|축이 겹치는 컬럼이 5개가 되어 어느 것이 판정 근거인지 문서에 없는 상태가 지속|

## 9. 원천 문서에 반영할 것

|문서|고칠 것|
|---|---|
|[04. 측정 방식](04_측정_방식.md)|섹션 전면 교체 — `measure_type` 신설 취소 · 플래그 3종으로 대체 · `count`/`duration_second` 분리는 이미 완료됨을 반영|
|[12. 개인 최고 기록 이력](12_개인_최고_기록_이력.md)|참조 테이블 → enum · "선행 2 측정 방식 선언"을 플래그로 · 최장 지속 시간 제외 근거 삭제 · "대량 테이블 열거형 확장" 근거 삭제 · 정체 구간 근거 문장 정정(아래)|
|[13. 실행 순서와 의존 관계](13_실행_순서와_의존_관계.md)|강제 순서 §4 → §12 재서술 · §9·§10 완료 반영으로 권고 순서 4~6순위 갱신|
|[14. 선택·변경된 사항](14_선택_변경된_사항.md)|"최고 기록 종류 관리 방식" 행을 enum으로 뒤집고 근거 갱신 · `measure_type` 폐기 행 추가|
|[17. 테이블·컬럼 명세](17_테이블_컬럼_명세와_ERD_근거.md)|`personal_record_type` 명세 삭제 · 이력 테이블 명세 교체 · FK 목록에서 `record_type_id` 제거 · ERD 2 수정|

§12의 다음 문장은 **부정확하므로 정정 대상이다.**

> 갱신 방식을 수정으로 하면 목적이 사라짐 — 현재값만 남으면 달성 시점과 정체 기간을 알 수 없음

현재 최고값과 그 달성 시각이 있으면 "몇 주째 미갱신"은 계산된다. 이력이 실제로 필요한 것은 **기간 내에 달성한 최고 기록 수**(주간·월간 리포트의 "이번 달 달성한 최고 기록")이며, 이쪽은 현재값만으로는 산출되지 않는다.

`DB_구조_업그레이드_방안.md`(통합 원문)와 `99_원문_페이지별_보기.md` 는 PDF 원문 사본이므로 수정하지 않는다.

---

[목차](README.md)
