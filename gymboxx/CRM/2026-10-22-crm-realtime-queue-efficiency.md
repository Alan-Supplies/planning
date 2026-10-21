# 2026-10-22 CRM 실시간 큐(`prodCrmRealtimeUpdateQueue`) 유입 구성과 효율 검토

## 개요

- 조사 일시: 2026-10-22 05:20~06:00 KST
- 계기: 운영 DB 복제본 작업(binlog 보관 시간 설정) 때 CRM SQS 트리거를 껐다 켜면서 새벽에도 메시지가 꾸준히
  들어오는 것을 보고, 무엇이 왜 들어오는지 확인했다
- 대상
  - 큐: `prodCrmRealtimeUpdateQueue` (DLQ `prodCrmRealtimeUpdateDLQ`, `maxReceiveCount` 5)
  - 소비자: `crm-batch-prod-updateInRealtime` Lambda (event source mapping `65819449-c2ec-471b-bf39-be1094d502e9`)
- 조사 중 운영 환경 변경: 없음 (지표·로그 조회와 배포 패키지 읽기만 함)

## 결론

- **하루 약 22만 건 중 80%가 `SAVE_APP_INSTANCE`다.** 회원이 앱에서 멤버십 화면을 열 때마다 1건씩 나간다.
- 이 이벤트는 "회원의 최근 앱 기기 ID"를 기록할 뿐이다. 하루 동안 실제로 필요한 정보는 **회원 약 3.3만 명분**인데,
  메시지는 **1인당 하루 약 5.3번** 같은 내용을 반복한다.
- 결과를 바꾸지 않는 쓰기가 **하루 약 14만 건으로, 큐 전체의 약 65%**다. 실시간으로 처리할 이유가 없다.
- 나머지 20%(바코드 입장, 구매, 가입 등)는 Braze·GA4 마케팅 이벤트로 이어지므로 실시간 처리가 맞다.
- 지금은 평균 처리 시간이 약 0.19초로 안정적이고 Lambda 비용도 작다. 문제는 돈보다 구조다.
  - 7월 적체 장애의 원인이 바로 이 쓰기였다.
  - 의미 없는 트래픽이 운영 DB와 큐의 부하·장애 범위를 키운다.
- **권장: app-server에서 `(userId, appInstanceId)` 조합당 하루 1번만 보내도록 바꾼다.** 수정은 한 곳이고,
  큐 유입이 약 65% 줄어든다.

## 메시지 흐름

```text
gymboxx-app-server  ─┐  SAVE_APP_INSTANCE, BARCODE_CHECK, PURCHASE, USER_SIGNUP,
gymboxx-pass-server ─┤  UPDATE_AGREEMENT, EXERCISE_TAG_ADDED, PT_SESSION_COMPLETE,
gymboxx-user-app-batch ┘ GORDER_ORDER_CHANGED, SURVEY_SUBMITTED, DELETE_USER, MEMBERSHIP_EXPIRE
        │
        ▼
prodCrmRealtimeUpdateQueue ──(5회 실패)──▶ prodCrmRealtimeUpdateDLQ
        │  batch 10, window 5초, 최대 동시성 10
        ▼
crm-batch-prod-updateInRealtime (RealtimeEventRouter 가 type 별로 분기)
        ├─ gymboxx_crm DB 쓰기 (app_instance 등)
        ├─ GA4 Measurement Protocol
        └─ Braze /users/track
```

송신 코드는 모두 각 서비스의 `crm-batch.service.ts`에 있다.

- `gymboxx-app-server`: `src/modules/crm-batch/`, `src/modules/pass/modules/crm-batch/`, `src/modules/kiosk/modules/crm-batch/`, `src/modules/trainer/module/crm-batch/`
- `gymboxx-pass-server`: `src/modules/crm-batch/`
- `gymboxx-user-app-batch`: `handlers/membership-handler/crm-batch.service.ts`

## 주요 관측 결과

### 이벤트 구성 (최근 24시간, Lambda 로그 집계)

| 이벤트 | 건수 | 비율 | CRM 에서 하는 일 | 실시간 필요성 |
| -- | --: | --: | -- | -- |
| `SAVE_APP_INSTANCE` | 175,706 | **80.3%** | `app_instance.last_used_at` 갱신 또는 신규 INSERT | **낮음** |
| `BARCODE_CHECK` | 27,696 | 12.7% | GA4·Braze `barcode_check` 이벤트(첫 방문 여부 포함) | 높음 |
| `PURCHASE` | 4,952 | 2.3% | Braze·GA4 구매 이벤트 | 높음 |
| `GORDER_ORDER_CHANGED` | 4,330 | 2.0% | 무바 속성 재집계 | 중간 |
| `EXERCISE_TAG_ADDED` | 3,742 | 1.7% | 운동 태그 이벤트 | 중간 |
| `UPDATE_AGREEMENT` | 1,307 | 0.6% | 마케팅 동의 변경 반영 | 높음 |
| `MEMBERSHIP_EXPIRE` | 576 | 0.3% | 만료 이벤트 | 높음 |
| `USER_SIGNUP` | 318 | 0.1% | 가입 이벤트 | 높음 |
| `PT_SESSION_COMPLETE` | 298 | 0.1% | PT 완료 이벤트 | 높음 |
| `DELETE_USER` | 9 | 0.0% | 탈퇴 반영 | 높음 |
| **합계** | **218,934** | | | |

### 시간대별 유입 (최근 7일 평균, KST, `NumberOfMessagesSent`)

| 시간 | 시간당 메시지 |
| -- | --: |
| 03~04시 | 약 600 (최저) |
| 05시 | 약 1,150 |
| 06~08시 | 5,000~5,700 |
| 11~16시 | 9,000~12,000 |
| 18~19시 | 약 18,500 (최고) |
| 23시 | 약 5,200 |

7일 합계는 약 140만 건이다. 앱 사용량 곡선과 그대로 겹친다. 새벽에도 24시간 지점의 이른 운동 회원 때문에
메시지가 끊기지 않는다.

### `SAVE_APP_INSTANCE` 상세

**보내는 시점**
- `gymboxx-app-server`의 `GET /:userId/membership`(멤버십 상세/결제관리 조회) 핸들러 안에서 보낸다.
  `src/modules/user/user.controller.ts`의 `sendMessageToSaveAppInstance` 호출이다.
- 요청 헤더의 `app_instance_id`, `device_os`를 담는다. 앱 실행·로그인 같은 시점이 아니라 **조회 API를 부를 때마다** 나간다.

**CRM 에서 하는 일** (`AppInstanceService.saveAppInstance`)
- `(userId, appInstanceId)`로 `findOne` → 있으면 `UPDATE last_used_at`, 없으면 `INSERT`
- 메시지 1건당 쿼리 2번이고, `CRM_WRITE` 연결(primary)로 나간다.

**읽는 곳**
- `getAppInstance(userId)`가 `last_used_at DESC`로 가장 최근 기기 1건을 고른다.
- 이 값은 `BARCODE_CHECK`, PT 완료, 멤버십 이벤트를 GA4로 보낼 때 `app_instance_id`로 쓴다. 다른 용도는 없다.

**중복도** (최근 24시간)

| 항목 | 값 |
| -- | --: |
| 메시지 | 175,697 |
| 고유 회원 | 33,064 |
| 고유 `appInstanceId` | 33,243 |
| 회원 1인당 하루 메시지 | 약 5.3 |

- 회원과 기기가 거의 1:1이다. 기기가 둘 이상인 회원이 드물다는 뜻이다.
- 그래서 `last_used_at`을 하루 여러 번 갱신해도 GA4가 고르는 기기는 바뀌지 않는다.
- 하루 1번만 보내도 결과는 같다. 메시지 175,697건이 약 33,000건으로 줄고, **약 14만 건(큐 전체의 약 65%)이 사라진다.**
- 고유 수는 Logs Insights `count_distinct` 근사값이다.

### 소비자 Lambda 현황 (최근 7일)

| 항목 | 값 |
| -- | -- |
| 호출 | 343,350회 |
| 오류 | 130회 |
| 평균 처리 시간 | 약 188ms (최대 60초 = timeout) |
| 최대 동시 실행 | 5 (상한 10) |
| 설정 | Node.js 22, 1,024MB, timeout 60초, reserved concurrency 10, batch 10, window 5초, partial batch response 꺼짐 |

- 평균 처리 시간이 7월 장애 때의 약 19초에서 약 0.19초로 내려와, 지금은 여유가 있다.
- Lambda 실행량은 주 약 64,000 GB-초로, 비용은 월 수 달러 수준이다. 비용 절감이 이 개선의 주목적은 아니다.

### DLQ

- `prodCrmRealtimeUpdateDLQ`에 **83건**이 남아 있다. 가장 오래된 메시지는 약 13일 전(10월 8일 무렵) 것이다.
- 10-21 오후 77건에서 84건 → 83건으로 거의 그대로이고, 이번 작업으로 늘지 않았다.
- Lambda 에러는 대부분 `Validation failed` 유형이다(10-20~21 이틀간 1,243건, 작업 중 2건).
- 처리하지 않고 둔 건지, 원래 큐로 redrive해야 하는 건지 정해지지 않았다.

## 판단

- **효율이 떨어지는 이유는 실시간 큐 자체가 아니라 `SAVE_APP_INSTANCE`를 보내는 방식이다.**
  - 상태 동기화(이 회원의 기기 ID는 X다)를 이벤트처럼 매 요청마다 흘려보내고 있다.
  - 변하지 않은 상태가 대부분이라 큐·Lambda·DB 쓰기의 약 2/3가 아무 결과도 남기지 않는다.
- 지금 당장 장애가 날 상황은 아니다. 하지만 이 트래픽이 아래 비용을 계속 키운다.
  - **장애 범위**: 7월 적체 장애는 이 UPDATE가 인덱스 없는 전체 스캔을 하면서 시작됐다
    (`gymboxx/2026-07-27-rds-crm-queue-backlog.md`).
  - **운영 작업 제약**: 복제본 재시작 같은 작업 때 SQS 트리거를 꺼야 하는 상시 사용처가 된다. 2026-10-22 작업에서도 껐다.
  - **로그·관측 잡음**: 메시지마다 본문 전체를 로그로 남겨, 하루 로그(약 300MB)의 상당 부분을 이 이벤트가 차지한다.
- 나머지 이벤트(바코드, 구매, 가입, 동의 등)는 Braze 여정과 GA4 분석에 바로 쓰이므로 지금 구조가 맞다.

## 개선안

| 순위 | 안 | 바꿀 곳 | 효과 | 비고 |
| -- | -- | -- | -- | -- |
| 1 | **송신 쪽 중복 제거** — `(userId, appInstanceId)`당 24시간에 1번만 보낸다 | `gymboxx-app-server` | 큐 유입 약 65% 감소, CRM 쓰기·Lambda 호출 감소 | Redis `SET key 1 NX EX 86400`이 성공할 때만 전송. 신규 기기는 첫 요청에 바로 보내므로 GA4 매핑 지연 없음 |
| 2 | **소비 쪽 쿼리 1회로** — `(user_id, app_instance_id)` 유니크 키 + `INSERT ... ON DUPLICATE KEY UPDATE` | `crm-batch` | 남는 메시지의 쿼리 2회 → 1회 | 유니크 키 추가 전 중복 행 정리 필요 |
| 3 | **갱신 생략 조건** — `last_used_at`이 N시간 안이면 UPDATE 생략 | `crm-batch` | DB 쓰기 감소 (큐·Lambda는 그대로) | 1번이 어려울 때의 대안 |
| 4 | **보내는 시점 이동** — 멤버십 조회 대신 앱 실행·로그인 시점 | 앱 + `gymboxx-app-server` | 1번과 비슷 | 앱 배포가 필요해 범위가 큼 |

1번과 2번을 함께 하는 것을 권장한다. 1번만으로도 효과 대부분을 얻는다.

## 확인 필요

- [ ] 운영 `gymboxx_crm.app_instance`에 `(user_id, app_instance_id)` 인덱스가 생겼는지 (7월 조사 당시 PK 외 인덱스 없음)
  ```sql
  SHOW INDEX FROM gymboxx_crm.app_instance;
  ```
- [ ] `app_instance`를 GA4 외에 다른 곳(대시보드, DW, Braze)에서 `last_used_at` 기준으로 쓰는지.
  쓴다면 1번의 하루 1회 주기가 충분한지 확인
- [ ] DLQ 83건 처리 방침(폐기 또는 redrive)

## 조사 방법

**이벤트별 건수** — CloudWatch Logs Insights, 로그 그룹 `/aws/lambda/crm-batch-prod-updateInRealtime`, 최근 24시간

```text
filter @message like /"type": "/
| parse @message /"type": "(?<t>[A-Z_]+)"/
| stats count(*) as n by t
| sort n desc
```

**`SAVE_APP_INSTANCE` 중복도**

```text
filter @message like /SAVE_APP_INSTANCE/
| parse @message /"userId": "?(?<u>\d+)/
| parse @message /"appInstanceId": "(?<a>[^"]*)"/
| stats count(*) as msgs, count_distinct(u) as users, count_distinct(a) as instances
```

**시간대별 유입** — CloudWatch `AWS/SQS` `NumberOfMessagesSent`, `QueueName=prodCrmRealtimeUpdateQueue`, 1시간 단위 7일

**소비자 코드**
- `crm-batch` 레포에 접근 권한이 없어, 배포된 Lambda 패키지(`aws lambda get-function`의 `Code.Location`)를 받아
  `src/main.js.map`의 `sourcesContent`로 원본 TypeScript를 복원해 읽었다.
- 확인한 파일: `src/handlers/update-in-realtime.handler.ts`, `src/realtime-event/realtime-event.router.ts`,
  `src/app-instance/app-instance.service.ts`, `src/user/user.service.ts`(`sendBarcodeCheckEvent`)
