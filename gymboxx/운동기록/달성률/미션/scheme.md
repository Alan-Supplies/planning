# 목표·미션 스키마 초안

> 2026-09-09: 테이블명 `user_goal`, `user_mission`, `user_goal_attendance_time`은 60% 확정, 컬럼은 재검토 대상이다.
> 구현 요구사항은 [specification.md](specification.md), 검증 케이스는 [테스트목록.md](테스트목록.md)를 함께 읽는다. 아래 인터페이스에는 유산소 강도 제거를 반영했으며 나머지 새 보완안은 아직 반영하지 않았다.

> 기준: TECH-601 · TECH-602 · TECH-1382를 정리한
> [`목표및미션시스템설계.md`](../목표및미션시스템설계.md).
> 주 단위 달성률·300% 캡은 구판이므로 반영하지 않는다.

## 공통 타입

```typescript
type Id = number;
type DateTime = string; // UTC ISO-8601
type LocalDate = string; // KST의 YYYY-MM-DD
type LocalTime = string; // KST의 HH:mm:ss

type UserGoalStatus = 'ACTIVE' | 'COMPLETED' | 'CHANGED';

type GoalPurpose =
  | 'STRENGTH_GAIN'
  | 'ENDURANCE_GAIN'
  | 'WEIGHT_LOSS'
  | 'POSTURE_CORRECTION'
  | 'HEALTH_MANAGEMENT';

type UserMissionStatus =
  | 'IN_PROGRESS'
  | 'CLEARED'
  | 'REPLACED'
  | 'CLOSED';

/** 1차 구현 대상. 값 이름은 DB 구조 개편에서 최종 확정한다. */
type MissionMetricType =
  | 'BODY_PART_SET'
  | 'BODY_PART_VOLUME'
  | 'CARDIO_MINUTE'
  | 'STRETCHING_MINUTE';

type BodyPart =
  | 'CHEST'
  | 'BACK'
  | 'SHOULDER'
  | 'ARM'
  | 'LEG'
  | 'CORE';

type DayOfWeek =
  | 'MONDAY'
  | 'TUESDAY'
  | 'WEDNESDAY'
  | 'THURSDAY'
  | 'FRIDAY'
  | 'SATURDAY'
  | 'SUNDAY';
```

## user_goal

회원이 선택한 목표 한 건이다. 회원별 `ACTIVE` 목표는 최대 1개다.

```typescript
interface UserGoal {
  id: Id;
  userId: Id;

  /** 객관식 문구이면 마스터 FK, 직접 입력이면 null */
  goalPhraseId: Id | null;

  /** 마스터 수정 뒤에도 과거 표시를 보존하는 문구 스냅샷 */
  phrase: string;

  /** 미션 생성 규칙의 입력값. 선택 문구에서 결정해 스냅샷 저장 */
  purpose: GoalPurpose;

  /** 목표를 선택한 이유 */
  reason: string;

  status: UserGoalStatus;

  /** 사용자에게 안내할 설정 종료일. 자동 종료나 미션 달성률 계산에는 쓰지 않음 */
  plannedEndOn: LocalDate | null;

  /** 목표 활성화 시각이자 완료 결과 지표의 집계 시작점 */
  startedAt: DateTime;

  /** 사용자가 완료 또는 변경을 확정한 시각. ACTIVE이면 null */
  endedAt: DateTime | null;

  createdAt: DateTime;
  updatedAt: DateTime;
}
```

상태는 `ACTIVE -> COMPLETED` 또는 `ACTIVE -> CHANGED`로만 이동한다. 완료는 달성률로 자동 판정하지 않는다. 삭제 정책은 미확정이므로 아직 `DELETED` 상태나 삭제 시각을 넣지 않는다.

## user_mission

목표에 속한 개별 미션 한 건이다. 미션 하나가 홈 게이지 하나이며 목표 전체 합산 달성률은 없다.

```typescript
interface UserMission {
  id: Id;
  userGoalId: Id;

  /** 목표 안의 고정 슬롯 번호 */
  slotNo: 1 | 2 | 3 | 4 | 5;

  /** 같은 슬롯에서 몇 번째로 부여된 미션인지 나타내는 회차. 최초 1 */
  slotGeneration: number;

  metricType: MissionMetricType;

  /**
   * BODY_PART_SET/BODY_PART_VOLUME: BodyPart
   * CARDIO_MINUTE: null (exercise.training_type = CARDIO, 강도 구분 없음)
   * STRETCHING_MINUTE: BodyPart | null
   * null 스트레칭은 특정 부위가 없는 전신 스트레칭을 뜻한다.
   */
  targetParam: BodyPart | null;

  /** 부여 시 계산해 고정하는 분모 스냅샷 */
  targetTotal: number;

  /** assignedAt 이후 유효 기록 전체를 재집계한 분자 */
  numerator: number;

  /** numerator / targetTotal. 1.0 = 100%, 상한 없음 */
  rate: number;

  status: UserMissionStatus;

  /** 이 미션의 집계 기산점 */
  assignedAt: DateTime;

  /** 최초로 rate >= 1.0이 된 시각 */
  clearedAt: DateTime | null;

  /** REPLACED 또는 CLOSED로 종결된 시각 */
  endedAt: DateTime | null;

  createdAt: DateTime;
  updatedAt: DateTime;
}
```

| `metricType` | `targetParam` | `targetTotal` / `numerator` 단위 |
|---|---|---|
| `BODY_PART_SET` | 부위 6종 | 기여도 반영 세트분 |
| `BODY_PART_VOLUME` | 부위 6종 | kg 환산 총 훈련량 |
| `CARDIO_MINUTE` | `null` | 실제 운동 분 |
| `STRETCHING_MINUTE` | 부위 또는 `null` | 분 |

효과별 세션 수는 마스터 데이터가 준비되지 않아 보류하고, 출석 일수는 폴백 스펙이 확정되기 전까지 1차 타입에서 제외한다.

상태 전이는 다음과 같다.

```text
IN_PROGRESS ──rate >= 1.0──> CLEARED ──사용자 교체──> REPLACED
      │                         │
      └────목표 완료·변경───────┴──────────────────> CLOSED
```

`CLEARED`도 계속 재집계한다. 교체하면 기존 행을 `REPLACED`로 보존하고 같은 슬롯에 다음 회차 행을 생성하며, 초과분은 이월하지 않는다.

## user_goal_attendance_time

목표 생성 시 선택한 운동 예정 요일과 시각이다. 한 행은 한 요일의 일정을 나타낸다.
캘린더·리마인드용 부가 정보이며 미션의 `numerator`나 `rate` 계산에는 사용하지 않는다.

```typescript
interface UserGoalAttendanceTime {
  id: Id;
  userGoalId: Id;

  /** 한국시간 기준 요일 */
  dayOfWeek: DayOfWeek;

  /** 한국시간 기준 예정 시각 */
  attendanceTime: LocalTime;

  createdAt: DateTime;
  updatedAt: DateTime;
}
```

## DB 제약과 계산 규칙

| 대상 | 제약 |
|---|---|
| `user_goal` | 회원당 `ACTIVE` 최대 1행 |
| `user_mission` | `UNIQUE(user_goal_id, slot_no, slot_generation)` |
| `user_mission` | 목표·슬롯별 `IN_PROGRESS` 또는 `CLEARED` 최대 1행 |
| `slot_no` | `1 <= slot_no <= 5` |
| `slot_generation` | `slot_generation >= 1` |
| `target_total` | `target_total > 0` |
| `numerator`, `rate` | `>= 0`; 소수를 보존하고 화면에서만 반올림 |
| `user_goal_attendance_time` | `UNIQUE(user_goal_id, day_of_week)` |

달성률은 이벤트마다 원천 기록을 전량 재산출한다. 회원, `assignedAt` 이후, 종료된 세션, 삭제·비활성 제외 조건을 적용하고 외부 운동도 포함한다. 홈 조회에서는 저장된 `numerator`와 `rate`를 반환한다.

`targetTotal`은 `per_visit_amount × 10 × frequency_factor`의 결과를 복사한 값이다. 기준 운동량 마스터를 조회 시점에 다시 조인해 재계산하면 안 된다.

## 남은 결정

- 직접 입력한 목표 문구를 `GoalPurpose`로 분류하는 규칙
- 운영 목적의 `ATHLETIC_PERFORMANCE` 포함 여부
- 목표 삭제의 soft delete 정책과 컬럼
- 로테이션 마스터 변경에 대비한 우선순위 절대 위치 저장 여부
- 기록 수정으로 100% 미만이 된 `CLEARED` 미션의 상태 복귀 여부
- `MissionMetricType`의 최종 DB enum 이름


## 2026-09-09 요구사항 기반 재검토 메모

[요구사항](specification.md)의 **보완안**은 PO 확정이 아니며, 다음 사항을 결정한 후 인터페이스/DDL에 반영한다.

| 검토 대상 | 요구사항에서 필요해진 정보·동작 |
|---|---|
| `UserGoal` 삭제 표시 | soft delete 보완안(R31). deletedAt 또는 동등한 컬럼 필요. 기존 상태를 덮어 삭제를 표현하지 않기 |
| 생성 입력 보존 | 생성 당시 세그먼트·로테이션/분류 규칙 버전 또는 스냅샷(R07/R08/R16). 현재 회원 정보만 조회해서 과거 규칙을 바꾸지 않기 |
| `CLEARED` 역전이 | 기록 정정 시 IN_PROGRESS로 복귀(R28). clearedAt은 최초 도달 시각 유지, 교체 권한은 현재 rate로 판정 |
| `assignedAt`의 원천 비교 | 세션 started_at 기준 반개구간과 종료 조건(R19). created_at/end_at 중 임의 선택 금지 |
| `REPLACED`/`CLOSED` | 종료 시 마지막 분자/비율을 보존하며 이후 정정에 불변(R29) |
| 타입별 파라미터·단위 | 유산소는 training_type=CARDIO의 실제 분 합산(R23), 볼륨은 이미 저장된 kg(R22). 분모 기준량도 같은 단위 필요 |
| 계산 진단·소수 | 마지막 계산 시각, 분자/비율 정밀도, 동시 갱신 방식 검토(R25/R27). 도달 여부에 표시 반올림 사용 금지 |
| 유일성과 트랜잭션 | MySQL의 활성 목표/현재 슬롯 제약과 회원 단위 직렬화(R34). 전량 재산출만으로 경합이 해소되지는 않음 |
| 1차 미지원 | 65세 이상 균형 구성·효과세션·출석 폴백, 데이터 미준비 구성은 R17/R18의 개방 조건 확인 |

`ATHLETIC_PERFORMANCE` 추가는 이번 요구사항 범위에서 채택하지 않는다. 현재 목적 5종을 유지한다. 컬럼명이 확정되면 요구사항 ID와 테스트 ID를 유지한 채 물리 필드 매핑만 갱신한다.

운영 DB를 읽기 전용으로 대조한 결과, 세트 `duration_second`/`done_at`은 이미 존재하지만 최근 1,000건에서 모두 NULL이었다. 기여도·유산소 강도는 아직 없고 `weight_role=ASSIST`는 존재한다. 시간 원천·레거시 호환·보조중량 제외는 요구사항 R22/R37 및 테스트 D01~D09를 먼저 확인한다. 운영 스키마와 worktree 라이브러리는 일치하지 않는다.

2026-09-09 사용자 방향 반영: 유산소 강도 타입을 제거하고 CARDIO_MINUTE의 targetParam을 null, 단위를 실제 분으로 변경했다. 강도 컬럼 신설은 필요 없다. 대신 현재 exercise.training_type 분류의 오탐·누락 정비(R38)가 선행한다.
