# 운동기록 DW 배치 파이프라인 PoC — 진행상황 (2026-08-18)

> 오늘 대화 정리본. 집에서 이어서 진행할 때 이 문서부터 읽는다.

## 2026-08-20 진행 체크포인트

### 완료

- CDC 원천 데이터를 적재할 S3 구조를 결정했다. 세부 설계 문서는 추가 보강이 필요하다.
- `gymboxx_dev`의 binlog 설정을 완료했다.
- AWS DMS 초기 설정을 IaC로 작성해 `feature/aws-dms` 브랜치에 커밋했다.

### 미완료

- AWS DMS CDC task 적용과 실행.
- 합성 운동기록 생성·변경 후 MySQL→S3 복제 결과 확인.

### 오늘 밤 이어서 할 다음 행동

1. `feature/aws-dms`의 IaC 적용 상태를 확인한다.
2. DMS source·target endpoint 연결 테스트를 통과시킨다.
3. 운동기록 두 테이블의 CDC task를 시작한다.
4. 합성 운동기록을 생성·변경하고 S3 반영 결과를 확인해 증거를 기록한다.

## 오늘 확정된 것

1. **스택**: MySQL(gymboxx-dev) → AWS DMS(CDC) → S3(Glue Catalog) → Athena(lake sql) → Airflow+dbt core → BigQuery(Warehouse) → Airflow+dbt core → Mart(BigQuery). (`스택결정.md`)
2. **대상 데이터**: gymboxx P0-11(lib 4.29.0+DDL) 산출물인 `user_exercise_session_history` · `user_exercise_set_history`만. `weight_value`·`challenge_calendar` 등 다른 테이블은 범위 밖.
3. **환경**: `gymboxx-dev`, 합성/테스트 데이터 — 운영 스냅샷 아님. → 국외이전 법무 검토(DA-P0-16)는 이 PoC 단계에서는 블로커 아님. (단, 나중에 운영 데이터로 바뀌면 재검토 필요)
4. **기존 일정과의 관계**: **전체 P0 신규작업 중단**(P0-06 IDOR, P0-15a 야간 cron 등 포함). 단 `P0-10`(round_number 정합화)·`P0-11`(lib+DDL)은 **dev 한정 예외**로 계속 — 프로덕션 배포(스테이징 검증·6단계 배포·소비 repo 영향조사 등 기존 DoD)는 별도 승인 전까지 보류.
5. **실시간 매출 ADR과는 별개**: `ADR-실시간-매출-데이터-반영-아키텍처.md`(Continuous Query 기반)는 다른 기능이라 상태 변경 없이 계속 `제안`으로 둠.
6. 오늘 이 대화가 "구현·PoC 착수" 승인으로 기록됨 — 관련 문서 전부 갱신 완료(아래 목록).

## 오늘 수정한 파일

- `ADR-실시간-매출-데이터-반영-아키텍처.md` — 배경(Lakehouse=S3+DMS+Glue/Athena, Warehouse=BigQuery 유지), Option C 설명, 영향 섹션(크로스클라우드 적재 지연 단계) 수정.
- `dw-tool-comparison.md` — "가결정" → "결정 확정", L1→Lake 실제 경로 반영, DMS(CDC)가 문서의 "배치 전제"와 결이 다를 수 있다는 메모 추가.
- `스택결정.md` — "1차 PoC 승인" 절 추가(대상/환경/기존일정 관계/범위 밖 명시).
- `alan-실행순서.md` — 상단에 "2026-08-18 갱신: 전체 P0 신규작업 중단, P0-10·11만 dev 예외" 공지 추가.
- `daily/2608/260818.md` — 오늘 할 일(P0-15a) 중단 표시, "새로 들어온 일"에 오늘 결정 요약, 종료 점검에 재계획 사유·다음 행동 기록.

## 기술 구현 방식 4가지 — 결정 (2026-08-18)

1. **DMS 복제 모드**: ~~Full Load 1회~~ → **지속 CDC 복제**로 확정. (Full Load보다 범위가 넓어짐 — Phase 1·5 DoD에 "증분 반영 확인"이 추가됨)
2. **S3 → BigQuery 브리지 방식**: 별도 결정 불필요 — `스택결정.md`에 이미 "transformer (airflow + dbt core)"로 명시됨. BigQuery Omni/STS는 채택 안 함.
3. **Airflow 호스팅**: **미정 — 담당자 조사 과제로 남김.** 후보: 기존 EKS 클러스터에 self-hosted / 로컬·docker-compose / 관리형 MWAA / 관리형 Cloud Composer. → Phase 3·5를 막는 선행 스파이크 이슈로 별도 발행.
4. **Mart가 답해야 할 지표**: **일별 세션당 평균 세트 완료율**로 확정 (`user_exercise_session_history`·`user_exercise_set_history`로 계산 가능).

## 인프라 스택 구현 이슈 분해

→ **`인프라-스택-구현-이슈.md`로 분리**했다. 이슈 8건의 제목·선행관계·완료 기준은 그 문서를 본다(이 문서에 중복해서 적지 않는다).

큰 구조만 옮겨두면, 스택 설치(1. 도입 방식 결정 → 2. 설치·구축)를 선행으로 끝낸 뒤 Warehouse·Mart 작업으로 넘어간다. DMS(3)와 Glue/Athena(4)는 Airflow와 무관해 병렬 진행 가능하다.

## 이어서 할 다음 행동

1. `인프라-스택-구현-이슈.md`의 8건을 Linear에 발행 (ID는 Linear 자동 발행, 선행관계는 blockedBy로 연결).
2. 1번(Airflow+dbt core 도입 방식 결정) 담당자 먼저 지정 — 2번의 선행이고 2번이 다시 5~8번의 선행이라 전체 일정을 좌우한다.
3. 나머지 담당자 배정 후 각 이슈의 담당자 항목 채우기.
4. Harvey/Vonn에게 "전체 P0 중단" 사실 통보 — IDOR 등 보안·법적 리스크가 계속 누적됨을 알고 내린 결정임을 명시.
