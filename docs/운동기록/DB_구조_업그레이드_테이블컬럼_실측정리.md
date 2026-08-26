# DB 구조 업그레이드 방안 — 주제별 테이블·컬럼 실측 정리

> 원본: [DB_구조_업그레이드_방안.md](DB_구조_업그레이드_방안.md)
> 원본 문서(§00~§17)에서 다루는 주제별로 관련 테이블·컬럼을 뽑고, gymboxx 개발 DB(`gymboxx-dev`)에 직접 접속해 실제 구조를 대조했다. 원본 문서의 실측 기준은 **프로덕션 read-replica**(2026-08-19/21)이고, 이 문서의 실측은 **개발 DB** 기준이라 절대 행수는 다를 수 있다 — 구조(컬럼명·타입·제약)가 같은지가 확인 포인트다.

## 요약 — 문서·실측 차이 6건

1. `exercise`에 문서에 없는 `familiarity_level`(친숙도, float) 컬럼이 실제로 존재.
2. `exercise_body_part` 행수 — 문서 376행 vs 실측 334행(오차 42, 다른 테이블 오차 1~3행보다 큼). 원인 미상, 프로덕션 재확인 필요.
3. `body_part.part` 타입 — 문서 `varchar(30)` vs 실제 `varchar(255)`.
4. §04 "측정 방식 실측 조합 12종" — 개발 DB에서는 `exercise.unit`이 SET/MINUTE 2종뿐이고 `(unit, has_weight)` 조합도 3종만 관찰됨. 표본 차이인지 확인 필요.
5. 문서에 언급되지 않은 병렬 테이블 `user_workout_exercise_log` / `user_workout_exercise_log_detail` / `user_workout_log` 존재 — §12가 말하는 "루틴 계열 44,230행" 서술의 실체로 추정됨.
6. 마스터·분류 테이블(`exercise`, `body_part`, `body_part_detail`, `exercise_function`, `exercise_body_part_detail`)은 문서 수치와 오차 0~3건 수준으로 거의 일치 — dev/prod가 이 데이터만큼은 동기화된 것으로 추정. 반면 회원 기록성 테이블(`user`, `user_exercise_session*`)은 dev 표본이 훨씬 작아 절대 수치 비교 무의미.

---

## §01. 운동 성격 태그를 효과 축·추천 태그 테이블로 분리

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `exercise_function` | `exercise_id int NOT NULL`, `functional_tag enum('FAT_LOSS','ENDURANCE','MOBILITY','BALANCE','RECOVERY') NOT NULL` | 존재, 88행(문서 87행), PK `(functional_tag, exercise_id)`, FK `exercise_id→exercise.id`(문서 DDL엔 FK 생략) |
| 신설 예정 | `exercise_effect` | `id`(PK), `exercise_id`(FK), `effect_tag enum('STRENGTH','ENDURANCE','MOBILITY','BALANCE','PLYOMETRIC')`, `is_primary`, `status enum('ACTIVE','INACTIVE')`, `created_at`, `updated_at` | **미존재** |
| 신설 예정 | `exercise_recommend_tag` | `id`, `exercise_id`(FK), `tag enum('FAT_LOSS','RECOVERY')`, `status`, `created_at`, `updated_at` | **미존재** |

## §02. 부위 라벨 사전에 축 구분 컬럼 추가

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `body_part` | `id`, `part`, `status`, `created_at` | 존재, 8행(문서 일치), `part`는 실제 `varchar(255)`(문서는 `varchar(30)` — 불일치) |
| 신설 예정 | `body_part` | `axis enum('MUSCLE','MODALITY') NOT NULL` | **미존재** |
| 참조 FK(변경 시 함께 걸림) | `body_part_detail`, `exercise_body_part`, `machine_body_part`, `user_exercise_session_body_part`, `exercise_recommendation_log_body_part` | `body_part_id` | 5개 FK 전부 실측 확인 |

## §03. 유산소 강도 컬럼 신설

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `exercise` | `fatigue_level float` | 존재, 문서 표(로잉머신5·트레드밀런4·일립티컬3·트레드밀워크2) 실측과 일치 |
| 신설 예정 | `exercise` | `cardio_intensity enum('MODERATE','VIGOROUS') NULL` | **미존재** |

## §04. 측정 방식 선언 컬럼 신설

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `exercise` | `unit varchar(30)`, `has_weight tinyint NOT NULL DEFAULT 1` | 존재. 개발 DB `unit` distinct = SET, MINUTE 2종뿐, `(unit, has_weight)` 조합 3종(SET,1)=188·(SET,0)=64·(MINUTE,0)=23 |
| 신설 예정 | `exercise` | `measure_type enum('WEIGHT_REPS','REPS','DURATION') NOT NULL` | **미존재** |
| ⚠ 불일치 | — | — | 문서는 "실측 조합 12종"(프로덕션)이라 하나 개발 DB는 3종만 관찰 — 표본 차이 여부 확인 필요 |

## §05. 장비 분류를 12종으로 교체

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `exercise` | `type varchar(30) NOT NULL` | 존재. 6종 분포 MACHINE 77·DUMBBELL 55·BODY 42·PROP 42·BARBELL 32·CABLE 27 (문서 수치와 오차 0~1) |
| 신설 예정 | `exercise` | `equipment_type enum(12종)` (병행 생성, 구 `type`은 후속 제거) | **미존재** |

## §06. 부위 기여도 컬럼 추가 · 부하율 원값 보존

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `exercise_body_part_detail` | `exercise_id`, `body_part_detail_id`, `status`, `load_ratio float NOT NULL`, `created_at` | 존재, 511행(문서 514행), 자연키 복합 PK `(exercise_id, body_part_detail_id)`, `load_ratio` distinct 15개(0.05~1.0) — 문서와 일치 |
| 신설 예정 | `exercise_body_part_detail` | `contribution enum('DIRECT','ASSIST') NOT NULL` | **미존재** |

## §07. 부위 매핑 중복 방지 제약 추가 · 대리키 전환

| 구분 | 테이블 | 컬럼/제약 | 실측 확인 |
|---|---|---|---|
| 기존 | `exercise_body_part` | `id`(PK), `exercise_id`, `body_part_id`, `status`, `created_at` | 존재, 334행(문서 376행, 오차 42 — 확인 필요), FK 2개, **UNIQUE 제약 없음**(문서와 일치) |
| 신설 예정 | `exercise_body_part` | 생성열 + `UNIQUE(exercise_id, body_part_id, 생성열)` | **미존재** |
| 신설 예정 | `exercise_body_part_detail` | 자연키 복합 PK → 대리키(`id`) 전환 | 아직 자연키 복합 PK 그대로(§06과 동일 테이블) |

## §08. 동작 양식을 6번째 분류 축으로 선언

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존(스키마 변경 없음, 축 선언만) | `exercise` | `movement_pattern enum('PUSH','PULL','SQUAT','LUNGE','HINGE','ISOLATION','LOCOMOTION','STRETCH')` | 존재, 275행 전건 채움(NULL 0건). 분포: ISOLATION 115·PUSH 42·PULL 41·HINGE 22·LOCOMOTION 14·SQUAT 18·LUNGE 12·STRETCH 11 (문서와 거의 일치) |

## §09. 무게 단위 환산 구조 정비

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `user_exercise_session_history` | `weight_type enum('kg','lb') NOT NULL` | 존재(문서와 일치) |
| 기존 | `user_exercise_set_history` | `weight decimal(10,7) DEFAULT NULL` | 존재 |
| 신설 예정 | `user_exercise_set_history` | `weight_unit enum('kg','lb') NULL`(상위 행 값 복사), `weight_kg decimal(10,7)`(생성열, lb×0.45359237) | **미존재** |
| 참고(문서 미언급) | `user_workout_exercise_log_detail` | `weight_unit varchar(10)`, `weight decimal(5,2)`, `rep`, `duration` | 이미 존재(루틴 계열, dev 0행) — §12 "루틴 계열 44,230행" 서술의 원천 테이블로 추정 |

## §10. 세트 테이블에 대리키·수행 시각 추가

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존 | `user_exercise_set_history` | `user_exercise_session_history_id`, `set_number`, `count int COMMENT '횟수 or 초'`, `weight` — **정확히 4컬럼** | 존재, 980행, PK 복합자연키 `(user_exercise_session_history_id, set_number)`, 시각 컬럼 전혀 없음 — 문서와 완전 일치 |
| 신설 예정 | `user_exercise_set_history` | `id`(대리키, 기존 자연키는 UNIQUE로 유지), `performed_at timestamp NULL`, `created_at`, `updated_at` | **미존재** |

## §11. 세트 단위 강도 컬럼 신설

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 기존(비교 기준) | `user_exercise_session` | `rpe int unsigned COMMENT '운동자각도 10/10'` | 존재 |
| 신설 예정 | `user_exercise_set_history` | `rpe tinyint unsigned NULL`(1~10) | **미존재** |

## §12. 개인 최고 기록 이력 테이블 신설

| 구분 | 테이블 | 컬럼 | 실측 확인 |
|---|---|---|---|
| 신설 예정 | `personal_record_type` | `id`, `code varchar(30) UNIQUE`, `display_name`, `value_unit`, `applies_to_measure enum('WEIGHT_REPS','REPS','DURATION')`, `min_value`/`max_value decimal(12,4)`, `sort_order`, `status` | **미존재**(`SHOW TABLES LIKE '%personal_record%'` 0건) |
| 신설 예정 | `user_personal_record_history` | `id`, `user_id`(FK→`user.id`), `exercise_id`(FK→`exercise.id`), `record_type_id`(FK→`personal_record_type.id`), `record_value decimal(12,4)`, `weight_kg`, `reps`, `source_set_id`(FK→`user_exercise_set_history.id`, §10 전제), `achieved_at`, `is_approximate`/`is_current`, `created_at` | **미존재** |
| 선행 조건 확인 | `user`, `exercise`, `user_exercise_set_history` | `id` | 참조 대상 테이블은 모두 존재하나, `source_set_id`가 참조할 `user_exercise_set_history.id`는 §10 미착수라 아직 없음(강제 순서 §04→§12, §09→§12, §10→§12와 실측 상태가 부합) |

## §13~§16. 실행 순서·의사결정·검증

서술/전략 섹션으로 테이블·컬럼 신설 대상 없음. 언급된 테이블은 모두 §01~§12에서 실측 완료.

## §17. 부록 — 테이블·컬럼 변경 명세

§17-2(신설 테이블 4종 DDL), §17-3(기존 테이블 컬럼 변경 표), §17-4(FK 목록)는 §01~§12 내용과 동일해 개별 섹션에서 이미 대조했다. §17 고유의 추가 확인:

- §17-4 기존 FK 12개 전부 실측 확인: `body_part_detail.body_part_id`, `exercise_body_part.exercise_id`/`body_part_id`, `exercise_body_part_detail.exercise_id`/`body_part_detail_id`, `user_exercise_session.user_id`/`gym_id`/`access_history_id`, `user_exercise_session_history.user_exercise_session_id`/`exercise_id`/`machine_id`, `user_exercise_set_history.user_exercise_session_history_id`.
- §17-3의 `body_part.part` 타입 표기(`varchar(30)`)는 실제(`varchar(255)`)와 불일치(§02와 동일 건).

---

## 전체 테이블 목록 (실측 결과 포함)

| 테이블 | 문서상 상태 | DB 실측 |
|---|---|---|
| `exercise` | 기존, 컬럼 3종 추가·1종(구 `type`) 후속 제거 예정 | 존재, 275행, 14컬럼(문서에 없는 `familiarity_level` 컬럼 포함) |
| `exercise_function` | 기존, 이관 후 제거 예정 | 존재, 88행, 2컬럼 |
| `body_part` | 기존, `axis` 컬럼 추가 예정 | 존재, 8행, 4컬럼 |
| `body_part_detail` | 기존, 변경 없음 | 존재, 21행, 5컬럼 |
| `exercise_body_part` | 기존, 고유 제약 추가 예정 | 존재, 334행, 5컬럼(UNIQUE 없음) |
| `exercise_body_part_detail` | 기존, `contribution` 추가 + 대리키 전환 예정 | 존재, 511행, 자연키 복합 PK |
| `user_exercise_session` | 기존, 변경 없음 | 존재, 328행(`rpe` 보유) |
| `user_exercise_session_history` | 기존, 변경 없음(`weight_type` 보유) | 존재, 1087행 |
| `user_exercise_set_history` | 기존, 컬럼 6종 추가 + 대리키 전환 예정 | 존재, 980행, 정확히 4컬럼 |
| `machine` | 기존, 언급만 | 존재, 1137행 |
| `machine_body_part` | 기존(§02 FK 근거) | 존재 |
| `user_exercise_session_body_part` | 기존(§02 FK 근거) | 존재 |
| `exercise_recommendation_log_body_part` | 기존(§02 FK 근거) | 존재 |
| `user` | 기존, 언급만(성별·생년) | 존재, 386행, `gender`/`birth_of_date` 확인 |
| `access_history` | 기존, 언급만 | 존재 |
| `exercise_effect` | **신설 예정** | 미존재 |
| `exercise_recommend_tag` | **신설 예정** | 미존재 |
| `personal_record_type` | **신설 예정** | 미존재 |
| `user_personal_record_history` | **신설 예정** | 미존재 |
| `user_workout_exercise_log` / `user_workout_exercise_log_detail` / `user_workout_log` | 문서 미언급 | 존재(루틴 계열 병렬 테이블, §12 서술의 실체로 추정) |
