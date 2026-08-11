# 운동 기록하기 테이블 구조

PT 배정/트레이너/PT 상품·주문 연관 테이블(`workout_card_assignment`, `trainer`, `pt_product`, `pt_order` 등)과
레거시 `workout`/`access_history`/`user_exercise_session*` 테이블은 제외하고, 운동 기록 자체와 직접 관련된
테이블만 정리한 문서입니다.

Entity 정의 위치: `node_modules/@suppliesfitness/gymboxx-lib/src/entity/`

## 테이블 목록

### exercise (운동 종목 마스터)
파일: `entity/exercise.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| name | string | 운동 이름 |
| type | EXERCISE_TYPE | DUMBBELL / BARBELL / MACHINE / CABLE / KETTLEBELL / BODY / PROP |
| unit | EXERCISE_UNIT | SET / MINUTE |
| description | string | |
| image_url | string | |
| video_url | string | |
| status | STATUS | |
| created_at | timestamp | |

관계
- `exercise_body_part[]` — 1:N
- `workout_card_exercise[]` — 1:N
- `user_workout_exercise_log[]` — 1:N

### body_part (운동 부위 마스터)
파일: `entity/body_part.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| part | BODY_PART | CHEST / BACK / SHOULDER / ARM / LEG / CORE / CARDIO / STRETCHING |
| status | STATUS | |
| created_at | timestamp | |

관계
- `exercise_body_part[]` — 1:N

### exercise_body_part (exercise ↔ body_part 조인)
파일: `entity/exercise_body_part.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| exercise_id | FK → exercise | |
| body_part_id | FK → body_part | |
| status | STATUS | |
| created_at | timestamp | |

### workout_card (운동 카드/루틴)
파일: `entity/workout_card.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| title | string | |
| workout_part | string | |
| description | string | |
| image_url | string | |
| type | WORKOUT_CARD_TYPE | PRODUCT / BOOKMARK / USER |
| status | WORKOUT_CARD_STATUS | ACTIVE / CREATED / UPDATED / DELETED |
| created_at | timestamp | |
| updated_at | timestamp | |

관계
- `workout_card_exercise[]` — 1:N (카드에 포함된 운동 목록)
- `workout_card_history[]` — 1:N (변경 이력)
- `user_workout_log[]` — 1:N (사용자 운동 기록 세션)

> 참고: 원본 엔티티에는 `trainer_id`, `pt_product_id`, `pt_order_id` 컬럼도 있으나 PT 연관 필드라 이 문서에서는 제외했습니다.

### workout_card_exercise (카드 내 운동 구성, 계획값)
파일: `entity/workout_card_exercise.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| workout_card_id | FK → workout_card | |
| exercise_id | FK → exercise | |
| set | number \| null | |
| duration | number \| null | |
| order | number \| null | 카드 내 노출 순서 |
| status | STATUS | 기본 ACTIVE |
| created_at | timestamp | |

### workout_card_history (카드 변경 이력)
파일: `entity/workout_card_history.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| workout_card_id | FK → workout_card | |
| status | WORKOUT_CARD_HISTORY_STATUS | CREATED / UPDATED / DELETED |
| created_at | timestamp | |

### user_workout_log (사용자의 1회 운동 세션 기록)
파일: `entity/user_workout_log.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| user_id | FK → user | |
| workout_card_id | FK → workout_card | |
| status | USER_WORKOUT_LOG_STATUS | IN_PROGRESS / DONE / INACTIVE |
| is_auto_done | boolean | 자동 완료 여부 |
| created_at | timestamp | |

관계
- `user_workout_exercise_log[]` — 1:N (cascade insert/update)

### user_workout_exercise_log (세션 내 개별 운동 기록)
파일: `entity/user_workout_exercise_log.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| user_workout_log_id | FK → user_workout_log | |
| exercise_id | FK → exercise | |
| set | number \| null | |
| duration | number \| null | |
| memo | string \| null | |
| tag | EXERCISE_LOG_TAG \| null | GOOD / DIFFICULT / NOT_FEEL / PAIN |
| status | USER_WORKOUT_EXERCISE_LOG_STATUS | TODO / DONE |
| created_at | timestamp | |

관계
- `user_workout_exercise_log_detail[]` — 1:N

### user_workout_exercise_log_detail (세트/반복/무게 상세 기록)
파일: `entity/user_workout_exercise_log_detail.ts`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | PK | |
| user_workout_exercise_log_id | FK → user_workout_exercise_log | |
| round | number | 세트(회차) 번호 |
| weight_unit | WORKOUT_WEIGHT_UNIT \| null | KG / LBS |
| weight | decimal(5,2) \| null | |
| rep | number \| null | |
| duration | number \| null | |
| status | STATUS | |
| created_at | timestamp | |

## 관계 다이어그램

```
exercise ──< exercise_body_part >── body_part

workout_card ──< workout_card_exercise >── exercise
workout_card ──< workout_card_history

user ──< user_workout_log >── workout_card
user_workout_log ──< user_workout_exercise_log >── exercise
user_workout_exercise_log ──< user_workout_exercise_log_detail
```

## 관련 코드 위치
- `src/modules/pt-subscription/pt-subscription.dao.ts:304-480` — 운동 기록 생성/조회/수정 로직
  (`getWorkoutCardLogsByOrderId`, `updateWorkoutExerciseLog`, `updateWorkoutExerciseLogDetail`,
  `createUserWorkoutExerciseLogDetail` 등)
- `src/modules/pt-subscription/pt-subscription.module.ts:15-42` — 모듈 내 repository 등록
- 엔티티 원본: `node_modules/@suppliesfitness/gymboxx-lib/src/entity/{exercise,exercise_body_part,body_part,workout_card,workout_card_exercise,workout_card_history,user_workout_log,user_workout_exercise_log,user_workout_exercise_log_detail}.ts`
- Enum 정의: `node_modules/@suppliesfitness/gymboxx-lib/src/enum/common.enum.ts:820-974`
