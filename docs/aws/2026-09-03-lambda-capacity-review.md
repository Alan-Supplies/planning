# 2026-09-03 Lambda 용량 분포 점검

## 개요

- 조사 일시: 2026-09-03 18:24~18:40 KST
- AWS 계정: `699016088228`
- 리전: `ap-northeast-2` (서울)
- 분석 구간: 2026-08-31 09:24 ~ 2026-09-03 09:24 UTC (3일)
- 데이터 출처
  - Lambda `list-functions` / `get-function-concurrency` / `get-account-settings`
  - CloudWatch Logs Insights: `filter @type="REPORT"` 의 `@maxMemoryUsed`, `@billedDuration`
  - CloudWatch 메트릭: `AWS/Lambda` Duration, Invocations, Errors, Throttles, ConcurrentExecutions / `AWS/SQS`
- 조사 중 운영 환경 변경: 없음 (전부 읽기 전용 조회)
- 관련 문서: [2026-07-27 운영 RDS 부하 및 CRM 큐 적체 조사](../2026-07-27-rds-crm-queue-backlog.md)

### 단위 주의

CloudWatch Logs 의 `@maxMemoryUsed` 는 바이트이고, REPORT 라인의 `Max Memory Used: N MB`
는 `바이트 / 1,000,000` 이다. 이 문서의 MB 는 REPORT 와 같은 기준(10진)으로
환산했으므로 Lambda 콘솔 값과 직접 비교할 수 있다. `1,048,576` 으로 나누면
사용률이 약 4.9% 낮게 나온다.

## 결론

용량 문제의 본질은 "1024MB 획일 할당" 이 아니다. 대부분의 함수는 할당량의
1/4도 쓰지 않고 놀고 있으며, 라이트사이징으로 얻을 수 있는 금액은 월 $65
수준(그중 79%가 함수 한 개)이라 실익이 작다.

실제 리스크는 정반대 방향의 함수 두 개다.

- `gymboxx-messaging-lambda-prod-sendAppPush` — 호출의 9.6%가 메모리 천장(1024MB)에
  붙어 있고 3일간 `Runtime.OutOfMemory` 7건이 발생했다. 동시에 예약 동시성 10에
  포화되어 스로틀 877건이 발생했다. 즉 메모리와 동시성 양쪽이 동시에 한계다.
- `crm-batch-prod-updateInRealtime` — 전체 Lambda 컴퓨트 비용의 79%를 혼자 쓰고,
  에러율 9.2%, 예약 동시성 10에 중위값 8로 상시 근접해 있다. 2026-07-27 조사에서
  지적된 함수와 동일하며, duration 은 개선됐지만 동시성 포화와 SQS 적체는
  아직 남아 있다.

계정 전체 동시 실행은 최대 34 / 한도 1000 으로 여유가 매우 크다. 병목은 계정
한도가 아니라 개별 함수에 걸린 예약 동시성이다.

## 전체 현황

리전별 함수 수. 실질적으로 전부 서울에 있다.

| 리전 | 함수 수 |
|---|---|
| ap-northeast-2 | 319 |
| us-east-1 | 8 (Datadog 연동 4, 이미지 리사이즈 2, `nextjs-url-modifier`, `tutorial-serverless-dev-hello`) |
| ap-northeast-1 | 1 (`Spoany`) |

이하 모든 수치는 `ap-northeast-2` 319개 기준이다.

### 프로젝트별 함수 수

| 프로젝트 | 함수 수 |
|---|---|
| preppers-admin-serverless | 118 |
| gymboxx-user-app-batch | 105 |
| preppers-kds-serverless | 32 |
| crm-batch | 12 |
| payment-lambda | 8 |
| app-web-socket | 8 |
| s3-handler-lambda | 6 |
| preppers-sales-bot | 6 |
| common-message-lambda | 6 |
| marketing-help-lambda | 4 |
| image-resize-to-save-lambda | 4 |
| 기타 (gymboxx-messaging-lambda, spoany-bot, naver-pt-slackbot, naver-place-ranking 등) | 10 |

### 런타임

| 런타임 | 함수 수 |
|---|---|
| nodejs22.x | 188 |
| nodejs20.x | 124 |
| nodejs18.x | 4 |
| nodejs16.x | 1 |
| python3.8 | 1 |
| python3.13 | 1 |

지원 종료 구간의 런타임을 쓰는 함수 목록.

| 런타임 | 함수 |
|---|---|
| nodejs16.x | `spoany-bot-dev-start` |
| nodejs18.x | `gymboxx-messaging-lambda-{dev,prod}-sendAppPush`, `image-resize-to-save-lambda-{dev,prod}-custom-resource-existing-s3` |
| python3.8 | `aws-cloudwatch-alarm-to-slack` |

`sendAppPush` 가 `nodejs18.x` 라는 점은 아래 조치 항목과 함께 다룬다.
us-east-1 에도 `nextjs-url-modifier` 가 `nodejs16.x` 다.

## 1. 메모리 할당 분포

| 할당 메모리 | 함수 수 | 비중 |
|---|---|---|
| 128 MB | 12 | 3.8% |
| 512 MB | 2 | 0.6% |
| 1024 MB | 295 | 92.5% |
| 2048 MB | 8 | 2.5% |
| 4096 MB | 2 | 0.6% |

- 총 프로비저닝 메모리: 321.5 GB
- 평균 할당: 1,032 MB
- 사실상 1024MB 가 기본값이고 나머지는 예외 케이스다.

1024MB 가 아닌 함수 목록.

| 할당 | 함수 |
|---|---|
| 4096 MB | `gymboxx-user-app-batch-{dev,prod}-saveDailyActiveUser` |
| 2048 MB | `preppers-sales-bot-{dev,prod}-{getDeliverySales,getStoreSales,saveBaeminCancelled}`, `marketing-help-lambda-prod-{getPreppersRankings,getPreppersGoogleRankings}` |
| 512 MB | `naver-pt-slackbot-dev-slackInteractivity`, `spoany-bot-dev-start` |
| 128 MB | `s3-handler-lambda-{dev,prod}-{copyObject,getPresignedUploadUrl,getPresignedUrl}`, `image-resize-to-save-lambda-{dev,prod}-resizeToS3`, `checkDb`, `eks-endpoint-dns-sync`, `aws-cloudwatch-alarm-to-slack`, `dev-preppers-auth-jwt` |

### 임시 스토리지(/tmp)

319개 전부 512 MB 기본값이다. 늘려 쓰는 함수가 없고 이슈도 없다.

### 타임아웃 분포

| 타임아웃 | 함수 수 |
|---|---|
| 300초 | 161 |
| 900초 | 121 |
| 30초 | 17 |
| 60초 | 5 |
| 6초 | 6 |
| 180초 | 3 |
| 3초 | 3 |
| 25초 | 1 |
| 600초 | 2 |

배치성 함수가 많아 300초/900초가 대부분이다.

## 2. 실제 메모리 사용률

3일간 호출이 1건 이상 있었던 함수는 **183개**다. 나머지 136개는 호출 0이다.

| 최대 사용률 | 함수 수 | 비중 |
|---|---|---|
| < 15% | 23 | 12.6% |
| 15 ~ 25% | 117 | 63.9% |
| 25 ~ 40% | 24 | 13.1% |
| 40 ~ 60% | 8 | 4.4% |
| 60 ~ 80% | 3 | 1.6% |
| 80 ~ 90% | 5 | 2.7% |
| >= 90% | 3 | 1.6% |

**140개(76.5%)가 최대 사용률 25% 미만**이다. Node.js 런타임 기본 오버헤드
(100~150MB)만 쓰고 끝나는 API 핸들러가 대부분이다.

### 호출 0인 함수 (3일)

| 프로젝트 | 미호출 함수 수 |
|---|---|
| preppers-admin-serverless | 80 |
| preppers-kds-serverless | 20 |
| gymboxx-user-app-batch | 20 |
| s3-handler-lambda | 4 |
| 기타 | 12 |
| **합계** | **136** |

주 단위/월 단위 배치가 섞여 있으므로 전부 미사용으로 볼 수는 없다. 다만
`preppers-admin-serverless` 118개 중 80개가 3일간 무호출인 것은 별도 정리
검토가 필요하다.

또한 함수는 존재하지만 로그 그룹이 없는 함수가 5개 있다 (한 번도 실행되지
않았을 가능성).

## 3. 천장에 붙은 함수 — 핵심 리스크

최대 사용률 60% 이상인 함수 전체.

| 함수 | 할당 | 최대 사용 | 사용률 | 평균 사용 | 3일 호출 |
|---|---|---|---|---|---|
| `payment-lambda-prod-handlePayment` | 1024MB | 1024MB | 100.0% | 444MB | 29,307 |
| `gymboxx-messaging-lambda-prod-sendAppPush` | 1024MB | 1024MB | 100.0% | 571MB | 147,371 |
| `marketing-help-lambda-prod-getPreppersGoogleRankings` | 2048MB | 2027MB | 99.0% | 1945MB | 3 |
| `image-resize-to-save-lambda-prod-resizeToS3` | 128MB | 115MB | 89.8% | 107MB | 228 |
| `image-resize-to-save-lambda-dev-resizeToS3` | 128MB | 109MB | 85.2% | 109MB | 2 |
| `eks-endpoint-dns-sync` | 128MB | 106MB | 82.8% | 103MB | 288 |
| `gymboxx-user-app-batch-prod-handleExpiredMemberships` | 1024MB | 842MB | 82.2% | 778MB | 3 |
| `s3-handler-lambda-prod-getPresignedUploadUrl` | 128MB | 103MB | 80.5% | 102MB | 328 |
| `s3-handler-lambda-dev-getPresignedUploadUrl` | 128MB | 101MB | 78.9% | 101MB | 2 |
| `marketing-help-lambda-prod-getGymboxxReviews` | 1024MB | 762MB | 74.4% | 658MB | 432 |
| `marketing-help-lambda-prod-getGymboxxRankings` | 1024MB | 760MB | 74.2% | 739MB | 3 |

### 상위 두 함수의 사용량 분포

최대값 하나가 아니라 분포로 보면 심각도가 드러난다.

| 함수 | 호출 | >900MB | >1000MB (천장) | p50 | p95 | p99 |
|---|---|---|---|---|---|---|
| `sendAppPush` | 147,276 | 23,415 (15.9%) | **14,158 (9.6%)** | 520MB | 1022MB | 1023MB |
| `handlePayment` | 29,298 | 1,133 (3.9%) | **609 (2.1%)** | 389MB | 855MB | 1015MB |

`sendAppPush` 는 **호출 10건 중 1건이 메모리 천장에서 실행된다.** p95 가 이미
1022MB 로 할당량과 같다.

### OOM 실제 발생

`gymboxx-messaging-lambda-prod-sendAppPush` 에서 3일간 7건 확인.

```text
REPORT RequestId: fa4e6a1f-083b-573d-ace2-090d2b00a3ac  Duration: 6954.19 ms
  Billed Duration: 6955 ms  Memory Size: 1024 MB  Max Memory Used: 1023 MB
  Status: error  Error Type: Runtime.OutOfMemory
```

발생 시각(UTC): 08-31 09:25, 08-31 13:22, 09-01 06:10, 09-01 12:28,
09-02 10:51, 09-02 13:00, 09-02 13:13.

조회 쿼리:

```text
filter @message like /signal: killed|Runtime.OutOfMemory|Task timed out|Runtime exited/
| stats count() as errs by @log
```

`handlePayment` 는 3일간 OOM 로그가 없다. 다만 p99 가 1015MB 이므로 여유가
사실상 없는 상태로 결제 승인 경로가 돌고 있다.

### 128MB 함수는 오히려 부족하다

| 함수 | 할당 | 최대 사용 | 사용률 |
|---|---|---|---|
| `image-resize-to-save-lambda-prod-resizeToS3` | 128MB | 115MB | 89.8% |
| `eks-endpoint-dns-sync` | 128MB | 106MB | 82.8% |
| `s3-handler-lambda-prod-getPresignedUploadUrl` | 128MB | 103MB | 80.5% |

이미지 리사이즈는 입력 파일 크기에 사용량이 비례하므로, 큰 파일 하나로 OOM 이
발생할 수 있는 구조다.

## 4. 동시성 용량

### 계정 한도

| 항목 | 값 |
|---|---|
| ConcurrentExecutions 한도 | 1,000 |
| 예약 합계 | 72 |
| 미예약 여유 | 928 |
| 실측 최대 동시 실행 (3일, 1분 Maximum) | **34** |
| p99 | 24 |
| p50 | 11 |

계정 한도의 3.4% 만 사용 중이다. 계정 레벨 증설은 필요 없다.

### 예약 동시성 설정 함수

| 함수 | 예약값 | 실측 최대 | p99 | p50 |
|---|---|---|---|---|
| `gymboxx-messaging-lambda-prod-sendAppPush` | 10 | **10** | **10** | 3 |
| `crm-batch-prod-updateInRealtime` | 10 | **10** | **10** | **8** |
| `preppers-kds-serverless-prod-convertOrderSheetToObject` | 10 | 3 | 2 | 1 |
| `crm-batch-prod-updateUser` | 2 | 1 | 1 | 1 |
| `gymboxx-messaging-lambda-dev-sendAppPush` | 10 | - | - | - |
| `crm-batch-dev-updateInRealtime` | 10 | - | - | - |
| `preppers-kds-serverless-dev-convertOrderSheetToObject` | 10 | - | - | - |
| `crm-batch-dev-updateUser` | 2 | - | - | - |
| `crm-batch-{dev,prod}-updateCurrentMembership` | 각 1 | - | - | - |
| `crm-batch-{dev,prod}-updateMembershipStatistics` | 각 1 | - | - | - |
| `crm-batch-{dev,prod}-updateNotStartedMembership` | 각 1 | - | - | - |
| `crm-batch-{dev,prod}-updateUpsellProductStatistics` | 각 1 | - | - | - |

프로비저닝 동시성(항상 warm)은 설정된 함수가 없다.

### 스로틀

3일간 스로틀이 발생한 함수는 단 하나다.

| 함수 | 스로틀 |
|---|---|
| `gymboxx-messaging-lambda-prod-sendAppPush` | **877** |

계정 여유가 928인데도 스로틀이 나는 이유는 자기 예약값 10 때문이다. 즉
푸시 발송이 스스로 걸어둔 한도에 막혀 밀리고 있다.

## 5. 에러

3일간 에러 상위 함수.

| 함수 | 에러 | 호출 | 에러율 |
|---|---|---|---|
| `crm-batch-prod-updateInRealtime` | 12,803 | 138,606 | **9.2%** |
| `crm-batch-dev-updateInRealtime` | 667 | - | - |
| `spoany-bot-dev-start` | 216 | 216 | 100% |
| `common-message-lambda-prod-sendTextMessage` | 155 | 4,789 | 3.2% |
| `gymboxx-messaging-lambda-prod-sendAppPush` | 104 | 147,371 | 0.07% |
| `gymboxx-user-app-batch-dev-sendWorkoutAlarm` | 12 | 440 | 2.7% |
| `gymboxx-user-app-batch-dev-sendPushPTOrderReview` | 12 | - | - |
| `gymboxx-user-app-batch-dev-sendPushPTHistoryReview` | 12 | - | - |
| `app-web-socket-dev-messageToOne` | 10 | - | - |
| `preppers-sales-bot-dev-getDeliverySales` | 9 | 9 | 100% |
| `naver-place-ranking-dev-getShakerRankings` | 9 | 9 | 100% |
| `preppers-admin-serverless-prod-saveHourlyPlatformSalesByRange` | 7 | 8 | 87.5% |

`spoany-bot-dev-start`, `preppers-sales-bot-dev-getDeliverySales`,
`naver-place-ranking-dev-getShakerRankings` 는 호출 전량이 실패다. dev 환경
방치 함수로 보이지만 확인이 필요하다.

### 타임아웃 의심

`app-web-socket-prod-messageToOne` 에서 3일간 1건이 **정확히 900,000ms**
(타임아웃 900초 상한)를 소진했다. 이때 메모리 사용은 399MB(1024MB 중)뿐이므로
메모리 문제가 아니라 hang 이다.

```text
2026-08-31 10:20:55  billedDuration=900000  memMB=399.6
  requestId=9cf86bac-e4b7-4610-aa79-51285734cd19
```

## 6. 비용

3일 실측 → 30일 환산(x10) 기준.

| 항목 | 값 |
|---|---|
| 3일 총 GB-초 | 1,566,849 |
| 월 환산 GB-초 | 약 15,668,000 |
| 월 컴퓨트 비용 추정 | **약 $261** (요청료 별도) |

### GB-초 상위 15

| 함수 | 할당 | 3일 GB-초 | 3일 호출 | 3일 실행시간 |
|---|---|---|---|---|
| `crm-batch-prod-updateInRealtime` | 1024MB | **1,233,532 (79%)** | 138,606 | 342.6h |
| `app-web-socket-prod-messageToOne` | 1024MB | 125,164 | 88,877 | 34.8h |
| `gymboxx-messaging-lambda-prod-sendAppPush` | 1024MB | 102,847 | 147,334 | 28.6h |
| `payment-lambda-prod-handlePayment` | 1024MB | 24,763 | 29,304 | 6.9h |
| `crm-batch-prod-updateMembershipStatistics` | 1024MB | 10,409 | 15 | 2.9h |
| `marketing-help-lambda-prod-getGymboxxReviews` | 1024MB | 8,320 | 432 | 2.3h |
| `gymboxx-user-app-batch-prod-tryRenewMemberships` | 1024MB | 5,562 | 20 | 1.5h |
| `crm-batch-prod-updateUser` | 1024MB | 4,820 | 6 | 1.3h |
| `app-web-socket-prod-websocketConnect` | 1024MB | 4,382 | 110,047 | 1.2h |
| `marketing-help-lambda-prod-getPreppersGoogleRankings` | 2048MB | 3,904 | 3 | 0.5h |
| `preppers-kds-serverless-prod-convertOrderSheetToObject` | 1024MB | 2,936 | 9,724 | 0.8h |
| `crm-batch-prod-updateUpsellProductStatistics` | 1024MB | 2,702 | 6 | 0.8h |
| `gymboxx-user-app-batch-prod-updateGymFoodOperationStatus` | 1024MB | 2,554 | 144 | 0.7h |
| `payment-lambda-prod-getBillKey` | 1024MB | 2,428 | 3,874 | 0.7h |
| `preppers-admin-serverless-prod-saveHourlyPlatformSalesByRange` | 1024MB | 2,351 | 8 | 0.7h |

**`crm-batch-prod-updateInRealtime` 한 개가 전체의 79%** 다. 호출 138,606건에
실행시간 342.6시간 → 건당 평균 8.9초다. "realtime" 이라는 이름에 비해 길다.

참고로 2026-07-27 조사 당시 평균 duration 은 약 18.9초였다. 8.9초로 절반 이하로
줄었으나 여전히 예약 동시성 10을 상시 점유한다.

### 라이트사이징 잠재 절감

"최대 사용량 x 1.4 를 128MB 배수로 올림" 을 목표값으로 계산한 결과.

- 후보 172개
- 이론 절감: 전체의 25.0% = **월 약 $65**
- 그중 `crm-batch-prod-updateInRealtime` 하나가 월 $51.40 (79%)

| 함수 | 현재 → 목표 | 최대 사용 | 월 절감 |
|---|---|---|---|
| `crm-batch-prod-updateInRealtime` | 1024 → 768MB | 465MB | $51.40 |
| `app-web-socket-prod-messageToOne` | 1024 → 640MB | 429MB | $7.82 |
| `crm-batch-prod-updateMembershipStatistics` | 1024 → 640MB | 389MB | $0.65 |
| `app-web-socket-prod-websocketConnect` | 1024 → 256MB | 128MB | $0.55 |
| `gymboxx-user-app-batch-prod-tryRenewMemberships` | 1024 → 640MB | 431MB | $0.35 |
| `preppers-kds-serverless-prod-convertOrderSheetToObject` | 1024 → 384MB | 228MB | $0.31 |
| `payment-lambda-prod-getBillKey` | 1024 → 256MB | 158MB | $0.30 |
| `crm-batch-prod-updateUser` | 1024 → 640MB | 386MB | $0.30 |
| `app-web-socket-prod-websocketDisconnect` | 1024 → 256MB | 122MB | $0.29 |
| `preppers-admin-serverless-prod-saveHourlyPlatformSalesByRange` | 1024 → 384MB | 252MB | $0.24 |
| (이하 162개 합계) | | | 약 $3 |

상위 2개를 제외한 170개를 전부 조정해도 월 $6 수준이다.

**주의: Lambda 는 메모리에 비례해 CPU 가 배정된다.** 1,769MB 에서 1 vCPU 이므로
1024MB 는 약 0.58 vCPU 다. 1024 → 256MB 로 내리면 CPU 가 1/4이 되어 duration 이
늘고 절감이 상쇄되거나 역전될 수 있다. CPU 바운드 여부를 모르는 상태에서
일괄 축소는 권하지 않는다.

## 7. 코드 스토리지

| 항목 | 값 |
|---|---|
| 사용량 | 47.1 GB |
| 한도 | 85 GB (91,268,055,040 바이트) |
| 사용률 | **55.4%** |
| 현재 `$LATEST` 코드 합계 | 8.84 GB |

차액 약 38 GB 는 과거 버전 누적이다. 배포가 잦은
`preppers-admin-serverless`(118개), `gymboxx-user-app-batch`(105개)가 계속
쌓이는 구조다. 아직 여유는 있으나 미사용 버전 정리 정책이 없다.

### 코드 크기 상위

| 크기 | 함수 |
|---|---|
| 92.3 MB | `naver-place-ranking-dev-getShakerRankings` |
| 81.2 MB | `preppers-sales-bot-{dev,prod}-{getDeliverySales,getStoreSales,saveBaeminCancelled}` |
| 75.8 MB | `marketing-help-lambda-prod-{getPreppersRankings,getPreppersGoogleRankings,getGymboxxReviews}` |

zip 직접 업로드 한도(50MB)를 넘으므로 S3 또는 컨테이너 이미지 경유로 배포된
함수들이다. Chromium/Playwright 계열 의존성이 포함된 것으로 추정된다.

## 8. 로그 스토리지

| 항목 | 값 |
|---|---|
| `/aws/lambda/` 로그 그룹 수 | 341 |
| 누적 저장량 | **120.66 GB** |
| 보존기간 미설정(무기한) | **340개** |
| 보존기간 설정(30일) | 1개 |

### 저장량 상위 10

| 저장량 | 로그 그룹 |
|---|---|
| 27.56 GB | `gymboxx-messaging-lambda-prod-sendAppPush` |
| 27.27 GB | `crm-batch-prod-updateInRealtime` |
| 11.42 GB | `app-web-socket-prod-websocketConnect` |
| 9.00 GB | `app-web-socket-prod-messageToOne` |
| 8.99 GB | `app-web-socket-prod-websocketDisconnect` |
| 7.33 GB | `preppers-kds-serverless-dev-convertOrderSheetToObject` |
| 7.14 GB | `preppers-kds-serverless-prod-convertOrderSheetToObject` |
| 6.76 GB | `payment-lambda-prod-handlePayment` |
| 1.78 GB | `crm-batch-prod-updateUser` |
| 1.36 GB | `crm-batch-prod-updateMembershipStatistics` |

상위 2개가 전체의 45%다. 보존기간이 없어 계속 증가한다.

## 9. CRM 큐 현황 (2026-07-27 조사 후속)

조사 시점 `prodCrmRealtimeUpdateQueue` 상태.

| 항목 | 2026-07-27 | 2026-09-03 |
|---|---|---|
| visible messages | 약 25,800 | **25,501** |
| in-flight | 90~100 | 90 |
| 가장 오래된 메시지 | 약 67분 | 3일 최대 **194분** |
| Visibility timeout | 60초 | 60초 |
| Message retention | 1일 | 1일 |
| DLQ | 없음 | **있음** (`prodCrmRealtimeUpdateDLQ`, maxReceiveCount 5) |
| DLQ 적재 | - | 46건 |
| Lambda 평균 duration | 약 18.9초 | 약 8.9초 |
| Lambda 최대 동시성 | 10 포화 | 10 포화 (p50 8) |

3일 처리량 추이:

- 전송 776,357건 / 삭제 784,270건 → 평균적으로는 처리량이 유입을 따라간다
- visible 메시지: 최대 48,427 / 최소 0 / 평균 10,273

즉 상시 적체가 아니라 **버스트성 적체**다. 유입 스파이크가 오면 동시성 10
상한 때문에 최대 3시간 이상 지연이 발생하고, 이후 서서히 배수된다. 조사 시점의
25,501건은 진행 중인 버스트다.

DLQ 도입과 duration 개선(18.9초 → 8.9초)은 7월 조사의 권고가 반영된 결과로
보인다. 다만 동시성 포화와 9.2% 에러율은 해소되지 않았다.

## 권장 조치

### 1. `gymboxx-messaging-lambda-prod-sendAppPush` (최우선)

- 메모리 1024 → 2048MB
- 예약 동시성 10 → 상향 (미예약 여유 928, 계정 실측 피크 34이므로 증설 부담 없음)

근거와 비용:

- 호출의 9.6%가 천장에서 실행되고 실제 OOM 7건 발생 중이다. 푸시 유실이다.
- 스로틀 877건도 자기 예약값 때문이며 계정 여유와 무관하다.
- 이 함수는 전체 GB-초의 6.6%뿐이라 메모리를 2배로 올려도 월 약 +$17 수준이다.
- 런타임이 `nodejs18.x` 라 함께 업그레이드를 검토한다.

주의: 예약 동시성을 올리면 하위 시스템(푸시 프로바이더, DB) 부하가 함께
증가한다. 메모리를 먼저 올려 OOM 을 끊고, 동시성은 하위 부하를 보며 단계적으로
올린다.

### 2. `payment-lambda-prod-handlePayment`

- 메모리 1024 → 1536MB 이상

결제 승인 경로에서 p99 1015MB / 최대 1024MB 는 방치할 자리가 아니다. 아직 OOM
로그는 없으나 여유가 없다. GB-초 비중이 1.6%라 비용 영향도 미미하다.

### 3. `crm-batch-prod-updateInRealtime`

메모리 조정보다 아래를 먼저 본다.

- 에러 12,803건 / 138,606건 = 9.2% 의 원인 분류 (7월 조사에서는 payload
  validation 실패와 Braze 400 이 주 원인이었다. 동일 원인인지 확인)
- 건당 평균 8.9초의 잔여 원인. 7월에 지적된 `app_instance` 인덱스가 실제로
  적용되었는지, 다른 쿼리가 남아 있는지 확인
- 위 두 개가 해소되면 동시성 포화와 SQS 3시간 지연, 그리고 전체 비용의 79%가
  같이 내려간다

메모리 축소(1024 → 768MB, 월 $51 절감)는 duration 개선 이후에 검토한다. CPU 가
줄면 duration 이 늘어 동시성 포화를 악화시킬 수 있다.

### 4. `app-web-socket-prod-messageToOne`

900초 타임아웃 소진 1건의 원인을 확인한다. 메모리가 아니라 hang 이므로
타임아웃 상향은 답이 아니다. 15분간 동시성 1슬롯을 점유한다.

### 5. 128MB 함수 상향 검토

- `image-resize-to-save-lambda-{dev,prod}-resizeToS3`: 128 → 512MB
  (입력 파일 크기 비례, 89.8% 사용 중)
- `eks-endpoint-dns-sync`, `s3-handler-lambda-*-getPresignedUploadUrl`:
  128 → 256MB

이 함수들은 호출량이 적어 비용 영향이 사실상 없다.

### 6. dev 환경 전량 실패 함수 정리

`spoany-bot-dev-start`(216/216), `preppers-sales-bot-dev-getDeliverySales`(9/9),
`naver-place-ranking-dev-getShakerRankings`(9/9) 는 호출 전량이 실패한다.
사용하지 않으면 트리거를 끄고, 사용하면 고친다. 실패 호출도 과금되고 로그도
쌓인다.

### 7. 로그 보존기간 설정

340개 로그 그룹이 무기한 보존이며 누적 120.66 GB 다. prod 90일 / dev 14일 등의
정책을 일괄 적용한다. 상위 2개(`sendAppPush`, `crm-batch-prod-updateInRealtime`)
만으로 55 GB 다.

### 8. 하지 않기를 권하는 것

- **170개 함수 일괄 라이트사이징**: 상위 2개를 뺀 절감은 월 $6 수준이고,
  메모리 축소는 CPU 축소를 동반해 duration 증가로 역전될 수 있다. 품과 리스크
  대비 실익이 없다.
- **계정 동시성 한도 증설**: 실측 피크 34 / 한도 1000 이다. 필요 없다.

## 재현 쿼리

### 메모리 사용률 (CloudWatch Logs Insights)

로그 그룹은 쿼리당 최대 50개이므로 나눠 실행한다.

```text
filter @type="REPORT"
| stats count() as inv,
        max(@maxMemoryUsed)/1000000 as maxMB,
        avg(@maxMemoryUsed)/1000000 as avgMB,
        max(@billedDuration) as maxDur
  by @log
```

### 사용량 분위 분포

```text
filter @type="REPORT"
| fields @maxMemoryUsed/1000000 as m
| stats count() as inv, sum(m>900) as over900, sum(m>1000) as over1000,
        pct(m,50) as p50, pct(m,95) as p95, pct(m,99) as p99
  by @log
```

### OOM / 타임아웃

```text
filter @message like /signal: killed|Runtime.OutOfMemory|Task timed out|Runtime exited/
| stats count() as errs by @log
```

### 함수 스펙 덤프

```bash
aws lambda list-functions --region ap-northeast-2 \
  --query 'Functions[].[FunctionName,MemorySize,EphemeralStorage.Size,Timeout,Runtime,CodeSize]' \
  --output text
```

### 예약 동시성 조회 (일괄)

```bash
aws lambda list-functions --region ap-northeast-2 \
  --query 'Functions[].FunctionName' --output text | tr '\t' '\n' \
| xargs -P 12 -I{} bash -c '
    v=$(aws lambda get-function-concurrency --region ap-northeast-2 \
        --function-name "$1" --query ReservedConcurrentExecutions --output text)
    [ "$v" != "None" ] && printf "%s\t%s\n" "$1" "$v"' _ {}
```

### GB-초 계산 (CloudWatch 메트릭, Insights 비용 없음)

`AWS/Lambda` 의 `Duration`(Sum) 과 `Invocations`(Sum) 을 `get-metric-data` 로
일괄 조회한다. 쿼리는 호출당 최대 500개다.

```text
GB-초 = Duration_Sum(ms) / 1000 * (MemorySize(MB) / 1024)
월 비용 = GB-초 * 0.0000166667 USD
```

## 남은 확인 항목

- `crm-batch-prod-updateInRealtime` 에러 12,803건의 실제 메시지 분류
- `gymboxx_crm.app_instance` 인덱스 적용 여부 (7월 권고 항목)
- `app-web-socket-prod-messageToOne` 900초 hang 의 원인
- `preppers-admin-serverless` 118개 중 3일 무호출 80개의 실사용 여부
- 로그 그룹은 있으나 함수가 없는 고아 로그 그룹 (341 - 319 + 5 = 27개 추정)
