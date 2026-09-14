# TECH-997 — 효과 축 · 추천 태그 분리 결정 기록

> 작성 2026-08-30 · 대상 [TECH-997](https://linear.app/suppliesfitness/issue/TECH-997)
> 원본 방안: `DB_구조_업그레이드_방안.md` §01 (같은 디렉토리)
>
> **이 문서의 역할** — 구현하며 내린 결정과 원본 방안 문서와 어긋난 지점을 남긴다.
> 원본 정본은 이 레포의 `docs/운동기록데이터화/DB_구조_업그레이드_방안.md` 이고,
> `_원본.md` 는 수정 전 백업이다.
>
> PR — lib [#260](https://github.com/suppliesfitness/gymboxx-lib/pull/260) · app-server [#705](https://github.com/suppliesfitness/gymboxx-app-server/pull/705) (둘 다 draft)

## 1. 추천 경로는 어느 테이블을 읽는가

**두 테이블을 모두 읽는다.** 배타 규칙은 계산 경로에만 성립하는 단방향이다.

| 경로 | `exercise_effect` | `exercise_recommend_tag` |
|---|---|---|
| 계산 — 목표 달성률 · 랭킹 · 리포트 | **읽는다 (유일한 출처)** | 읽지 않는다 |
| 추천 — `exercise-recommendation` 모듈 | **읽는다** | **읽는다** |

`exercise_recommend_tag` 는 "추천 **전용**" 이지만, 추천이 "`exercise_recommend_tag` 전용" 은 아니다.
이 비대칭을 놓치면 추천 기능이 깨진다.

### 근거 — 목적별 태그 매핑을 축으로 분해하면

`GOAL_TO_SPECIFIC_COMPATIBILITY` (app-server `constants/goal-to-specific-compatibility.constants.ts`)

| 회원 목적 | 매핑 태그 | 효과 축 | 추천 태그 |
|---|---|---|---|
| `WEIGHT_LOSS` 감량 | `FAT_LOSS` · `ENDURANCE` | `ENDURANCE` | `FAT_LOSS` |
| `STRENGTH_GAIN` 근력 증가 | `ENDURANCE` | `ENDURANCE` | — |
| `ENDURANCE_GAIN` 지구력 향상 | `ENDURANCE` · `BALANCE` | 둘 다 | — |
| `HEALTH_MANAGEMENT` 건강 관리 | `RECOVERY` · `MOBILITY` | `MOBILITY` | `RECOVERY` |
| `POSTURE_CORRECTION` 자세 교정 | `MOBILITY` · `BALANCE` | 둘 다 | — |
| `ATHLETIC_PERFORMANCE` 운동 능력 | `BALANCE` · `MOBILITY` · `ENDURANCE` | 셋 다 | — |

**6개 목적 중 4개는 효과 축 태그만으로 추천된다.** 추천을 `exercise_recommend_tag` 만 읽게 바꾸면
이 4개 목적의 기능성 루틴이 전부 빈 배열이 된다.

기능성 후보 풀 판정(§4.4)도 두 축을 본다 — 근력을 뺀 효과 축 **또는** 추천 태그 보유.

### 구현 위치

판정과 수집을 app-server `recommendator/exercise-tag.ts` 한 곳에 모았다.

```ts
export type ExerciseTag = EXERCISE_EFFECT_TAG | EXERCISE_RECOMMEND_TAG

collectEffectTags(exercise)      // exercise_effect      중 status='ACTIVE'
collectRecommendTags(exercise)   // exercise_recommend_tag 중 status='ACTIVE'
collectExerciseTags(exercise)    // 위 둘의 합집합 — 추천 경로가 쓰는 것
isFunctionalExercise(exercise)   // §4.4 기능성 풀 판정
```

신설 테이블에는 `status` 가 생겼으므로 **두 수집 함수 모두 `ACTIVE` 행만 읽는다.**
이관 전 `exercise_function` 에는 없던 조건이다.

## 2. 기능성 판정에서 `STRENGTH` 를 제외한다

이관 전 기능성 판정은 *"`exercise_function` 매핑 보유"* 였고 그 5종에 근력은 없었다.
이관 후 `STRENGTH` 는 150~230종 규모로 붙기 때문에, `exercise_effect` 보유 여부만 보면
거의 모든 운동이 기능성 풀로 들어가 일반 루틴이 비어버린다.

```ts
export const FUNCTIONAL_EFFECT_TAGS = [ENDURANCE, MOBILITY, BALANCE, PLYOMETRIC]  // STRENGTH 없음
```

근력을 뺀 이 집합이 이관 전 기능성 집합과 일치하므로 추천 결과는 이관 전후로 바뀌지 않는다.

`GOAL_TO_SPECIFIC_COMPATIBILITY` 도 매핑 내용을 그대로 뒀다. `STRENGTH_GAIN` 이 `ENDURANCE` 만
보는 기존 모양이 어색하지만, 여기에 `STRENGTH` 를 넣는 것은 추천 정책 변경이라 TECH-997 범위 밖이다.

## 3. 원본 방안 문서 §01 과 어긋난 지점

### (가) ✅ 근력 백필 대상 규칙 — **2026-08-31 반영 완료**

운영 DB 실측으로 방안 문서의 수치가 **그대로 재현되어** 규칙이 확정됐다. §5 참고.

| | 모집단 | 제외 | 결과 |
|---|---|---|---|
| **원본 문서 · 확정** | 근육 부위 라벨 보유 **253종** | 지구력 · 이완을 겸한 **28종** → 검수 대상 | **225종** 백필 |
| 최초 구현 (폐기) | 부위 라벨이 CARDIO · STRETCHING 이 아닌 ACTIVE 운동 | 없음 | dev 221종 |

겹함 28종을 자동 부여에서 빼는 것이 이 단계의 핵심이다. 스쿼트처럼 지구력·이완을 겸한 종목에
주 효과 판정 없이 근력을 붙이면, 유산소 시간이 부풀려지는 바로 그 문제(§01 「유산소 운동 시간
목표」)를 재생산한다. 최초 구현은 SQL 주석에 그 케이스를 반대로 *"근력에서 빠지는 경계 사례"*
로 적고 자동 부여했다 — 문서 쪽이 맞았다.

반영한 것 (`V4_30_0__exercise_function_split.sql` §4):

- 모집단을 `bp.part IN ('CHEST','BACK','SHOULDER','ARM','LEG','CORE')` 로 교체
- `ENDURANCE` · `MOBILITY` 겸함 28종을 `NOT IN` 으로 제외 → §6 검수 대상으로 이월
- **`BALANCE` 는 제외 조건이 아니다** — 균형만 가진 종목은 백필 대상이다.
  BALANCE 까지 빼면 224종이 되어 문서의 225종과 어긋난다 (운영 실측으로 확인)
- **부위 라벨을 id 범위가 아닌 이름으로 건다.** `body_part_id BETWEEN 1 AND 6` 은 대리키 순서에
  의미를 부여하는 방식이라 이관·재생성으로 조용히 깨진다 (방안 문서 §02 「주의」).
  §02(TECH-998) 의 `body_part.axis` 가 생기면 `axis = 'MUSCLE'` 로 교체한다
- 부위 매핑의 `status` 는 걸지 않는다 — 매핑이 비활성이어도 그 운동이 근력이라는 사실은
  변하지 않는다. 문서의 253종도 같은 기준이다
- 행의 `status` 는 §2 · §3 과 같이 운동 자신의 status 를 따른다 (운영 기준 36종이 INACTIVE)

### (나) ✅ DDL 3건 — **2026-08-31 반영 완료**

| | 반영값 (문서 기준) | 최초 구현 |
|---|---|---|
| `id` | `int unsigned` | `int` |
| `status` | `enum('ACTIVE','INACTIVE')` | `varchar(30)` |
| `updated_at` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE ...` | `NULL ON UPDATE ...` |

`varchar(30)` 은 기존 `exercise_body_part_detail` 컨벤션을 따른 것이었지만, TypeORM 엔티티가
이미 `type: 'enum', enum: STATUS` 라 문서 쪽이 엔티티와도 일치한다.
`id unsigned` 는 lib `17b0b4b` (마케팅 플레이스 순위 PK unsigned 추가) 의 선례와도 맞다.

🔴 **`exercise_id` 는 signed `int` 를 유지한다** — `exercise.id` 가 signed `int` 라 FK 정합상
필수다 (운영 `information_schema` 확인). 문서 DDL 도 `exercise_id int NOT NULL` 로 같다.
unsigned 로 바꾼 것은 PK 인 `id` 뿐이다.

엔티티의 `updated_at` 도 non-null 로 맞췄다 (snake · camel 4파일).

### (다) ✅ 원본 문서의 "어디에 쓰이는가" 표 — **2026-08-30 반영 완료**

원본 §01 이 `ENDURANCE` · `BALANCE` · `MOBILITY` 를 "계산" 으로만 적어, 추천도 이 셋을 쓴다는
사실이 드러나지 않았다. 그 표만 읽으면 "추천은 감량·회복만 쓴다" 로 읽힌다.

`DB_구조_업그레이드_방안.md` §01 에 반영한 것:

1. **"어디에 쓰이는가" 표 정정** — 지구력 "계산 + 추천(6개 목적 중 4개)" · 균형 · 이완 "계산 + 추천(3개 목적)" · 감량 · 회복 "추천 전용"
2. **FIG 2 표 보강** — 효과 축 셀에 "추천 경로도 이 테이블을 읽음" 추가
3. **`#### 경로별 읽기 규칙 — 배타는 계산 경로에만 성립하는 단방향` 절 신설** — 경로별 읽기 표 + 목적별 태그 매핑 축 분해 표 + "추천을 `exercise_recommend_tag` 만 읽게 바꾸면 4개 목적의 기능성 루틴이 빈 배열이 된다"

`<details>원문 페이지 N` 안의 PDF 원문 덤프는 원문 보존 영역이라 수정하지 않았다.
수정 전 백업은 `DB_구조_업그레이드_방안_원본.md` 다.

## 4. 그 외 원본 문서와 일치하는 결정

- 감량 · 회복을 한 테이블에 둔다 — 축은 다르지만 쓰이는 방식이 같고, 오늘 어떤 쿼리도 둘을 구별하지 않는다
- 생성 열 + 부분 고유 제약 — `UNIQUE(exercise_id, effect_tag, active_key)` 로 사용 중 1행 + 비활성 이력 여러 행 허용
  - `active_key` 는 `status='ACTIVE'` 일 때만 `1`, 그 밖에는 `NULL`. MySQL 의 `UNIQUE` 가 NULL 중복을 허용하는 성질을 쓴다
  - 앱이 쓰는 컬럼이 아니라 TypeORM 엔티티에는 매핑하지 않았다
- `is_primary` 는 효과 축에만 둔다 · `status` · `created_at` · `updated_at` 은 양쪽에 둔다
- 순발력 `PLYOMETRIC` 은 열거형에만 열어두고 행 삽입은 후순위
- `exercise_function` 은 이번에 제거하지 않는다 · 백업 테이블은 이후에도 유지
- 이관 SQL 을 "자동분(§1~§5)" 과 "검수 반영분(§6)" 으로 쪼갠다

## 5. 실측 — 기준은 **운영 DB**

방안 문서의 수치는 운영 기준이다. dev 는 데이터가 달라 재현되지 않는다
(dev: 운동 275종 · `exercise_function` 88행 · CARDIO 부위 8종).

### 운영 실측 (2026-08-31) — 문서 수치와 전부 일치

| 항목 | 운영 실측 | 문서 |
|---|---|---|
| `exercise` 전체 | **273종** | 273개 운동 ✓ |
| `exercise_function` 전체 | **87행** | 87행 ✓ |
| 태그 분포 | ENDURANCE 25 · BALANCE 20 · MOBILITY 18 · FAT_LOSS 14 · RECOVERY 10 | 동일 ✓ |
| 근육 부위 라벨(`CHEST`~`CORE`) 보유 | **253종** | 253종 ✓ |
| 지구력·이완 겸함 = 검수 대상 | **28종** | 28종 ✓ |
| 근력 백필 확정 | **225종** | 225종 ✓ |
| CARDIO **전용** | **13종** | 13종 ✓ (이슈의 "CARDIO 13종") |
| STRETCHING **전용** | **7종** | 7종 ✓ |
| 효과 축 이관 | **63행** | 63행 ✓ |
| 추천 태그 이관 | **24행** | 24행 ✓ |
| 이관 후 `exercise_effect` | **288행** (63 + 225) | "약 290행" ✓ |
| 백필 225종 중 운동이 INACTIVE | 36종 | — |

`exercise.id` 는 signed `int` (FK 정합 확인용).

### ⚠️ 원본 §02 의 "겹침 없이 분할" 은 사실과 다르다

§02 는 *"8종 라벨이 273개 운동을 **겹침 없이 분할**"* 하고, 표에 MODALITY 연결 운동을
"20종(13 + 7)" 으로 적었다. 운영 실측은 다르다.

| 축 | 라벨 | 연결 운동 (실측) | 전용 (다른 축 없음) |
|---|---|---|---|
| MUSCLE | 근육 부위 6종 | 253종 | 233종 |
| MODALITY | CARDIO | 18종 | **13종** |
| MODALITY | STRETCHING | 22종 | **7종** |

**두 축에 겹치는 운동이 20종 있다.** 253 + 40 − 20 = 273 으로 계산이 맞는다.
문서의 "20종(13 + 7)" 은 연결 운동이 아니라 **MODALITY 전용 종수**이고,
겹치는 20종은 253종 안에 이미 포함되어 있다.

TECH-997 에는 영향이 없다 — 백필 모집단이 "근육 부위 라벨 보유 253종" 이라 겹침 20종을
포함하는 것이 문서 수치와 맞다. 다만 **§02(TECH-998) 가 `axis='MUSCLE'` 로 부위 집계를
바꿀 때는 겹침 20종이 근육 부위 집계에 들어간다.** §02 가 기대한 "유산소 13종·스트레칭 7종이
부위 운동량에 섞이는 것을 축 조건 하나로 자동 제외" 는 전용 20종에만 성립하고,
겹침 20종은 여전히 남는다. → **TECH-998 쪽에서 확인이 필요하다.**

### dev / 운영 스키마 대조 (2026-08-31) — 운동 도메인은 일치

`sig` 는 `CONCAT(column_name,':',column_type)` 을 ordinal 순으로 이어 붙인 MD5 다.

| 테이블 | cols | dev = 운영 |
|---|---|---|
| `body_part` · `body_part_detail` | 4 · 5 | ✅ |
| `exercise` | 14 | ✅ |
| `exercise_body_part` · `exercise_body_part_detail` | 5 · 5 | ✅ |
| `exercise_function` · `exercise_machine` | 2 · 2 | ✅ |

MySQL 도 양쪽 **8.0.45** 다. 이 마이그레이션이 참조하는 테이블이 전부 같으므로
**dev 검증 결과를 운영에 적용할 수 있다.**

단, 두 가지는 다르다.

- **dev 에 생성 열이 0건**이다 (운영 1건 — `payment_card.favorite_user_id`).
  `V4_28_9` · `V4_28_14` 가 dev 에 반영되지 않았다. 운동 도메인과 무관해 이 작업에는 영향이 없지만,
  dev 검증이 **생성 열을 처음 만드는 시험**이 된다.
- **데이터는 다르다** — 스키마가 같다는 뜻이지 행이 같다는 뜻이 아니다.
  dev 검증에서 행수가 288/24 와 어긋나는 것은 정상이다.

## 6. 미결정 — 트레이너 · 기획 회신 대기

이관 SQL §6 에 주석으로 남겨둔 항목이다. 회신 전까지 자동분만 배포한다.

- [ ] `is_primary` 29종 지정 — 회신 전까지 전 행 `0`. 계산 경로가 아직 이 값을 읽지 않아 `0` 상태 배포는 동작 영향 없음
- [ ] "유산소 주 효과" 정의를 "부위 라벨 CARDIO 기준" 으로 문장 확정
- [ ] 효과 축 0개 7종 처리 방침 — `STRETCHING` 부위에 `MOBILITY` 를 줄지가 쟁점
- [ ] `PLYOMETRIC` 부여 대상 지정 (버피 · 점핑잭 · 스플릿 점프 등)
- [ ] §3 (가) 검수 대상(dev 25종 / 문서 28종) 의 주 효과 판정

## 7. 배포 순서

```
lib #260 머지 → 4.30.0 publish
  ↓
V4_30_0 마이그레이션 §1~§5 (자동분)
  ↓
app-server #705 — package-lock 갱신 후 머지 · 배포
  ↓
§6 검수 반영분 (별도 마이그레이션)
  ↓
exercise_function DROP (앱 코드 참조 0건 확인 후 · 백업 테이블 유지)
```

## 8. 작업 환경 메모

- **dev DB 접속은 VPN 필요** · VPN 연결 시 GitHub 레포 접근이 DNS 문제로 막힐 수 있다 (그때그때 확인)
- **기준 DB 는 운영이다** — 방안 문서의 모든 수치가 운영 기준이고 dev 에서는 재현되지 않는다
- 한글 파일명이 macOS 에서 NFD 로 저장되어 셸 글롭 · `find -name` 매칭이 불안정하다.
  이 디렉토리의 문서를 스크립트로 다룰 때는 `os.listdir` + `unicodedata.normalize` 로 경로를 해석한다
- 🔴 **같은 클론을 여러 세션이 공유한다** (회사 / 집). 2026-08-31 에 TECH-998 세션이 브랜치를
  옮겨둔 상태에서 TECH-997 커밋이 `feature/tech-998/exercise-mapping-constraints` 로 들어가
  push 된 사고가 있었다. **git 작업 전에 `git branch --show-current` 로 브랜치를 확인한다.**

## 9. 설계 판단 기록

구현하며 검토한 대안과 채택 근거다. 같은 질문이 다시 나왔을 때 재검토 비용을 줄이려고 남긴다.

### 9-1. `status` enum 인가, boolean 인가

**`status enum('ACTIVE','INACTIVE')` 유지.**

`status` 는 이 레포에서 사실상 표준어다 — 201개 테이블 중 **149개(74%)** 가 갖고 있고,
운동 도메인은 전부 `varchar(30) default 'ACTIVE'` 에 실제 값도 2개뿐이다.
"사용 여부를 나타내는 데 `status` 라는 이름이 맞나" 는 지적은 타당하지만, 이 테이블만 바꾸면
일관성만 잃는다. 그리고 `status` 를 3~4값으로 쓰는 테이블이 실재한다 —
`gym_acquisition_message`(DRAFT/RESERVED/SENT/CANCELED) ·
`membership_period_change_history`(WAITING_CONFIRMATION/CONFIRMED/REJECTED/INACTIVE).
즉 이 레포의 `status` 는 "사용 여부" 가 아니라 "상태 일반" 이고 2값은 그 특수 케이스다.

🔴 **결정적 이유는 따로 있다 — boolean 으로 바꿔도 생성 열이 그대로 필요하다.**
`UNIQUE(exercise_id, effect_tag, is_active)` 로는 `is_active=0` 인 행도 (운동, 축)당 1개로 제한되어
INACTIVE 이력 보존이 깨진다. 컬럼 수도 안 줄고 구조도 그대로다.

타입을 `enum` 으로 둔 것은 방안 문서 §01 명시 + 최근 테이블 추세(`event` V4_28_4 ·
`user_popup_confirmation` V4_28_8 가 enum) + 엔티티가 이미 `type: 'enum'` 이기 때문이다.
다만 운동 도메인 이웃 테이블은 전부 `varchar(30)` 이라 타입이 갈리는 것은 사실이다.

### 9-2. 왜 생성 열인가 — 코드로 흡수하면 안 되나

**생성 열 유지.** 앱 레벨 검증으로 대체할 수 없는 이유는 **동시성**이다.

```
요청 A: SELECT 중복 확인 → 없음
요청 B: SELECT 중복 확인 → 없음
요청 A: INSERT ✅
요청 B: INSERT ✅   ← ACTIVE 2행
```

락이나 격리 수준을 올려 막을 수는 있지만, 그럴 바엔 유니크 제약이 낫다.
이슈의 기대효과도 *"효과 축 조건이 **DB 제약으로 강제**된다"* 다.

> ⚠️ 처음에는 "마이그레이션 SQL 이 앱을 우회한다" 도 근거로 들었으나, 그건 **1회성 초기 적재**라
> 상시 제약을 정당화하는 논거로는 약하다. 남는 실질 근거는 동시성 하나다.

생성 열은 트릭이 아니라 **MySQL 관용구**다. PostgreSQL 은 `CREATE UNIQUE INDEX ... WHERE status='ACTIVE'`
한 줄이면 되지만 MySQL 은 부분 인덱스가 없다. 8.0.13+ 함수 인덱스도 내부적으로 숨은 생성 열을
만드는 것이라 본질이 같고, 스키마에 드러나지 않아 오히려 덜 명시적이다.

**이 레포에 이미 선례가 있다** — `payment_card.favorite_user_id` (TECH-787 · `V4_28_14`).

```sql
favorite_user_id INT GENERATED ALWAYS AS (
  CASE WHEN is_favorite = 1 AND status = 'ACTIVE' THEN user_id END
) STORED COMMENT 'is_favorite 유니크 강제용 생성 컬럼 (직접 쓰기 금지)',
ADD UNIQUE KEY uk_payment_card_favorite (favorite_user_id)
```

그 마이그레이션 주석이 같은 근거를 적고 있다 —
*"MySQL 8 은 부분 유니크 인덱스가 없어 생성 컬럼에 유니크 키를 건다."*

### 9-3. 검토했으나 채택하지 않은 대안 — 이력 테이블 분리

`exercise_effect` 는 ACTIVE 만 두고 이력은 `exercise_effect_history` 로 빼는 방식.

| 축 | 생성 열 (채택) | 이력 분리 |
|---|---|---|
| 테이블 | 1 | 2 |
| `UNIQUE` | 3컬럼 + 생성 열 | `(exercise_id, effect_tag)` 단순 |
| **현재 상태 조회** | `WHERE status='ACTIVE'` **필수** | 필터 불필요 |
| 해제 연산 | `UPDATE` 1회 | `DELETE` + history `INSERT`, 트랜잭션 |
| 이슈·문서 명시 | ✅ | ❌ |

**이력 분리가 나은 점이 하나 있다.** 방안 문서 §01 이 지적한 문제 —
*"조건을 손으로 옮겨 적고 한 곳이 빠지면 그 화면만 조용히 다른 숫자를 보여줌"* — 이
`status='ACTIVE'` 필터에도 똑같이 적용된다. 테이블을 나눠 놓고 같은 함정을 다시 만드는 셈이다.

→ **뷰로 덮는다.** 테이블을 늘리지 않고 같은 효과를 얻는다.

```sql
CREATE VIEW v_exercise_effect_active AS
SELECT * FROM exercise_effect WHERE status = 'ACTIVE';
```

계산 경로가 이 뷰만 읽으면 필터를 기억할 필요가 없다. (아직 만들지 않았다 — §6 참고)

### 9-4. `active_key` 를 엔티티에 매핑할 것인가 — **매핑함 (2026-08-31 결정)**

**"code base 를 진실의 원천으로 둔다"** 는 기준을 우선해 매핑했다.

```ts
@Column({
  type: 'tinyint',
  nullable: true,
  asExpression: "if(status = 'ACTIVE', 1, null)",
  generatedType: 'STORED',
  insert: false,
  update: false,
  select: false,
  comment: 'ACTIVE 행만 유니크 강제용 생성 열 (직접 쓰기 금지)',
})
active_key?: number | null
```

- `insert`·`update`·`select` **셋 다 false 가 필수**다. 빠뜨리면 TypeORM 이 INSERT 문에 컬럼을 넣고
  MySQL 이 `ERROR 3105` 로 거부한다
- TypeORM 0.2.45 는 `asExpression` · `generatedType` 을 지원한다 (`ColumnOptions.d.ts:116,120`)
- 선례인 `payment_card` 는 `favorite_user_id` 를 매핑하지 않았다. **이 결정은 선례와 다르다** —
  그쪽은 엔티티만 보면 생성 열의 존재조차 알 수 없어, 따라갈 선례라기보다 개선 대상으로 봤다
- 검토 과정에서 미매핑을 지지한 논거는 "생성식이 SQL 과 엔티티 두 곳에 존재하고, `synchronize` 를
  쓰지 않으므로 엔티티 쪽은 실행되지 않는 죽은 선언" 하나였다. **JSDoc 에 "정본은 SQL" 을 명시해
  완화**했다 — SQL 을 고치면 엔티티도 함께 고쳐야 한다는 것을 코드 옆에 적어뒀다

### 9-5. 엔티티 컬럼 코멘트

SQL 의 컬럼 코멘트를 TypeORM `comment` 옵션으로 옮겼다 (`b8408dd9`).
`gym_acquisition_migration`(17개) · `event`(12개) 등 최근 엔티티의 컨벤션을 따른 것으로,
lib 전체로는 187개 중 24개(13%)만 코멘트를 쓴다 — 최근 작업일수록 쓰는 추세다.

**테이블 코멘트는 옮기지 못했다.** TypeORM 0.2.45 의 `EntityOptions` 에 `comment` 가 없다
(0.3부터 지원). `@Entity` 에 코멘트를 쓴 선례가 레포에 하나도 없던 이유다.
클래스 JSDoc 에 그 사실을 명시했다.
