# 알림 시스템 2차 개편 — 판정·발송 이력·수신 시간대

작성: 2026-10-27
상태: 제안. 4분기 과제 후보로 정리한 계획이며, 착수 전에 7절의 결정 항목과 8절의 경계 합의가 필요하다.
담당 제안: Alan
선행 문서: [알림개인화 README](../알림개인화/README.md) · [착수 계획](../알림개인화/00_개편_착수계획.md) · [현황](../알림개인화/01_현황.md) · [설계안](../알림개인화/02_설계안.md) · [사례와 고려사항](../알림개인화/03_사례와_고려사항.md)

## 1. 한 줄 요약

1차 개편은 동의 3종 분류와 설정 화면으로 끝났고, 10월에 Weizen이 푸시 발송 입구를 app-server 한 곳으로 모았다. 2차는 그 입구에 판정 함수 하나와 발송 이력을 붙여 "동의를 껐으면 안 오고, 왔으면 기록이 남는" 상태를 만든다.

## 2. 왜 지금인가

### 2-1. 1차에서 끝난 것과 남은 것

- Linear [푸시 알림 시스템 업데이트](https://linear.app/suppliesfitness/project/푸시-알림-시스템-업데이트-50d91425ccf4)는 10/16 Completed. 동의 3종(공지 및 이용 안내사항 · 편의사항 · 마케팅 정보) 분류, 출석 약속 동의 컬럼·API와 출석 요일 배치 게이트([TECH-2133](https://linear.app/suppliesfitness/issue/TECH-2133)), 온보딩 동의 시트([TECH-2808](https://linear.app/suppliesfitness/issue/TECH-2808)), 운동 목표 알림([TECH-2866](https://linear.app/suppliesfitness/issue/TECH-2866))까지 반영됐다.
- 프로젝트 설명에 "알림 시스템 전체 점검·업데이트"는 후속 범위(next scope)로 남아 있다. [설계안](../알림개인화/02_설계안.md) 6절의 4~6단계(디스패처 판정·발송 이력·차단 적용·dedupe)가 그 내용이다.
- 공유 리마인드 [TECH-2585](https://linear.app/suppliesfitness/issue/TECH-2585)는 법률 검토로 취소됐다. 이 문서의 범위에 넣지 않는다.

### 2-2. 10월에 생긴 기반 — Weizen의 푸시 C안

C안은 "본체 알림 모듈(app-server) + DB 없는 발송기(messaging-lambda)"다. 10/21까지 아래가 운영에 반영됐다.

| 단계 | 이슈 | 결과 |
| --- | --- | --- |
| 1. 람다 lib·TypeORM 제거 | [TECH-3112](https://linear.app/suppliesfitness/issue/TECH-3112) | 람다가 mysql2 SQL 3개만 쓴다. `target_id` 없을 때 임의 회원에게 가던 구멍이 막혔다 |
| 2. app-server 발송 5벌 통합 | [TECH-3120](https://linear.app/suppliesfitness/issue/TECH-3120) | `AppPushQueue` 하나가 메시지 조립·SQS 전송을 맡는다. 호출 지점 57곳은 그대로 |
| 3·4. 메시지 v2 + 내부 발송 API | [TECH-3151](https://linear.app/suppliesfitness/issue/TECH-3151) | app-server가 토큰을 찾아 담는다. `POST /internal/notifications/app-push` 신설 |
| 5. HQ·branch-admin 전환 | [TECH-3162](https://linear.app/suppliesfitness/issue/TECH-3162) | HQ·지점 어드민 푸시가 내부 API로 들어온다 |
| 알림함 저장 이동 | [TECH-3182](https://linear.app/suppliesfitness/issue/TECH-3182) | `notification` INSERT를 app-server가 한다 |

C안 이슈 본문에 남은 것으로 적힌 항목이 이번 2차의 출발점이다.

- "동의 게이트 없음(정책 대기)" — TECH-3112 본문. 판정을 어디서 누가 할지 정해지지 않았다.
- user-app-batch는 아직 SQS v1에 직접 넣는다. "batch는 app-server 통합 때 함께 전환" — TECH-3162 본문.
- 람다의 무효 토큰 정리(람다 DB 제거 2/2)는 미착수.

즉 설계안 5절에서 고른 B안(디스패처)은 새 워커를 만드는 것이 아니라 **app-server 알림 모듈의 `AppPushQueue` 앞단에 판정과 이력을 두는 것**으로 구체화된다.

### 2-3. CS 근거 — 발송 이력이 없어서 생기는 일

#gymboxx_cs 8/1~10/27에서 "안 왔다"는 문의마다 CS가 개발자에게 로그 확인을 부탁했다.

| 날짜 | 문의 | 채널 |
| --- | --- | --- |
| 8/25 | 휴대폰 변경 후 로그인 PIN 미수신 2건. 수신거부(A0090)로 판명 | 문자 |
| 10/1 | 외국인 회원 결제 완료 링크 메일 미수신 | 메일 |
| 10/8 | PIN 문자 수신 불가, 스팸 등록 아님 | 문자 |
| 10/12 | 365PASS 인증번호 미수신, 발송 로그 확인 요청 | 문자 |
| 10/12 | 락커 회수 안내 푸시·문자 미수신 주장, 로그 확인 요청 | 앱 푸시·문자 |

여섯 건 중 앱 푸시는 한 건이고 나머지는 문자·메일이다. 발송 이력 조회가 CS에 효과를 내려면 **채널에 상관없이 회원 단위로 보여야 한다.** 그래서 이력 테이블은 채널 공통으로 설계하고, 1차 구현은 앱 푸시를 채우며 문자는 기존 `sms_history`를 같은 조회 화면에 잇는다.

### 2-4. 같이 닫히는 결함

- [TECH-2891](https://linear.app/suppliesfitness/issue/TECH-2891) `APP_PUSH_TYPE` 값 하나가 제목·저장값·수신자 판정을 겸해 푸시 하나 추가에 lib 발행이 필요하고, 트레이너 푸시가 회원에게 갈 수 있다. 2차의 매핑표 작업에서 `target_type`과 `title`을 분리하면 같이 끝난다.
- [TECH-1087](https://linear.app/suppliesfitness/issue/TECH-1087) UX-004 "알림 동의 상태와 실제 발송의 일치". 2026-06까지 이어진 제보의 원인이 2-5절의 현황이다.
- [TECH-2842](https://linear.app/suppliesfitness/issue/TECH-2842) 080 수신거부 번호에 인증 문자까지 안 나가던 결함은 10/13 해결됐다. 발신번호 분기 결과가 이력에 남아야 CS가 다시 묻지 않는다.
- [TECH-1324](https://linear.app/suppliesfitness/issue/TECH-1324) SQS 배치 재시도로 문자가 중복 발송된다. 문자 경로는 이번 범위 밖이지만 `dedupe_key` 설계를 같은 모양으로 둔다.

### 2-5. 현황 요약 ([01_현황](../알림개인화/01_현황.md) 10/7 기준, 10/21 C안 반영 뒤 갱신)

- 동의를 검사하는 발송 경로는 배치 2곳뿐이다. app-server 경로 전체가 `app_push` 토글을 보지 않는다.
- 발송 이력 테이블이 없다. 알림함 `notification`이 유일한 기록이고, 판정 결과(왜 안 보냈는지)는 어디에도 없다.
- 배치마다 중복 방지 방식이 다르고 없는 배치도 있다.
- 야간 광고 차단과 `(광고)` 표기 코드가 없다.
- 동의 철회 시각이 남지 않는다(`*_agreed_at`만 있음).
- 10/21 이후 달라진 점: app-server·HQ·branch-admin 발 푸시는 전부 `AppPushQueue`를 지난다. 판정을 넣을 자리가 생겼다.

## 3. 목표와 완료 조건

| 목표 | 완료 조건 | 측정 |
| --- | --- | --- |
| 모든 앱 푸시가 판정 하나를 거친다 | 발송처가 SQS에 직접 넣는 경로 0 (batch 포함) | 람다 로그의 `format: v1` 비율 0 |
| 동의를 끈 회원에게 그 카테고리 푸시가 가지 않는다 | shadow 기간에 측정한 "동의 OFF인데 발송" 건수가 차단 적용 뒤 0 | `notification_dispatch_log.decision` 집계 |
| 왜 안 왔는지 CS가 직접 본다 | HQ 회원 상세에서 채널 공통 발송 이력 조회 | #gymboxx_cs 로그 확인 요청 건수, 3개월 6건 기준 |
| 중복 발송이 없다 | 같은 `dedupe_key` 2회 발송 0 | UNIQUE 위반 집계 |
| 수신 시간대·야간 광고 규칙이 적용된다 | 21~08시 KST 광고성 발송 0 (야간 동의 없는 회원) | `decision = SKIPPED_QUIET_HOURS` 집계 |

## 4. 범위

### 포함

- 판정 함수 `decide()`와 호출 지점: app-server `AppPushQueue` 앞단
- `notification_dispatch_log`(채널 공통 스키마, 1차 적재는 앱 푸시)
- `user_notification_preference` 신설과 기존 4개 동의 컬럼 양쪽 쓰기
- `user_notification_quiet_hours`와 설정 API
- 푸시 타입 ↔ 카테고리 매핑표(lib), `target_type`·`title` 분리([TECH-2891](https://linear.app/suppliesfitness/issue/TECH-2891))
- user-app-batch 발송을 내부 API로 전환(C안 잔여, Weizen과 분담)
- 배치별 중복 방지를 `dedupe_key`로 교체
- HQ 회원 상세의 발송 이력 조회 API(문자는 `sms_history` 연계)

### 제외

- Braze 캠페인 발송 경로. 수신 설정 정본만 이 도메인이 갖고 CRM에 동기화한다
- 앱 설정 화면 변경(1차에서 끝남). 수신 시간대 화면은 FE 별건으로 발행
- 기존 동의 컬럼 읽기 제거(설계안 6단계, 별건)
- 공유 리마인드 정책(법률 검토 대기)
- 문자·알림톡 발송 경로 자체의 개편(common-lambda). 이력 조회 연계만 한다
- 람다 무효 토큰 정리(C안 잔여, Weizen)

## 5. 설계 — 설계안 대비 갱신한 것

### 5-1. 어디에 두는가

설계안 5절 B안을 C안 구조에 맞춘다.

```
app-server 호출부 57곳 ─┐
HQ · branch-admin ──────┼─▶ POST /internal/notifications/app-push ─▶ AppPushQueue
user-app-batch (전환) ──┘                                               │
                                                        decide() ──▶ dispatch_log 기록
                                                        SEND 이면 ──▶ notification 적재 ─▶ SQS v2 ─▶ messaging-lambda ─▶ FCM
```

- 별도 워커를 만들지 않는다. 입구가 이미 한 곳이다.
- 판정 코드를 lib로 빼서 배치가 복제해 쓰는 방식(설계안 A안)은 택하지 않는다. 배치는 내부 API로 전환한다.
- 람다는 계속 DB 없이 보내기만 한다.

### 5-2. 카테고리

10/7 기획의 3종으로 확정한다. 설계안 2절의 4분류 후보(서비스 · 회원 활동 · 커뮤니티 · 광고)는 폐기한다.

| 카테고리 | 기존 토글·컬럼 | 소속 |
| --- | --- | --- |
| 공지 및 이용 안내사항 | `app_push_agreement` | 결제·환불, 공지·변경, G오더, PT, 쿠폰, 락커 안내 |
| 편의사항 | `attendance_reminder_push_agreement` | 출석 요일, 운동 목표, 운동 공유, 배지, 챌린지, 같이운동 |
| 마케팅 정보 | `marketing_push_agreement` | 이벤트·할인 |

- 타입별 소속은 Austin의 [TECH-2589](https://linear.app/suppliesfitness/issue/TECH-2589) 조사 결과(앱 알림 ↔ 수신 동의 컬럼 매핑)를 정본으로 옮긴다.
- 매핑이 없는 타입은 발송을 막는다(설계안 2절). 32개 타입 전부에 소속을 적는 것이 2단계의 완료 조건이다.
- `system_push_agreement`(OS 권한)는 카테고리가 아니라 대상 유효성 검사(토큰 있음)로 다룬다.

### 5-3. 데이터

설계안 3절을 유지하되 아래를 바꾼다.

- `notification_dispatch_log`에 `channel`(`APP_PUSH` / `SMS` / `KAKAO` / `EMAIL`)을 둔다. 1차는 `APP_PUSH`만 적재한다.
- `decision`에 `SKIPPED_NO_MAPPING`을 추가한다.
- `dedupe_key` 규칙을 문서로 고정한다. 예: `attendance-before:plan:{plan_id}:{yyyy-mm-dd}`, `goal-d7:goal:{goal_id}`.
- 보존 기간 90일. 보존이 끝난 행은 집계만 남긴다.

### 5-4. 판정 순서

설계안 4절 그대로 둔다. 단 3번(전체 알림 OFF) 처리에서 "공지 및 이용 안내사항" 예외 여부는 7절의 결정 항목이다.

## 6. 단계와 일정

2026-11-03 시작, 전담 기준 6주. 각 단계는 앞 단계가 끝나면 바로 당긴다.

| 단계 | 기간 | 내용 | 완료 증거 |
| --- | --- | --- | --- |
| 1. 조사 마무리·결정 확정 | 11/3~11/7 | user-app-batch 발송 지점 전수 목록, 트레이너 푸시 구분 방식, 7절 결정 항목의 결정자·기한 확정, Weizen과 8절 경계 합의 | 발송 지점 표, 결정 표 |
| 2. 매핑표와 type 분리 | 11/10~11/14 | lib에 타입 ↔ 카테고리 매핑, `target_type`·`title` 분리, lib minor 발행 | 32개 타입 전부 소속 있음, TECH-2891 완료 |
| 3. 발송 이력 shadow | 11/17~11/26 | `dispatch_log` 테이블, `decide()` 구현, 결과만 기록하고 막지 않음, HQ 조회 API | 운영 일주일 집계: 동의 OFF 발송 건수, 매핑 없음 건수 |
| 4. batch 전환 | 11/27~12/3 | user-app-batch `sendAppPush`를 내부 API로. 람다 v1 경로 0 | 람다 로그 v1 0 |
| 5. 판정 적용 | 12/4~12/10 | 차단 켜기, 배치별 중복 방지를 `dedupe_key`로 교체, 수신 시간대·야간 광고 규칙 | 동의 OFF 발송 0, 중복 0 |
| 6. 안정화·문서 | 12/11~12/12 | 운영 지표 대시보드, CS용 HQ 조회 안내, 설계안 갱신 | 통제판 완료 처리 |

shadow를 한 주 이상 돌린 뒤 차단을 켜는 순서는 고정이다. 결제·환불 같은 공지 카테고리는 차단 대상에서 기본 제외하고 결정이 나면 켠다.

## 7. 결정이 필요한 것

| 항목 | 선택지 | 결정자 | 기한 |
| --- | --- | --- | --- |
| 공지 및 이용 안내사항을 끌 수 있는가 | 못 끔 / 끌 수 있되 결제·환불은 예외 | vonn | 1단계 |
| 수신 시간대 동작 | 버림 / 시간대 끝나면 발송 / 카테고리별 | vonn | 1단계 |
| 광고 야간 동의를 받을지 | 받음 / 안 받음(야간 광고 전면 차단) | vonn · 법무 | 2단계 |
| 기존 회원의 편의사항 기본값 | 기존 출석 약속 동의 값 승계 / 전원 OFF 재동의 | vonn | 2단계 |
| 동의 이력 테이블(법적 증빙) | 둠 / 안 둠 | 법무 | 3단계 |
| 판정 SKIP 시 알림함 적재 | 안 함 / 적재하고 미발송 표시 | Harvey · vonn | 3단계 |
| `notification.type` 영문 키 전환 시 기존 행 호환 | 그대로 두고 새 컬럼 / 일괄 변환 | Weizen · Alan | 2단계 |

결정이 늦으면 설계안의 기본값(끌 수 없음, 버림, 야간 광고 차단, 기존 값 승계, 이력 둠, 적재 안 함)으로 구현하고 차이는 후속 이슈로 격리한다.

## 8. 경계와 협업

| 상대 | 합의할 것 |
| --- | --- |
| Weizen | C안 잔여 중 batch 전환·동의 게이트를 이 프로젝트가 가져가는지. `AppPushQueue` 변경 리뷰. `notification.type` 호환 |
| Austin | TECH-2589 매핑 결과 정본 이관. HQ 회원 상세의 발송 이력 조회 화면 자리 |
| vonn · Harvey | 7절 결정, 수신 시간대 화면 발행 시점 |
| JENNA · 권준혁 | 앱 알림 설정 화면은 변경 없음을 확인. 수신 시간대 화면은 별건 |
| 법무 | 광고 야간 동의, 동의 이력 보존 |

## 9. 위험과 대응

- 서비스 알림 오차단: shadow 한 주 이상, 공지 카테고리는 차단 기본 제외.
- batch 전환 전 이력 누락: 4단계까지 람다 v1 경로가 남는 동안 이력 집계에 "미집계 경로"를 명시한다.
- 람다 중복 저장: 알림함 적재 순서가 바뀌므로 TECH-3182의 `notification_saved` 표시 규칙을 그대로 쓴다.
- 이력 테이블 증가: 하루 약 3.9만 건(TECH-3112 실측) 기준 90일 약 350만 행. 파티션 또는 월 단위 정리 배치를 3단계에 포함한다.
- 결정 지연: 7절 기본값으로 진행.

## 10. 관련 링크

- 설계·현황: [알림개인화 폴더](../알림개인화/)
- C안: [TECH-3112](https://linear.app/suppliesfitness/issue/TECH-3112) · [TECH-3120](https://linear.app/suppliesfitness/issue/TECH-3120) · [TECH-3151](https://linear.app/suppliesfitness/issue/TECH-3151) · [TECH-3162](https://linear.app/suppliesfitness/issue/TECH-3162) · [TECH-3182](https://linear.app/suppliesfitness/issue/TECH-3182)
- 결함·요구: [TECH-2891](https://linear.app/suppliesfitness/issue/TECH-2891) · [TECH-1087](https://linear.app/suppliesfitness/issue/TECH-1087) · [TECH-2842](https://linear.app/suppliesfitness/issue/TECH-2842) · [TECH-1324](https://linear.app/suppliesfitness/issue/TECH-1324) · [TECH-564](https://linear.app/suppliesfitness/issue/TECH-564) · [TECH-565](https://linear.app/suppliesfitness/issue/TECH-565)
- 매핑 조사: [TECH-2589](https://linear.app/suppliesfitness/issue/TECH-2589)
- 1차 프로젝트: [푸시 알림 시스템 업데이트](https://linear.app/suppliesfitness/project/푸시-알림-시스템-업데이트-50d91425ccf4)

## 11. 다음 행동

1. Weizen에게 8절 첫 줄을 묻는다. C안 잔여를 이 프로젝트가 가져가도 되는지, `AppPushQueue` 앞단에 판정을 두는 구조에 이견이 없는지.
2. vonn에게 7절 결정 항목 중 1단계 기한 두 개(공지 OFF 가능 여부, 수신 시간대 동작)를 보낸다.
3. 합의되면 Linear 프로젝트 "알림 시스템 2차"를 만들고 6단계를 마일스톤으로 올린다.
