# preppers-kds-serverless dev 스테이지 제거 검토

- 작성: 2026-10-27
- 상태: 검토 완료
- 대상: `suppliesfitness/preppers-kds-serverless` 의 `dev` 스테이지 (Lambda 16개, API Gateway `h734u4op6b`, SQS `devOrderSheetQueue`·`devOrderSheetDLQ`)
- 계기: TECH-1470 을 닫으면서(대체됨) dev 스테이지를 계속 둘지 검토했다

## 결론

**dev 스테이지는 개발 용도로는 죽어 있고, 운영에 꼭 필요한 의존도 없다. 다만 지금 바로 스택째 지우지는 않는다.**

dev 를 바라보는 것은 아래 세 가지다.

| 호출하는 쪽 | 대상 | 처리 |
| --- | --- | --- |
| 라즈베리파이 부팅 알림 | dev `/notify-status` | **당분간 유지** (결정됨) |
| 라즈베리파이 영수증 전송 | `devOrderSheetQueue` (prod 큐와 이중 발행) | 파이 코드에서 dev 발행 제거 후 큐 삭제 |
| Windows 수신기 `KioskReceiver`·`PosSerial` (매장 PC 2대) | dev `/bill-receiver-auth` | 오래된 테스트 프로그램으로 쓸모가 없다(결정됨). 엔드포인트를 바로 제거한다 |

`/notify-status` 를 당분간 dev 에 남기기로 했으므로, **dev 스테이지는 그동안 `notifyStatus` 하나를 위해 남는다.** 나머지 함수와 dev 큐는 그 전에 정리할 수 있다.

더 급한 건 `/bill-receiver-auth` 다. 고정 문자열 하나만 맞추면 **`IAMFullAccess` 가 붙은 IAM 사용자 키를 돌려준다.** prod 스테이지에도 같은 엔드포인트가 있다. dev 정리와 상관없이 먼저 처리한다. 자세한 내용은 「보안」에 정리했다.

## dev 스테이지 현재 상태

- 2026-09-29 배포(kds-lib 2.33.0, #502/#503) 이후 dev Lambda 16개 모두 **VPC 연결이 없다.** main 과 develop 어디에도 `custom.vpcConfig.dev` 가 없어서, 배포하면서 VPC 연결이 떨어졌다.
- dev DB 엔드포인트 `db.preppers.dev.supp.kr` 는 사설 존 별칭이라 VPC 밖에서는 찾을 수 없다. 그래서 DB 를 쓰는 dev 함수는 `getaddrinfo ENOTFOUND` 로 실패한다.
- `dev-convertOrderSheetToObject` 는 9/27 이후 24,412회 실행 중 21,478회 실패했다. `devOrderSheetDLQ` 에는 **947건**이 쌓여 있다 (2026-10-27 기준). 메시지는 매장 영수증 원문이다.
- dev 스테이지로 개발·테스트를 하는 사람은 없다(사용자 확인). 그래서 dev VPC 는 **복구하지 않는다.**
- `notifyStatus` 는 DB 를 쓰지 않고 슬랙만 보내므로 VPC 없이도 동작한다(9/27 이후 7회 실행, 오류 0).

## 함수별 호출 현황 (CloudWatch `Invocations`, 30일 단위 합계)

구간: A = 07-29 ~ 08-27, B = 08-28 ~ 09-26, C = 09-27 ~ 10-26. 빈칸은 0이다.

| 함수 | 트리거 | dev A / B / C | prod A / B / C | 비고 |
| --- | --- | --- | --- | --- |
| convertOrderSheetToObject | SQS | 108,941 / 63,142 / 24,412 | 108,877 / 63,142 / 10,096 | dev 는 파이가 이중 발행. C 구간 dev 실패 21,478 |
| storeSignIn | POST /signIn | 31 / 18 / | 1,240 / 783 / 455 | |
| createOrder | POST /order | / / 9 | 218 / 188 / 184 | dev 9회 전부 실패 |
| authBillReceiver | POST /bill-receiver-auth | 113 / 103 / 124 | | **dev 만 호출됨** — Windows 수신기 부팅 시 |
| notifyStatus | POST /notify-status | 41 / 20 / 7 | | **dev 만 호출됨** — 파이 부팅 알림 |
| getDidImages | GET /did-images | | 171,845 / 89,315 / 28,223 | |
| openOrderProduct | POST /slack/order-product | | 129 / 143 / 104 | |
| openCardRegistration | POST /slack/card-registration | | 9 / 12 / 3 | |
| interactivity | POST /slack/interactivity | 1 / / | 128 / 131 / 98 | |
| createBillingKey | (Lambda invoke) | | 13 / 13 / 5 | interactivity 가 호출 |
| orderProduct | POST /order-product | | | 90일간 0 |
| testPreppersOrder | POST /test-order | | | 90일간 0, **prod 에도 공개 HTTP 경로** |
| convertOrderSheetToObjectTest | 없음 | | | 90일간 0 |
| testConvert / testConvertFile / testConvertBills | 없음 | | | 90일간 0 |

## `authBillReceiver` 사용처

**매장 PC 2대에 설치된 Windows 수신기(`preppers-bill-receiver`)가 부팅할 때마다 호출한다.** 오래된 테스트 프로그램인데 시작 프로그램이나 서비스로 등록된 채 남아 있다.

### 근거

dev API Gateway 는 액세스 로그가 꺼져 있어서 호출자 IP 를 바로 볼 수 없다. 대신 두 기록을 시각으로 맞췄다.

1. **호출 시각.** `dev-authBillReceiver` 는 매일 2회, 회마다 1분 안에 3번씩 호출된다. 대부분 07~08시(KST)다.
   ```
   2026-10-27 07:47 ×3, 08:01 ×3
   2026-10-26 07:31 ×3, 08:01 ×3
   2026-10-25 07:30 ×3, 11:01 ×3
   ```
2. **키 사용 기록(CloudTrail).** 같은 시각에 이 엔드포인트가 돌려주는 키(`raspberry` 사용자)로 **Windows 10 + AWS .NET SDK** 클라이언트가 CloudWatch Logs 에 접속한다.

| 시각 (KST) | IP | 하는 일 |
| --- | --- | --- |
| 10-27 07:47 | 221.148.97.153 | 로그 그룹 `preppers-kiosk-test` 스트림 `KioskReceiver` 생성, `preppers-test` 스트림 `PosSerial` 기록 |
| 10-27 08:02 | 220.70.89.154 | 로그 그룹 `preppers-kiosk-test` 스트림 `KioskReceiver-SNUDONGWON-2026-10-27` 생성 |

같은 시간대에 라즈베리파이 2대(`203.234.156.61`, `59.16.204.198`, `aws-sdk-js` / linux rpi)도 같은 키를 쓴다. 하지만 파이는 `/bill-receiver-auth` 를 부르지 않는다. 키를 env 에 직접 갖고 있고, 레포 전체 브랜치 이력에도 호출 코드가 없다.

### 수신기가 실제로 하는 일

`KioskReceiver/SocketServerWorker.cs` 의 동작 순서:

1. 부팅하면 `/bill-receiver-auth` 로 키를 받는다.
2. TCP 포트를 연다.
3. 키오스크가 보낸 영수증 바이트를 **CloudWatch Logs 에 `[RECEIVED]` 로 남기기만 한다.** SQS 전송이나 주문 처리는 하지 않는다.

`preppers-kiosk-test` 의 `[RECEIVED]` 기록:

- 2026-06 ~ 07-06 은 SNUDONGWON 에서 매일 수백~수천 건이 들어왔다.
- **그 뒤로는 2026-09-21 에 15건이 들어온 게 전부다.** 지금은 부팅해서 테스트 로그만 남긴다.

정리하면 운영 주문 경로와 관계없는 수집 테스트 프로그램이다. **엔드포인트를 지워도 주문 처리에는 영향이 없다.** 수신기는 부팅 때 키를 못 받아 기동에 실패하고 끝난다. 쓸모없는 프로그램이므로 대체 경로를 만들지 않는다.

PC 에서 프로그램을 내리는 일은 필수가 아니다. 엔드포인트가 사라지면 매일 기동에 실패할 뿐이다. 매장 방문 등 기회가 있을 때 지운다.

## 보안 — `authBillReceiver` 가 IAM 키를 돌려준다

`handler/authBillReceiver.ts` 동작:

- 바디의 `secretKey` 가 코드에 하드코딩된 고정 문자열과 같으면
- **하드코딩된 AWS access key / secret key 를 응답으로 돌려준다.**

이 키의 주인:

- IAM 사용자 `raspberry`, 키 `AKIA2FQE…AMNH` — 2023-08-04 생성, 지금도 Active
- 붙어 있는 정책: **`IAMFullAccess`**, `AmazonSQSFullAccess`, `CloudWatchLogsFullAccess`, `CloudWatchAgentAdminPolicy`, `CloudWatchAgentServerPolicy`, `AmazonSSMManagedInstanceCore`, `IAMUserChangePassword`, `PreppersRasberryPiAdmin`
- 쓰는 곳: 라즈베리파이 2대(env 에 직접 보관), Windows 수신기 2대(엔드포인트로 받아 감)

문제는 세 가지다.

1. 키와 비밀번호가 git 기록에 평문으로 남아 있다(레포에 접근할 수 있으면 누구나 읽는다).
2. 엔드포인트가 API Gateway 에 인증 없이 열려 있고, 비밀번호는 고정 문자열 하나뿐이다.
3. `IAMFullAccess` 는 사용자를 만들고 정책을 붙일 수 있는 권한이라, 이 키를 손에 넣으면 **계정 전체를 장악할 수 있다.**

조치 방향(별도 티켓):

1. **dev·prod 의 `authBillReceiver` 를 제거한다.** 수신기는 쓰지 않으므로 대체 경로를 만들 필요가 없다.
2. `raspberry` 사용자에서 `IAMFullAccess` 를 떼고, 파이가 실제로 쓰는 권한만 남긴다(`sqs:SendMessage` 두 큐, CloudWatch Logs 쓰기 정도). 떼기 전에 이 키로 IAM API 를 부른 기록이 있는지 CloudTrail 로 확인한다.
3. 키가 유출됐다고 보고 교체한다. 새 키를 파이 2대의 env 에 넣은 뒤 기존 키를 비활성화한다. 파이마다 별도 사용자나 역할로 나누는 것도 이때 검토한다.

## 라즈베리파이 쪽 dev 의존

로컬 경로: `/Users/sungwookkim/workspace/supplies/preppers-kds-raspberrypi`

| 위치 | 내용 | 처리 |
| --- | --- | --- |
| `scripts/boot_notify.sh:10` | `NOTIFY_ENDPOINT` 기본값이 dev `/notify-status` | 당분간 유지. 나중에 옮길 때는 env 로 prod 주소를 덮어쓰거나 기본값을 바꾼다 |
| `queue.js` `sendDataToDevQueue` | 영수증마다 `QUEUE_URL_DEV` 로 `TEST_SHOP_ID` 를 달아 한 번 더 보낸다 | 호출을 코드에서 뺀다. `QUEUE_URL_DEV` 를 비우기만 하면 영수증마다 전송 실패 → 재시도 → `ALARM_CHANNEL` 슬랙 알림이 나간다 |

## 그 밖의 dev 참조 (개발 설정, 운영 영향 없음)

- `platform-iac` `stacks/eks/dev-eks/k8s/gymboxx.tf:133` — gymboxx dev 앱 서버의 `PREPPERS_ORDER_URL` 이 dev API. dev `orderProduct` 는 90일간 0회라 실제로 쓰이지 않는다
- `preppers-kds-client` `.env.development`, `.env.test`
- `preppers-kds-serverless` `test/**/*-e2e.test.ts`, `handler/preppersApp/interactivity.ts:10` 주석

## 제거 순서 제안

### 1단계 — 보안 (먼저, dev 정리와 별개)

- 「삭제할 람다」 7개 함수 제거 배포 (`authBillReceiver` 포함)
- `raspberry` 키 권한 축소와 교체
- (선택) 매장 PC 2대(`221.148.97.153`, `220.70.89.154` = SNUDONGWON)에서 `KioskReceiver`·`PosSerial` 서비스와 시작 프로그램을 내린다

### 2단계 — dev 큐 이중 발행 중단

1. 파이 코드에서 `sendDataToDevQueue` 호출을 제거하고 파이 2대에 배포한다
   - **코드 반영 완료 (2026-10-27).** `preppers-kds-raspberrypi` #47(main)·#48(develop), 커밋 `5eb7ee8` — `socket-server.js`·`src/serialServer/serialServer.js` 에서 호출 제거
   - **파이 배포는 아직이다.** 머지 뒤에도 `devOrderSheetQueue` 유입이 prod 와 같은 수준으로 이어졌다(10-27 16시 13건, 17시 8건 KST). 배포 파이프라인이 없어 파이마다 `git pull` 후 `pm2 restart` 가 필요하다
   - pm2 진입점이 아닌 `serial-port-legacy.js`·`socket-server copy.js`·`test.js` 에는 dev 전송이 남아 있다. 파이가 이 파일로 돌고 있지 않은지 배포할 때 `pm2 ls` 로 확인한다
2. `devOrderSheetQueue` 의 `NumberOfMessagesSent` 가 일주일 이상 0 인지 확인한다
3. `devOrderSheetDLQ` 의 947건은 영수증 원문이다. prod 쪽은 정상 처리됐으므로 재처리하지 않고 큐와 함께 지운다

### 3단계 — dev 스테이지를 `notifyStatus` 만 남기고 축소, 또는 그대로 두기

`/notify-status` 를 유지하는 동안 선택지는 둘이다.

| 방법 | 장점 | 단점 |
| --- | --- | --- |
| dev 스테이지를 그대로 둔다 | 할 일이 없다 | 쓰지 않는 dev Lambda 15개와 실패하는 함수가 계속 남는다 |
| dev 배포에서 `notifyStatus` 만 남긴다 | dev 에 남는 것이 실제로 쓰는 것뿐이다 | `serverless.yml` 에 스테이지별 함수 분기가 생긴다 |

dev 큐 소비자(`convertOrderSheetToObject`)는 2단계 뒤 메시지가 없어지면 해가 없으므로, **2단계까지 하고 dev 스테이지는 그대로 두는 것**을 권한다. `notifyStatus` 를 옮길 때 한꺼번에 지운다.

### 4단계 — dev 스테이지 삭제 (`/notify-status` 이전 후)

- 파이 `NOTIFY_ENDPOINT` 를 prod `/notify-status`(`89rho5lt8c`)로 바꾼다
- 「그 밖의 dev 참조」를 정리한다
- `serverless remove --stage dev` 로 CloudFormation 스택을 지운다(Lambda 16개, API Gateway, dev SQS 2개)
- `serverless.yml` `iamRoleStatements` 의 `…-dev-createBillingKey` ARN, `env.yml` 의 `dev`·`local` 블록, Secrets Manager `preppers-kds-serverless/dev/credentials` 정리 여부를 정한다. `local` 은 dev 시크릿을 보므로 로컬 실행 경로를 남길지 함께 정한다
- 로그 그룹 `/aws/lambda/preppers-kds-serverless-dev-*` 은 스택과 별개라 따로 지운다

## 삭제할 람다

함수는 `serverless/*.yml` 하나로 dev·prod 가 같이 정의된다. yml 에서 빼고 배포하면 **두 스테이지에서 함께 지워진다.** 아래 7개 함수, 스테이지 합쳐 Lambda 14개다.

호출 수는 CloudWatch `Invocations` 를 2025-07-30 ~ 2026-10-26 (15개월) 동안 일 단위로 합한 값이다.

| 함수 | 경로 | dev 호출 (마지막) | prod 호출 | 삭제 근거 |
| --- | --- | --- | --- | --- |
| `authBillReceiver` | POST `/bill-receiver-auth` | 1,698 (10-26) | 0 | 호출하는 곳은 오래된 Windows 테스트 수신기뿐이다. IAM 키를 고정 문자열 인증으로 돌려주는 보안 구멍이다 |
| `testPreppersOrder` | POST `/test-order` | 5 (2025-12-17) | 0 | 테스트용 주문 생성 핸들러가 prod 에 공개 경로로 열려 있다 |
| `orderProduct` | POST `/order-product` | 0 | 0 | 이벤트를 로그에 찍고 `success` 만 돌려주는 stub 이다. gymboxx 가 `PREPPERS_ORDER_URL` 로 부르는 건 `/order`(`createOrder`)라 관계없다. 참조는 e2e 테스트·문서뿐이다 |
| `convertOrderSheetToObjectTest` | 없음 | 0 | 0 | 트리거 없는 테스트 함수 |
| `testConvert` | 없음 | 0 | 0 | 〃 |
| `testConvertFile` | 없음 | 0 | 0 | 〃 |
| `testConvertBills` | 없음 | 0 | 0 | 〃 |

같은 PR 에서 정리할 것:

- 핸들러 파일: `handler/authBillReceiver.ts`, `handler/preppersOrder/orderProduct.ts`, `test-handler.*`, `test/handler/convertOrderSheetToObject.*`. `testPreppersOrder` 의 핸들러 `handler/order/createOrder` 는 다른 곳에서 import 하는지 확인하고 지운다
- `test/slack/order/order-e2e.test.ts` 의 `/order-product` 테스트, `KDS_API.md`·`docs/architecture.md` 의 해당 항목

### 남기는 함수

| 함수 | 이유 |
| --- | --- |
| `convertOrderSheetToObject` | 운영 영수증 처리 (SQS) |
| `storeSignIn`, `getDidImages` | 운영 호출 중 |
| `createOrder` (`/order`) | gymboxx 앱 서버가 프레퍼스 주문 생성에 쓴다 |
| `openOrderProduct`, `openCardRegistration`, `interactivity`, `createBillingKey` | 슬랙 주문·카드 등록 흐름, 운영 호출 중 |
| `notifyStatus` | dev 는 파이 부팅 알림이 쓴다(당분간 유지). prod 는 0회지만 4단계에서 파이가 옮겨 올 자리다 |

dev 스테이지에서 0회인 `openCardRegistration`·`createBillingKey` 등은 함수 단위가 아니라 4단계 스테이지 삭제 때 함께 정리된다.

## 미확인

- `raspberry` 키로 IAM API 를 부른 기록이 있는지(CloudTrail 90일). 확인한 시간대에는 CloudWatch Logs 호출만 있었다.
- `PreppersRasberryPiAdmin` 정책 내용.
