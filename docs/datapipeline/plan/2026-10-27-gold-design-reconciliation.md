# 운영 Gold 모델 보조 대조 — 2026-10-27

## 현재 범위

[TECH-3076](https://linear.app/suppliesfitness/issue/TECH-3076)이 현재 Bronze·Silver·Gold 테이블 현황의 기준이다. 이 문서는 해당 이슈의 운영 Gold 3개 테이블을 실제 SQL과 대조한 보조 기록이다. 10/27 범위는 운영 Q1(주별 활성·출석·운동 기록 회원)과 Q2(월별 구독 유지율)이며 Q3 G오더 매출은 보류했다. 기존 [TECH-3081](https://linear.app/suppliesfitness/issue/TECH-3081)의 dev PoC 모델 5개는 현재 구현 범위가 아니다. 하위 [TECH-868](https://linear.app/suppliesfitness/issue/TECH-868)은 MART 설계의 완료 기준을 다루며 현재 테이블 구현 상태를 나타내지 않는다.

## 현재 모델과 Silver 매핑

| 운영 Gold 모델 | grain·지표 | Silver 입력 | 코드·검증 근거 |
| --- | --- | --- | --- |
| `fct_user_exercise_daily` | KST 기록일 × 회원 × 지점 1행. 유효 세트가 있는 세션의 `session_count`·`set_count`. Q1 운동 기록 회원은 주별 `count(distinct user_id)`. | 현재 `user_exercise_session`, `user_exercise_session_history`, `user_exercise_set_history`, `exercise` | [모델 SQL](https://github.com/suppliesfitness/data-warehouse/blob/main/dbt/models/mart_gymboxx/fct_user_exercise_daily.sql). [운영 전환 기록](https://github.com/suppliesfitness/data-warehouse/blob/main/docs/2026-10-22-prod-%EC%A0%84%ED%99%98-%ED%98%84%ED%99%A9.md)은 첫 Gold 실행과 주별 원본 대조를 기록한다. |
| `fct_user_attendance_daily` | KST 출석일 × 회원 × 지점 1행. `type='ACCESS'`·회원 ID가 있는 출석 수. Q1 출석 회원은 주별 `count(distinct user_id)`. | 현재 `access_history` | [모델 SQL](https://github.com/suppliesfitness/data-warehouse/blob/main/dbt/models/mart_gymboxx/fct_user_attendance_daily.sql). daily 태그가 있다. Q1 세 열의 원본 일치 판정은 [TECH-3076](https://linear.app/suppliesfitness/issue/TECH-3076)에 기록됐다. |
| `fct_membership_order` | 멤버십 주문 1건 1행. Q1 활성 후보 `is_active_candidate`, Q2 갱신 `is_renewal`·이탈 `is_churn`. 활성 회원은 주문 기간과 주의 겹침으로, 유지율은 월별 갱신·이탈 수로 계산한다. | 현재 `membership_order`, `membership`, `membership_order_gym_transfer` | [모델 SQL](https://github.com/suppliesfitness/data-warehouse/blob/main/dbt/models/mart_gymboxx/fct_membership_order.sql). [PR #28](https://github.com/suppliesfitness/data-warehouse/pull/28)에 Q1 완료된 18주와 Q2 6개월의 PO 원본 일치가 기록됐다. `membership_order`가 daily이므로 정기 운영 생성·갱신 성공은 별도 확인 대상이다. |

세 모델 모두 `mart_gymboxx`의 [모델 명세](https://github.com/suppliesfitness/data-warehouse/blob/main/dbt/models/mart_gymboxx/_models.yml)에 등록돼 있다. Q1은 주별 순회원 수를 사실 테이블에서 `count(distinct user_id)`로 계산한다. 사실 테이블의 행 수 합계를 순회원 수로 쓰지 않는다.

## 다음 확인

- TECH-868 설계 원본의 모델 목록·grain·metric·Silver → Gold mapping을 TECH-3076의 운영 3개 모델과 맞출지 확인한다. 옛 dev PoC의 `dim_date`, `fct_workout_session`, `fct_workout_exercise`, `agg_daily_session_exercise_completion`, `agg_user_workout`은 현재 완료 목록에서 제외한다.
- Q3 G오더 매출은 10/27 보류로 적고, 재개 결정 전에는 Gold 완료 범위로 세지 않는다.
- [PR #28](https://github.com/suppliesfitness/data-warehouse/pull/28)의 운영 BigQuery SELECT·PO 원본 대조는 확인됐다. 머지 후 `silver_gymboxx_daily`가 `fct_membership_order`를 실제 생성·갱신한 로그, 실행 시각은 아직 확보하지 못했다.
- TECH-868 상태는 설계 산출물의 세 완료 기준(목록, grain/metric, Silver mapping)으로 판정한다. 운영 테이블의 생성·갱신 상태는 TECH-3076 기준으로 별도 확인한다.
