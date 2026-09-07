# 미션 생성·달성률 스키마 — draft

> 원천: [미션생성시스템.md](미션생성시스템.md) (PO 문서 전사본 · TECH-602) · 결정 이력은 [미션생선시스템_주의.md](미션생선시스템_주의.md)
> 기존 명세: [달성률_테이블_변경_명세.md](../달성률_테이블_변경_명세.md) — 마스터 데이터 쪽 변경은 그 문서가 정본
> 작성 2026-09-08 · **draft — 컬럼명·타입 미확정**

## 요약

`MemberMission` 검토 결과 **고쳐야 할 것 3개 · 채워야 할 것 3개**다.

| # | 항목 | 판단 |
|---|---|---|
| A | `status` 에 `REPLACED` | **제거** — 기각한 `archivedReason` 과 같은 컬럼이고, 활성/비활성 이분법을 깬다 |
| B | 축 파라미터 표현 불가 | **필드 추가** — 유산소 강도 · 스트레칭 부위를 `axisType`+`axisValue` 로 못 담는다 |
| C | `ATTENDANCE` 는 축이 아님 | `axisValue` **nullable** — §1-2 축은 3종, 출석은 축 목록에 없다 |
| D | 진행률 없음 | **테이블 분리 신설** — 교체 진입 조건(100% 도달) 판정 불가 |
| E | 100% 도달 시각 없음 | `reachedTargetAt` **추가** — 도달 시점 ≠ 교체 시점 |
| F | 산식 입력값 스냅샷 없음 | `perVisitAmount`·`frequencyFactor` **추가** — `targetVolume` 재현 불가 |

신설 테이블은 **9개** — 인스턴스 4 + 정의 1 + 상수 4.

---

## 1. `MemberMission` 검토

### A. `status: 'ACTIVE' | 'ARCHIVED' | 'REPLACED'` — `REPLACED` 제거

[주의 문서 6-1](미션생선시스템_주의.md)에서 `archivedReason` 을 기각한 근거가 그대로 적용된다. `status` 에 넣으면 이름만 바뀐 같은 컬럼이다.

넣으면 더 나빠지는 점이 하나 더 있다. **활성/비활성 이분법이 깨진다.**

```sql
-- REPLACED 를 두면 "종료된 미션"을 찾는 모든 쿼리가 2값 나열을 달고 다닌다
WHERE status IN ('ARCHIVED', 'REPLACED')
-- 값이 하나 늘 때마다 이 목록을 빠뜨린 쿼리가 조용히 틀린다
```

역산 방법은 이미 정해져 있다.

```sql
-- 같은 슬롯에 후속 회차가 있으면 교체, 자기가 마지막이면 목표 종료
SELECT m.*,
       CASE WHEN EXISTS (
         SELECT 1 FROM member_mission n
          WHERE n.goal_id = m.goal_id
            AND n.slot_index = m.slot_index
            AND n.slot_generation > m.slot_generation
       ) THEN 'REPLACED' ELSE 'GOAL_ENDED' END AS ended_reason
  FROM member_mission m
 WHERE m.status = 'ARCHIVED';
```

이 역산은 [주의 문서 7](미션생선시스템_주의.md)의 **소프트 삭제 확정**을 전제한다 — 행이 사라지면 근거가 없어진다.

### B. 축 파라미터 — `axisType` + `axisValue` 로 표현 불가한 미션이 있다

가장 큰 결함이다. [§1-3 볼륨 단위 5종](미션생성시스템.md#L87)은 단위마다 **축 값과 별개의 파라미터**를 정의한다.

| 단위 | 파라미터 (원문) | `axisValue` 로 되나 |
|---|---|---|
| 세트분 | 부위 6종 | ✅ |
| 총 훈련량(kg) | 부위 6종 | ✅ |
| 분 — 유산소 | **강도(중강도 · 고강도 · 무관)** | ❌ |
| 분 — 스트레칭 | **부위(선택)** | ❌ |
| 회(세션) | 효과 값 | ✅ |
| 일 | 없음 | — (C 참조) |

깨지는 케이스 두 개.

1. **유산소 강도** — 원문 표기 예가 `유산소 280분` 과 `고강도 유산소 90분` 두 종류다. 둘 다 `axisType='MODALITY', axisValue='CARDIO'` 라서 구분이 사라진다.
2. **자세 목적 스트레칭** — [§7-5](미션생성시스템.md#L1069)가 "스트레칭 2개는 전면 이완 부위 고정(어깨·가슴 계열)"이다. **성격 축 + 부위 파라미터가 동시에** 필요해 한 쌍으로는 안 된다.

→ `intensity`, `bodyPartParam` 을 명시 필드로 추가한다. 파라미터가 정확히 이 두 개뿐이므로 `axisParams: json` 보다 명시 컬럼이 낫다 — 검증·인덱스·조회가 다 쉬워진다.

### C. `ATTENDANCE` 는 축이 아니다

[§1-2](미션생성시스템.md#L43)의 축은 **3종**이다 — 운동 효과 · 운동 부위 · 운동 성격. 출석은 축 목록에 없고, [§1-3](미션생성시스템.md#L87)에서 단위 "일"의 파라미터가 **"없음"**, [§9 규칙 6](미션생성시스템.md#L1145)이 "출석형 미션은 범용 폴백 세트에만 · 최소 사용"이다.

`axisType` 에 넣는 것 자체는 실용적이다(미션 종류 판별자가 한 컬럼으로 모임). 다만 **`axisValue` 가 반드시 nullable** 이어야 하고, 축이 아니라는 사실이 코드에 남아야 한다.

### D. 진행률이 없다 — 별 테이블로 신설

[§2-1](미션생성시스템.md#L177) 교체 진입 조건이 "그 미션이 100% 도달 + 사용자가 새 미션 받기 선택"이다. `targetVolume` 만 있으면 **도달 여부를 판정할 수 없다.**

두 가지 성질을 같이 봐야 한다.

- **초과 허용** — [§2](미션생성시스템.md#L215) "100%에 닿고도 교체하지 않으면 초과율을 계속 올리며 유지" → `currentVolume > targetVolume` 이 정상 상태
- **쓰기 주기가 다르다** — 미션 본체는 할당 시점에 고정되는 불변 스냅샷, 진행률은 운동완료마다 갱신

→ **분리 권고.** 본체를 불변으로 두면 스냅샷 원칙([§3](미션생선시스템_주의.md))이 스키마로 강제된다. 단순화가 우선이면 `MemberMission.currentVolume` 한 컬럼도 성립하나, 그러면 본체 행이 계속 갱신돼 "스냅샷 테이블"이라는 성질을 잃는다.

`progressRate` 는 **저장하지 않는다** — `currentVolume / targetVolume` 파생이고, A와 같은 이유다.

### E. 100% 도달 시각이 필요하다

**자동 교체가 없다**([§2-1](미션생성시스템.md#L193) "닫는 판단은 사용자가 함"). 그래서 100% 도달 시점과 아카이브 시점이 다르고, 그 사이 간격이 얼마든 벌어질 수 있다. `archivedAt` 만으로는 "언제 채웠나"를 알 수 없어 달성 통계가 안 나온다.

→ `reachedTargetAt` 추가. 최초 도달 시점만 기록하고 이후 갱신하지 않는다.

### F. 산식 입력값 스냅샷이 없다

[§6](미션생성시스템.md#L786) `볼륨 = per_visit_amount × 10 × frequency_factor`. `targetVolume=40` 만 남기면 **"왜 40세트분인가"를 나중에 설명할 수 없다** — 기준 운동량 테이블은 실측으로 갱신되는 값이라 사후 재현이 불가능하다.

→ `perVisitAmount`, `frequencyFactor` 를 같이 복사 저장. 스냅샷 원칙의 취지가 원래 이것이다.

### 그 외

| 항목 | 의견 |
|---|---|
| `unit` 5종 | [§1-3](미션생성시스템.md#L87)과 **정확히 일치** ✅ (분이 유산소·스트레칭으로 나뉘어 표는 6줄이지만 단위는 `MINUTE` 하나) |
| `unit` 저장 필요성 | 현재는 `(axisType, axisValue)` 에서 파생 가능하다(BODY_PART→SET 유일). 다만 `KG_VOLUME` 개방 시 부위 축에 2택이 생기므로([§9-2](미션생성시스템.md#L1239)) 저장이 맞다 |
| `templateId` | [§3](미션생선시스템_주의.md) 대로 **추적용 FK만**. 조회 로직에서 조인해 현재값을 읽지 않도록 컬럼 주석에 명기 |
| `slotIndex: 1\|2\|3\|4\|5` | DDL 에서는 `tinyint` + `CHECK (slot_index BETWEEN 1 AND 5)`. 리터럴 유니온은 TS 레벨에서만 |
| `id: string` | ULID 권고 — 생성 시각 순 정렬이 되어 `slotGeneration` 이력 조회에 유리 |

---

## 2. `MemberMission` 수정본

```ts
MemberMission {
  id: string;
  goalId: string;
  slotIndex: 1 | 2 | 3 | 4 | 5;
  slotGeneration: number;      // 1부터 · 이력 카운터 + 종료 사유 역산 + 결정성 시드
                               // 로테이션 인덱스 아님(주의 6-2) · 볼륨 계수 아님(주의 8)
  templateId: string;          // 추적용 FK만 — 조회 시 조인 금지 (주의 3)

  // 축 — §1-2 축 3종 + 출석(축 아님, 주의 C)
  axisType: 'BODY_PART' | 'EFFECT' | 'MODALITY' | 'ATTENDANCE';
  axisValue?: string;          // ATTENDANCE 는 null
  intensity?: 'MODERATE' | 'VIGOROUS';  // MODALITY=CARDIO 전용 · null = 강도 무관 (§1-3)
  bodyPartParam?: string;      // MODALITY=STRETCHING 전용 · 자세 목적 전면 이완 (§7-5)

  // 볼륨 — 할당 시점 스냅샷 (§6)
  unit: 'SET' | 'KG_VOLUME' | 'MINUTE' | 'SESSION' | 'DAY';
  targetVolume: number;
  perVisitAmount: number;      // 산식 입력값 스냅샷 — targetVolume 재현용
  frequencyFactor: number;

  status: 'ACTIVE' | 'ARCHIVED';  // 단방향 — ARCHIVED → ACTIVE 경로 없음
                                  // 종료 사유는 후속 회차 존재 여부로 역산 (주의 6-1)
  reachedTargetAt?: Date;      // 100% 최초 도달 · 교체 시점과 다름 (§2-1)
  archivedAt?: Date;
  createdAt: Date;
}
```

---

## 3. 나머지 테이블 draft

### 3-1. `MemberGoal` — 회원 목표

```ts
MemberGoal {
  id: string;
  userId: string;

  phraseId?: string;           // 목표 문구 40종 FK · "기타 직접 작성" 시 null
  freeText?: string;           // 기타 작성 원문
  purpose: 'DIET' | 'STRENGTH' | 'HEALTH' | 'FITNESS' | 'POSTURE';
  purposeSource: 'PHRASE' | 'RULE_CLASSIFIED';   // 기타는 룰 베이스 분류 (§3 · §10)

  // 생성 파라미터 스냅샷 — 회원 정보는 변하므로 목표 단위로 고정
  ageBandSnapshot: string;     // 10~20대 · 30대 · 40대 · 50대+ (§5-1)
  genderSnapshot: 'M' | 'F';

  status: 'ACTIVE' | 'COMPLETED' | 'ARCHIVED';   // 삭제 = ARCHIVED · 하드 삭제 없음 (주의 7)
  startedAt: Date;
  completedAt?: Date;
  archivedAt?: Date;
}
```

- **연령대·성별을 스냅샷하는 이유** — 부위 우선순위 목록이 `목적 × 성별` 로 분기하고([§7-2](미션생성시스템.md#L937)) 기준 운동량이 `연령대 × 성별` 이다([§5-1](미션생성시스템.md#L354)). 회원 정보를 라이브로 읽으면 생일이 지나는 순간 진행 중 목표의 로테이션 목록이 바뀔 수 있다.
- **"불러오기" 필드 없음** — [주의 문서 4](미션생선시스템_주의.md)에서 기능 자체를 없애기로 확정했다.

### 3-2. `MemberMissionProgress` — 진행률

```ts
MemberMissionProgress {
  missionId: string;           // PK · MemberMission 과 1:1
  currentVolume: number;       // targetVolume 초과 가능 (§2 초과율)
  lastAppliedAt: Date;         // 마지막으로 반영된 이벤트 시각
  updatedAt: Date;
}
```

`progressRate` 는 저장하지 않는다(1-D). 정렬·필터 성능이 문제가 되면 그때 생성 컬럼으로 추가.

### 3-3. `MissionProgressLedger` — 반영 원장 **(가정 — ③ 문서 미확인)**

```ts
MissionProgressLedger {
  id: string;
  missionId: string;
  sourceType: 'SET' | 'SESSION' | 'ACCESS';   // 세트 / 세션 / 출입
  sourceId: string;
  deltaVolume: number;
  occurredAt: Date;            // KST 일자 판정 기준
  appliedAt: Date;
}
// UNIQUE (missionId, sourceType, sourceId)  ← 멱등키
```

**이 테이블은 전부 가정이다.** "미션 달성률 계산 시스템"(③) 문서를 아직 못 봤고, 운동완료 → 미션 매칭 방식과 멱등키가 [주의 문서 9](미션생선시스템_주의.md)의 유일한 미결 항목이다. 확인 후 재작성 대상.

걸리는 점 하나 — [기존 명세 §7](../달성률_테이블_변경_명세.md)이 `user_exercise_set_history` 에 **수행 시각 컬럼이 없다**고 확인했다. `occurredAt` 을 세트 단위로 채울 수 없어 세션 `started_at` 대용이 된다.

### 3-4. `MissionTemplate` — 축·개수 정의

```ts
MissionTemplate {
  id: string;
  purpose: 'DIET' | 'STRENGTH' | 'HEALTH' | 'FITNESS' | 'POSTURE';
  gender?: 'M' | 'F';          // null = 공용 (체력 · 자세는 성별 동일 §7-2)

  axisType: 'BODY_PART' | 'EFFECT' | 'MODALITY' | 'ATTENDANCE';
  axisValueRule: 'ROTATION' | 'FIXED';   // 부위 = 로테이션 · 유산소/스트레칭 = 고정
  axisValue?: string;          // FIXED 일 때만
  intensity?: 'MODERATE' | 'VIGOROUS';
  bodyPartParam?: string;
  unit: 'SET' | 'KG_VOLUME' | 'MINUTE' | 'SESSION' | 'DAY';

  slotCount: number;           // 이 템플릿이 차지하는 슬롯 개수 (§7-1 개수 배분)
  isFallbackOnly: boolean;     // 출석형 = 범용 폴백 세트 전용 (§9 규칙 6)
}
```

**볼륨 컬럼이 없다** — [주의 문서 5](미션생선시스템_주의.md)대로 템플릿은 축/개수 정의 수준이고, 볼륨은 할당 시점에 §6 공식으로 매번 계산한다.

### 3-5. 상수 테이블 — 4개

[§5](미션생성시스템.md#L350)가 "DB 마스터 테이블 또는 코드 내 상수 · 어느 쪽이든 값 변경이 규칙 코드 수정을 요구하지 않아야 함"이라 했다. 성질에 따라 갈린다.

| 테이블 | 내용 | 위치 권고 | 근거 |
|---|---|---|---|
| `MissionBaselineVolume` | 연령대 × 성별 × 유형 → `per_visit_amount` | **DB** | 실측으로 갱신되는 값 ([L1143](미션생성시스템.md#L1143)) |
| `MissionFrequencyFactor` | 유형 → `frequency_factor` | **DB** | 습관 관측치 · 갱신 여지 |
| `MissionCompositionRule` | 목적 × 성별 → 유형별 개수 | 코드 상수 | [§7-1](미션생성시스템.md#L835) · 문헌 근거 · 변경 = 정책 변경 |
| `MissionBodyPartPriority` | 목적 × 성별 → 부위 순서 | 코드 상수 | [§7-2](미션생성시스템.md#L937) · 변경에 배포 마찰이 있는 게 낫다 |

```ts
MissionBaselineVolume {
  ageBand: string;             // 10~20대 · 30대 · 40대 · 50대+
  gender: 'M' | 'F';
  metricType: string;          // 미션 유형 8종 — 부위 6 + 유산소 + 스트레칭
  targetParam?: string;
  perVisitAmount: number;
}
// PK (ageBand, gender, metricType, targetParam)  ← 8 세그먼트 × 8 유형

MissionFrequencyFactor {
  metricType: string;          // 가슴·등·하체 0.35 / 어깨·팔 0.30 / 코어 0.40 / 유산소 0.80 / 스트레칭 0.50
  factor: number;
}
// PK (metricType)
```

**`frequency_factor` 를 기준 운동량 테이블에서 뺐다.** 원문 [§5-1](미션생성시스템.md#L354)은 두 값을 한 테이블에 두는데, [§5-2](미션생성시스템.md#L630)가 **"세그먼트 무관 · 유형별 고정"**이라고 명시한다. 한 테이블에 두면 같은 계수가 8세그먼트에 8번 중복되고 갱신 시 일부만 바뀌는 사고가 난다. (원문은 고치지 않으므로 — [주의 6-3](미션생선시스템_주의.md) — 이 분리는 구현 판단으로 여기에만 남긴다.)

`MissionBodyPartPriority` 를 코드 상수로 두면 [주의 6-2](미션생선시스템_주의.md)의 `indexOf = -1` fallback 이 사실상 발생하지 않는다 — 목록 개정에 배포가 따라오므로 마이그레이션을 같이 붙일 수 있다. DB 테이블로 가면 fallback 규칙이 실동작 경로가 되므로 반드시 구현해야 한다.

### 3-6. `GoalPhrase` — 목표 문구 40종 **(① 소관 · 참조만)**

```ts
GoalPhrase {
  id: string;
  text: string;
  purpose: 'DIET' | 'STRENGTH' | 'HEALTH' | 'FITNESS' | 'POSTURE';  // 문구에 박힌 목적 코드
  gender?: 'M' | 'F';
  ageBand?: string;
}
```

[§0](미션생성시스템.md#L5) 시스템 경계상 ①(운동 목표 문구) 소관이다. `MemberGoal.phraseId` 가 참조하는 대상이라 자리만 잡아둔다.

---

## 4. 제약·인덱스

| 대상 | 제약 | 이유 |
|---|---|---|
| `member_mission` | `UNIQUE (goal_id, slot_index, slot_generation)` | 회차 중복 = 종료 사유 역산 붕괴 |
| `member_mission` | `UNIQUE (goal_id, slot_index) WHERE status='ACTIVE'` | 한 슬롯에 활성 미션 1개 · MySQL 은 부분 인덱스가 없어 생성 컬럼 또는 앱 레벨 |
| `member_mission` | `CHECK (slot_index BETWEEN 1 AND 5)` | [§9 규칙 1](미션생성시스템.md#L1145) 최대 5개 |
| `member_mission` | `CHECK (target_volume > 0)` | [§9 규칙 2](미션생성시스템.md#L1145) 볼륨 필수 |
| `member_mission` | `axis_type='ATTENDANCE'` ↔ `axis_value IS NULL` | 1-C |
| `member_mission` | `intensity IS NOT NULL` ⊂ `MODALITY/CARDIO` | 1-B |
| `member_goal` | `UNIQUE (user_id) WHERE status='ACTIVE'` | 활성 목표는 1개 |
| `mission_progress_ledger` | `UNIQUE (mission_id, source_type, source_id)` | 멱등 |

**DB 제약으로 못 막는 것** — [§9 규칙 3~5](미션생성시스템.md#L1145)는 세트 전체에 걸린 불변식이다.

- 규칙 3 — 동시 진행 미션에 성격 축과 효과 축 중 한쪽만
- 규칙 4 — 성격 축 근력 사용 불가
- 규칙 5 — 균형·순발력 미션과 부위 미션의 종목 교집합 검증

행 단위 CHECK 로 표현이 안 되므로 **생성기의 ⑤ 검증 단계**([§4](미션생성시스템.md#L273))에서 잡고, 위반 시 생성 실패 로그 + 폴백 세트를 부여한다([§8](미션생성시스템.md#L1095)).

---

## 5. 기존 명세와의 충돌 — 주간 진행 모델

[달성률_테이블_변경_명세.md §6](../달성률_테이블_변경_명세.md)이 "목표·진행 테이블 5종 신설"로 잡아둔 스펙과 이 문서의 모델이 **다르다.**

| 항목 | 기존 명세 (회의 문서 기준) | 미션 생성 시스템 (TECH-602) |
|---|---|---|
| 진행 단위 | **주 1행** · 주 경계 월요일 00:00 KST | **주 개념 없음** · 10회 방문 누적 |
| 목표선 | 주마다 스냅샷 · 부분 주 비율 조정 | 할당 시점 1회 스냅샷 · 조정 없음 |
| 합산 지표 | 목표별 달성률 | **없음** — 미션 1개 = 게이지 1개 ([주의 2](미션생선시스템_주의.md)) |
| 진행 종료 | 주 확정(확정 시각) | 100% 도달 후 사용자 교체 선택 |

기존 명세의 "주간 진행 · 목표선 스냅샷 · 부분 주 표식"은 이 모델에서 **전부 불필요**해진다. 반대로 기존 명세 §1~5(마스터 데이터 정비 — `contribution` 신설, `cardio_intensity` 값 부여, 균형 종목 등록)는 **그대로 필요하다.** 미션의 분자를 계산하는 원천이 같기 때문이다.

→ 어느 쪽이 정본인지 PO 확인 필요. 이 문서는 TECH-602 를 정본으로 가정하고 썼다.

---

## 6. 미결

- [ ] ③ "미션 달성률 계산 시스템" 문서 확인 후 3-3 `MissionProgressLedger` 재작성 — 매칭 방식·멱등키
- [ ] 5번 — 주간 진행 모델 폐기 여부 PO 확인
- [ ] `metricType` 의 값 도메인 — [§5-1](미션생성시스템.md#L354)은 `BODY_PART_SET` 처럼 축과 단위를 붙인 8유형인데, `MemberMission` 은 `axisType`/`axisValue`/`unit` 3분할이다. 상수 테이블 조회 시 변환 규칙 필요
- [ ] `MemberMissionProgress` 분리 vs `MemberMission.currentVolume` — 1-D 권고는 분리
