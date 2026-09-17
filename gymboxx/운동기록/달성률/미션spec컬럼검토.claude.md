# `user_mission.spec` 컬럼 설계 검토

| 항목 | 내용 |
| -- | -- |
| 상태 | **검토 중 — 확정 아님.** 확정되면 [결정기록.claude.md](결정기록.claude.md) 로 옮긴다 |
| 작성 | 2026-09-16 |
| 대상 | `user_mission` 이 "무엇을 세는 미션인지"를 담는 컬럼의 모양 |
| 관련 코드 | `src/modules/user-goal/` · `docs/달성률/목표테이블DDL.sql` |

---

## 0. 한 줄

미션 행에 **기계가 읽을 축**은 반드시 있어야 한다. 그러나 그것이 지금처럼 `simple-json` 한 덩어리일
이유는 없다. 아직 어느 환경에도 테이블이 나가지 않았으므로 **지금이 바꾸는 비용이 가장 싼 시점**이다.

## 1. 정해야 할 것은 셋이고, 서로 독립이다

섞어서 논의하면 답이 안 난다. 분리한다.

| | 질문 | 누가 답하나 |
| -- | -- | -- |
| **Q1** | 미션 행이 "무엇을 세는지"를 **DB에 어떤 모양으로** 담나 | 서버 단독 결정 가능 |
| **Q2** | 그중 **무엇을 클라에 내리나** | 앱 기획·프론트와 합의 필요 |
| **Q3** | 표시 문구(`name`)를 **누가 만드나** | Q2에 종속 |

Q1은 지금 결정할 수 있다. Q2는 [0% 카드 버튼 미결](#7-미결에-걸려-있는-것)에 막혀 있다.

## 2. 움직일 수 없는 제약

### 2-1. 재집계가 축을 요구한다

`user-mission-progress.dao.ts` 의 `sumNumerator` 는 **축에 따라 완전히 다른 SQL 5개**로 갈린다.
미션 행이 자기 축을 말해 주지 않으면 어떤 쿼리를 돌릴지 정할 수 없다. `name`("가슴 40세트분")은
표시용 원문이라 파싱 대상이 아니다.

| metricType | target | 단위 | 분자 |
| -- | -- | -- | -- |
| `BODY_PART_SET_EQUIVALENT` | `{ bodyPart }` | 세트분 | 세부부위 `load_ratio` 가중 세트 합 |
| `CARDIO_DURATION` | `null` | 분 | `training_type=CARDIO` 초 합 ÷ 60 |
| `STRETCHING_DURATION` | `{ bodyPart? }` | 분 | `training_type=MOBILITY` 초 합 ÷ 60 |
| `PRIMARY_EFFECT_SESSION` | `{ effect }` | 회(세션) | 주 효과 종목 포함 세션 수 |
| `ACTIVE_DAY` | `null` | 일 | 기록 있는 KST 날짜 수 |

### 2-2. 같은 부위가 서로 다른 축에 동시에 등장한다

자세교정 목표 하나가 아래를 **동시에** 갖는다.

```
등 세트분 · 어깨 세트분 · 코어 세트분      ← BODY_PART_PRIORITY 앞 3개
어깨 스트레칭 · 가슴 스트레칭               ← 전면 이완 고정
```

`어깨` 가 두 축에 걸린다. **따라서 축을 "부위" 하나로 표현할 수 없다.** 부위와 측정 방식을 함께
말하는 값이어야 한다. (가슴도 마찬가지 — 자세교정은 가슴 *근력* 을 일부러 빼지만 가슴 *스트레칭* 은 넣는다.)

### 2-3. 스트레칭 부위는 {없음, 어깨, 가슴} 으로 닫혀 있다

우연이 아니라 설계 결정이다 — [미션생성시스템_초안.md:352](미션생성시스템_초안.md#L352)
"자세 목적의 스트레칭 2개는 전면 이완 부위 고정(어깨·가슴 계열) · 다른 목적은 부위 파라미터 없이 전체 스트레칭".
따라서 조합을 유한하게 펼쳐도 안전하다.

### 2-4. 아직 아무 환경에도 나가지 않았다

[목표테이블DDL.sql](../달성률/목표테이블DDL.sql) 헤더 기준 **dev 미적용 · 운영 미적용**.
마이그레이션 부담 없이 컬럼을 바꿀 수 있는 마지막 구간이다.

## 3. 현재 구현(`spec` JSON)의 문제

| | 문제 | 근거 |
| -- | -- | -- |
| 1 | **`unit` 은 쓰기만 하고 읽는 곳이 0이다.** `metricType` 과 1:1이라 파생 가능 | 코드 전역에서 `spec.unit` 분기 없음. 도메인 로그도 `metric_type` 만 라벨로 쓴다 |
| 2 | **"대상 없음" 표기가 두 가지다.** 스트레칭은 `{}`, 유산소·`ACTIVE_DAY` 는 `null` | `user-mission-generator.service.ts:344` vs `:312`·`:443` |
| 3 | **조회가 안 된다.** 부위별 미션 분포, 축별 교체율 같은 운영·분석 쿼리를 `text` LIKE 로 해야 한다 | `spec text` (simple-json) |
| 4 | **스키마 검증이 없다.** 알 수 없는 `metricType` 이 들어오면 `switch` 가 미매치해 `undefined` 반환 → `current_value` 가 `NaN` 이 된다 | `sumNumerator` 에 default 절 없음 |

2번이 특히 나쁘다. 같은 뜻이 DB에 서로 다른 문자열로 들어가고 있으며, 타입만 그걸 가려 주고 있다.

## 4. 후보안

### A. 현행 유지 — `spec text` (simple-json)

- 장점: 변경 없음. 미래에 타깃이 2개 이상 필요한 축이 생겨도 스키마 변경 불필요
- 단점: §3의 네 가지 전부. 그리고 **현재 5종은 전부 타깃 키가 0~1개**라 그 유연성을 쓰고 있지 않다

### B. `metric_type` + `target` 두 컬럼

```sql
metric_type varchar(32) not null,   -- BODY_PART_SET_EQUIVALENT | CARDIO_DURATION | ...
target      varchar(32) null,       -- BODY_PART 또는 EXERCISE_EFFECT_TAG 값
```

- 장점: 조회·인덱스 가능. `unit` 제거. "없음"이 `null` 하나로 통일. 조합 자유도
- 단점: **불가능한 조합을 막지 못한다** (`CARDIO_DURATION` + `SHOULDER` 같은 행이 쓰일 수 있다).
  미션 카탈로그가 어디에도 명시되지 않아 "우리 미션이 무엇 무엇인가"를 한눈에 볼 수 없다

### C. `mission_code` 한 컬럼 + 코드 카탈로그  ← **권고**

조합을 유한하게 펼쳐 **12개 값**으로 닫는다.

```ts
enum MISSION_CODE {
  CHEST_SET = 'CHEST_SET',
  BACK_SET = 'BACK_SET',
  SHOULDER_SET = 'SHOULDER_SET',
  ARM_SET = 'ARM_SET',
  LEG_SET = 'LEG_SET',
  CORE_SET = 'CORE_SET',
  CARDIO_MINUTE = 'CARDIO_MINUTE',
  STRETCHING_MINUTE = 'STRETCHING_MINUTE',
  SHOULDER_STRETCHING_MINUTE = 'SHOULDER_STRETCHING_MINUTE',
  CHEST_STRETCHING_MINUTE = 'CHEST_STRETCHING_MINUTE',
  BALANCE_SESSION = 'BALANCE_SESSION',
  ACTIVE_DAY = 'ACTIVE_DAY',
}
```

- 장점: **불가능한 조합이 표현 불가능하다.** 미션 카탈로그 전체가 한 파일에서 리뷰된다
  (제품 관점에서 "우리 미션은 이 12개"가 보이는 것 자체가 값이다). 컬럼 하나라 인덱스·집계가 단순
- 단점 1: 쌍이 사라지지 않고 **코드로 옮겨간다.** SQL을 만들려면 카탈로그가 필요하다
- 단점 2: lib `BODY_PART` 에 부위가 늘면 enum + 카탈로그를 **수동으로** 따라가야 한다
- 단점 3: 부위별 집계를 SQL 단독으로 못 한다.
  ⚠️ **`code LIKE 'SHOULDER%'` 로 축을 복원하지 말 것** — 문자열 파싱은 카탈로그의 사본을 또 만든다.
  필요해지면 파생 `target` 컬럼을 추가한다

### 비교

| | A (JSON) | B (2컬럼) | C (코드 1컬럼) |
| -- | -- | -- | -- |
| 불가능한 조합 차단 | ❌ | ❌ | ✅ |
| 카탈로그 가시성 | ❌ | ❌ | ✅ |
| 조회·인덱스 | ❌ | ✅ | ✅ |
| 부위별 집계 SQL 단독 | ❌ | ✅ | ❌ (매핑 필요) |
| `unit` 중복 제거 | ❌ | ✅ | ✅ |
| 새 축 추가 비용 | 낮음 | 낮음 | 중간 (enum+카탈로그) |

## 5. C안을 고른다면

```sql
code          varchar(48)   not null comment '미션 축. MISSION_CODE 12종',
name          varchar(255)  not null comment '표시용 원문 (가슴 40세트분)',   -- §6 참조
current_value decimal(12,2) not null,
goal_value    decimal(12,2) not null,
status        varchar(20)   not null,
assigned_at   datetime      not null default current_timestamp,
```

카탈로그가 **유일한 정본**이 된다. 문구·단위·SQL 파라미터를 전부 여기서 파생한다.

```ts
const MISSION_CATALOG: Record<MISSION_CODE, {
  metricType: MetricType
  target: BODY_PART | EXERCISE_EFFECT_TAG | null
  unit: MissionUnit
  label: string   // '가슴' · '어깨 스트레칭'
}> = { ... }
```

enum 값은 **부위 이름이 아니라 (부위 × 방식)** 이어야 한다 — §2-2 때문이다. `CHEST` 라고만 쓰면
가슴 세트분인지 가슴 스트레칭인지 말하지 않는다.

`unit` 컬럼은 두지 않는다. `measure_type` 같은 별도 컬럼도 두지 않는다 — code에서 완전히 파생된다.

## 6. `name` 은 누가 만드나

`getMissionName(spec, goalValue)` 로 **완전히 파생**되므로 저장 자체가 선택이다.

| | 서버가 문구를 만든다 | 클라가 만든다 |
| -- | -- | -- |
| 변경점 | 서버 1곳 | iOS·AOS 각각, 앱 배포 대기 |
| 구버전 앱 | 모르는 code가 와도 글자는 뜬다 | 빈 카드가 된다 |
| 부분 스타일링 | ❌ 불투명한 한 줄. "가슴"만 색을 넣으려면 클라가 문자열을 파싱해야 한다 | ✅ 조각을 갖는다 |
| 카탈로그 위치 | 서버 | 클라 |

**결정 기준은 하나 — 디자인이 미션 카드를 축별로 다르게 그리는가.**

- 그린다(색·아이콘·전용 레이아웃) → 카탈로그를 **클라에 몰고** 서버는 `code` + 숫자만 내린다.
  색은 디자인 토큰이라 서버가 갖고 있으면 리디자인마다 서버 배포가 필요해진다
- 안 그린다 → 서버가 `name` 을 조립해 내린다

⚠️ **가장 나쁜 선택은 쪼개는 것이다.** 색은 클라가 갖고 문구는 서버가 가지면, 같은 카탈로그의 반쪽씩을
양쪽이 나눠 갖는다. 미션 하나를 추가할 때 서버·앱 배포가 둘 다 필요하고, 한쪽만 나가면
"색은 정해졌는데 문구가 없는" 행이 생긴다.

### `name` 을 DB에 저장할 이유는 약하다

`code` + `goal_value` 가 남아 있으면 교체된 과거 미션도 정확히 재현된다. 나중에 문구 규칙이 바뀌어
과거 행에 소급돼도 축과 값이 그대로라 거짓이 되지 않는다. 동결이 필요한 것은 `goal_value` 이고
**그건 이미 별도 컬럼이다.** 응답에서만 조립해도 된다.

## 7. 미결에 걸려 있는 것

Q2(무엇을 내리나)는 아래가 답해지기 전엔 닫히지 않는다.

> **0% 미션 카드의 버튼은 공통 기록 화면으로 가나, 그 미션 축에 맞는 종목 목록으로 가나?**

| 답 | 응답 계약 |
| -- | -- |
| 공통 화면 / 버튼 없음 | `code` 불필요 — `name` + 숫자 + `status` |
| 축별 종목 목록 | `code` 필요 — 클라가 모든 미션의 축을 알아야 한다 |

배경: 기획 문서에는 [미션달성률계산시스템.md:172](미션달성률계산시스템.md#L172)
"0% 상태 … 유산소는 기록 진입 버튼 직결" 한 줄뿐이고, **유산소만 특별 취급하는 근거가 없다.**
오히려 방향이 반대로 보인다 — 회원이 이해하기 어려운 쪽은 부위 세트분이다(`load_ratio` 가중이라
1세트 ≠ 1세트분이고, 1세트가 1세트분을 넘기도 한다). 유산소는 "뛴 시간 = 분"으로 가장 직관적이다.

**계약은 한 번 나가면 구버전 앱 때문에 줄이지 못한다. "혹시 몰라서" 넣지 않는다.**

## 8. 이 작업에서 같이 정리할 것

| | 항목 |
| -- | -- |
| 1 | **`ACTIVE_DAY` 가 반쪽이다** — DAO에 SQL이 있고 문구 조립도 있는데, baseline이 `throw` 라 생성되지 않는다(`user-mission-generator.service.ts:536-537`). 분모 규칙이 없다. enum에 값을 넣어도 **분모 산정 규칙을 정하지 않으면 여전히 못 만든다** |
| 2 | **`BODY_PART_TRAINING_VOLUME` 잔재** — [api.ts:145](api.ts#L145)에만 남아 있고 코드에는 0건. 설계 중 빠진 축으로 보인다. 정리 대상 |
| 3 | **`MISSON_NAME` 오타** — 검토 중이던 [scheme.ts](scheme.ts) 초안의 enum 이름. 확정 전에 `MISSION` 으로 |
| 4 | **`BODY_PART` 사본 금지** — lib `BODY_PART` 가 이미 `CHEST BACK SHOULDER ARM LEG CORE CARDIO STRETCHING` 8값을 갖는다. 부위 enum을 이 레포에 다시 만들지 않는다 (CLAUDE.md 규칙) |

## 9. 확정되면 할 일

1. `user-goal.types.ts` — `MissionSpec` 제거, `MISSION_CODE` + `MISSION_CATALOG` 도입
2. `user-mission.entity.ts` — `spec` → `code`
3. `목표테이블DDL.sql` — 컬럼 교체 (아직 미적용이므로 `create table` 본문 수정)
4. `user-mission-generator.service.ts` — baseline·교체·추가 로직이 `spec` 대신 `code` 로 중복 회피
5. `user-mission-progress.dao.ts` — `sumNumerator` 가 카탈로그에서 `metricType`·`target` 을 꺼내 분기
6. `user-goal.service.ts` — 응답 매퍼 (Q2 결론에 따라 `code` / `name` 중 무엇을 실을지)
7. 테스트 — `user-goal.service.spec.ts` · `user-mission-generator.service.spec.ts` ·
   `user-mission-progress.dao.spec.ts` · `test/user-goal/user-goal.e2e-spec.ts`
8. 도메인 로그 — `user_mission.completed` 의 `metric_type` 라벨을 유지할지 `code` 로 바꿀지.
   바꾸면 **README.md 도메인 로그 표도 같이 고친다** (CLAUDE.md 규칙)
