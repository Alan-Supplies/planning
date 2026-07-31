# 2026-07-27 운영 RDS 부하 및 CRM 큐 적체 조사

## 개요

- 조사 일시: 2026-07-27 20:07~20:15 KST
- 제보 시각: 2026-07-27 19:42 KST
- 관련 Slack: https://w1622455415-twy380170.slack.com/archives/C094ZAFAHMX/p1785148963242739
- EKS 클러스터: `eks_prod`
- 애플리케이션: `app-server-prod`
- RDS: `gymboxx-prod` (MySQL 8.0.40, `db.m6i.2xlarge`)
- 조사 중 운영 환경 변경: 없음

## 결론

관찰된 다수의 idle 세션은 이번 문제의 직접 원인이 아니다.

`app-server-prod`의 DB 계정인 `userapp`은 4개 파드에서 각각 mysql2 기본
connection pool 10개를 사용해 정확히 40개의 `Sleep` 세션을 유지하고 있었다.
세션 수는 재확인 시에도 40개로 일정했고, 연결 누수나 `Too many connections`
오류는 확인되지 않았다.

실제 병목은 `crm-batch-prod-updateInRealtime` Lambda가 실행하는 다음 UPDATE다.

```sql
UPDATE app_instance
SET last_used_at = ?
WHERE user_id = ?
  AND app_instance_id = ?;
```

`gymboxx_crm.app_instance`는 약 30만 행이지만 기본키 외 인덱스가 없다. 따라서
위 쿼리는 실행할 때마다 테이블 전체를 스캔한다. Lambda 처리 시간이 평균 약
19초까지 증가하면서 최대 동시성 10을 계속 사용했고, 유입량보다 처리량이
낮아져 SQS 메시지가 누적됐다.

## 장애 흐름

```text
app-server 등 이벤트 생산자
  → prodCrmRealtimeUpdateQueue
  → crm-batch-prod-updateInRealtime Lambda
  → 인덱스 없는 app_instance UPDATE 전체 스캔
  → Lambda 처리 지연 및 동시성 포화
  → SQS backlog 증가
```

## 주요 관측 결과

### RDS 연결

- 조사 구간 DatabaseConnections: 165~178
- 최근 7일 평균: 약 164
- 최근 7일 최대: 약 192
- MySQL `max_connections`: 2,614
- CPU: 평균 약 37%, 최대 약 51%
- FreeableMemory: 약 4.77~4.80 GB
- 애플리케이션 로그에서 연결 초과, 연결 거부, DB timeout 오류 없음

제보 시점 연결 수는 최근 기준선에서 크게 벗어나지 않았으며, 최대 연결 수의
약 6~7% 수준이었다.

### 계정별 MySQL 세션

대표 집계 결과:

- `userapp`: `Sleep` 40개
  - `app-server-prod` 4개 파드 × 기본 pool 10개
- `adminapp`: `Sleep` 20개
- `trainer`: `Sleep` 20개
- `gymboxx`: `Sleep` 약 70~80개
  - 여러 운영 서비스의 connection pool이 공용 계정을 사용
- `gymboxx`: 실행 중인 `Query` 10개
  - CRM Lambda 최대 동시성 10과 일치

MySQL `wait_timeout`과 `interactive_timeout`은 모두 28,800초(8시간)다. 풀에
반환된 연결은 애플리케이션이 종료하거나 서버 timeout에 도달할 때까지
`Sleep`으로 표시될 수 있다.

### Performance Insights

조사 구간 평균 DB Load는 약 10.46 AAS였다.

계정별 평균 부하:

- `gymboxx`: 약 8.79 AAS
- `userapp`: 약 0.84 AAS
- `appwebsocket`: 약 0.75 AAS
- 기타 계정: 각각 0.05 AAS 미만

가장 큰 부하를 발생시킨 SQL은 `app_instance.last_used_at` UPDATE로 약
7.84 AAS를 차지했다. 주요 대기 이벤트는
`wait/io/table/sql/handler`였다.

### 문제 테이블과 실행 계획

`gymboxx_crm.app_instance` 상태:

- 추정 행 수: 약 302,000
- 기본키: `id`
- 보조 인덱스: 없음

문제 UPDATE의 `EXPLAIN` 결과:

- access type: `index`
- 사용 인덱스: `PRIMARY`
- 예상 탐색 행: 약 302,825
- Extra: `Using where`

즉, `(user_id, app_instance_id)`를 찾기 위해 기본키 전체를 순회한다.

### CRM Lambda

`crm-batch-prod-updateInRealtime` 설정:

- Runtime: Node.js 22
- Memory: 1,024 MB
- Timeout: 60초
- Reserved concurrency: 10
- SQS event source maximum concurrency: 10
- Batch size: 10
- Partial batch response: 비활성화

약 103분 동안 관측한 지표:

- 호출: 2,894회
- 오류: 99회
- 평균 duration: 약 18.9초
- 최대 동시 실행: 매분 10으로 포화

제보 전후 15분 동안에도 duration은 평균 약 19초였고 동시성은 계속
포화 상태였다.

### SQS 적체

`prodCrmRealtimeUpdateQueue` 상태:

- 조사 당시 visible messages: 약 25,800건
- in-flight messages: 약 90~100건
- 가장 오래된 메시지: 약 67분
- 103분간 전송: 44,501건
- 103분간 삭제: 28,160건
- Visibility timeout: 60초
- Message retention: 1일
- DLQ/Redrive policy: 없음

유입은 분당 약 432건, 삭제는 분당 약 273건으로 처리량이 부족했다.
적체는 이번 앱 배포 이전인 2026-07-26 19:05 KST에도 1,000건을 넘었으므로,
2026-07-27 13:30 KST 앱 배포가 최초 원인은 아니다.

### Lambda 오류

Slack 제보 시각 전후 30분의 오류 로그에서 다음 패턴을 확인했다.

- Validation 오류: 147건
- Invalid message 로그: 147건
- Braze API 400 관련 로그: 27건
- Lambda Invoke Error: 27건
- Lambda timeout: 0건
- DB connection/lock/deadlock 오류: 0건

대표적인 잘못된 메시지는 `appInstanceId`, `deviceOS`, `accessCount` 등이
누락된 payload다. Braze에 빈 events 배열을 보내 `No data parsed` 400 응답이
발생하는 경우도 있었다.

현재 event source는 partial batch response가 꺼져 있어 한 레코드의 실패로
같은 batch가 다시 처리될 수 있다. DLQ도 없어 반복 실패 메시지를 격리할 수
없다.

## 권장 조치

### 1. app_instance 인덱스 추가

가장 먼저 다음 인덱스를 추가한다.

```sql
ALTER TABLE gymboxx_crm.app_instance
  ADD INDEX idx_app_instance_user_app (user_id, app_instance_id),
  ALGORITHM=INPLACE,
  LOCK=NONE;
```

주의 사항:

- 운영 DDL 전 실행 시간과 I/O 영향을 확인한다.
- 인덱스 생성 중 RDS CPU, DiskQueueDepth, WriteLatency, DB Load를 관찰한다.
- 현재 데이터의 중복 여부를 검증하기 전에는 `UNIQUE`를 사용하지 않는다.
- 인덱스 적용 전 Lambda 동시성을 높이지 않는다. 동시성을 먼저 높이면
  전체 스캔 수와 DB 부하만 증가할 수 있다.

### 2. 적용 후 검증

다음을 확인한다.

- 문제 UPDATE의 `EXPLAIN`이 신규 인덱스를 사용하는지
- UPDATE의 AAS와 `wait/io/table/sql/handler` 감소 여부
- Lambda duration 감소 여부
- Lambda concurrency가 10 아래로 내려가는지
- SQS visible messages와 oldest message age가 지속적으로 감소하는지

### 3. SQS/Lambda 실패 격리

- SQS DLQ와 적절한 `maxReceiveCount`를 설정한다.
- Lambda에서 `ReportBatchItemFailures`를 활성화한다.
- 개별 실패 레코드만 반환하도록 handler를 수정한다.
- Lambda timeout 60초에 비해 visibility timeout 60초는 여유가 없다.
  AWS 권장 기준과 실제 처리 시간을 고려해 visibility timeout을 늘린다.
- 메시지 보존 기간 1일이 충분한지 재검토한다.

### 4. 잘못된 이벤트 수정

- producer에서 필수 필드가 없는 이벤트를 발행하지 않도록 검증한다.
- consumer에서 잘못된 이벤트를 명시적으로 폐기하거나 DLQ로 보낸다.
- Braze events 배열이 비어 있으면 API를 호출하지 않는다.

### 5. 애플리케이션 DB pool 설정 정리

현재 설정:

```ts
extra: {
  decimalNumbers: true,
  max: 200,
  connectionTimeoutMillis: 5000,
}
```

`max`와 `connectionTimeoutMillis`는 mysql2 pool 옵션이 아니므로 의도대로
적용되지 않는다. mysql2에 맞게 `connectionLimit`, `connectTimeout` 등을
명시하고 서비스별 예상 동시성에 따라 pool 크기를 결정한다.

이 설정 문제는 이번 CRM 병목의 직접 원인은 아니지만, 운영 연결 수를
예측하고 관리하기 위해 수정할 필요가 있다.

### 6. 트랜잭션 코드 개선

별도 코드 조사에서 다음 개선 대상도 확인했다.

- 트랜잭션 내부의 외부 HTTP/SQS 호출
- QueryRunner를 전달하지 않는 중첩 repository 조회
- validation 예외 경로에서 QueryRunner가 해제되지 않을 수 있는 코드
- rollback 함수 호출 괄호 누락 가능성
- graceful shutdown hook 미설정

이 항목들은 현재 확인된 CRM 쿼리 병목과 별개의 잠재 위험이다. 인덱스 및
큐 적체를 먼저 해소한 후 별도 작업으로 수정한다.

## 데이터 수집 및 재현 방법

아래 명령은 모두 조회용이다. 운영 리소스를 변경하지 않도록 EKS context와
AWS region을 명령마다 명시한다. 로그와 쿼리 결과를 공유할 때는 사용자 정보,
토큰, DB 비밀번호, 메시지 본문을 제거한다.

### 사전 준비

```bash
export REGION=ap-northeast-2
export DB_INSTANCE=gymboxx-prod
export EKS_CONTEXT=arn:aws:eks:ap-northeast-2:699016088228:cluster/eks_prod
export APP_NAMESPACE=default
export APP_LABEL=app-server-prod
export CRM_FUNCTION=crm-batch-prod-updateInRealtime
export CRM_QUEUE=prodCrmRealtimeUpdateQueue
```

현재 AWS 계정과 Kubernetes 접근 대상을 먼저 확인한다.

```bash
aws sts get-caller-identity
kubectl config get-contexts
kubectl --context "$EKS_CONTEXT" cluster-info
```

조사 시간은 KST와 UTC를 함께 기록한다. AWS CLI의 `start-time`과 `end-time`은
UTC ISO 8601 형식으로 전달하는 것이 안전하다.

```text
2026-07-27 19:42:43 KST
= 2026-07-27 10:42:43 UTC
```

### 1. 운영 파드와 배포 상태

파드 수, 재시작, 생성 시각, 노드를 확인한다.

```bash
kubectl --context "$EKS_CONTEXT" \
  -n "$APP_NAMESPACE" \
  get pods -l app="$APP_LABEL" -o wide
```

배포 이미지, replica 수, rollout revision을 확인한다.

```bash
kubectl --context "$EKS_CONTEXT" \
  -n "$APP_NAMESPACE" \
  get deployment "$APP_LABEL" -o wide

kubectl --context "$EKS_CONTEXT" \
  -n "$APP_NAMESPACE" \
  rollout history deployment/"$APP_LABEL"
```

최근 파드 이벤트를 확인한다.

```bash
kubectl --context "$EKS_CONTEXT" \
  -n "$APP_NAMESPACE" \
  get events --sort-by=.lastTimestamp
```

### 2. 앱 서버 DB 오류 로그

최근 3시간 로그에서 연결 오류와 TypeORM/MySQL 오류를 검색한다.

```bash
kubectl --context "$EKS_CONTEXT" \
  -n "$APP_NAMESPACE" \
  logs -l app="$APP_LABEL" \
  --all-containers=true \
  --prefix \
  --since=3h \
  --timestamps |
rg -i \
  'too many connections|ER_CON_COUNT_ERROR|PROTOCOL_CONNECTION_LOST|ECONN|QueryFailedError|connection.*(timeout|closed|lost|refused)'
```

결과가 없으면 적어도 해당 시간 범위에 애플리케이션이 기록한 DB 연결 오류는
없었다는 의미다. 로그 레벨이나 예외 처리 방식에 따라 누락될 수 있으므로 RDS
지표와 함께 판단한다.

### 3. RDS 구성 확인

DB class, 엔진 버전, Performance Insights 활성화 여부와 리소스 ID를 가져온다.

```bash
aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_INSTANCE" \
  --query 'DBInstances[0].{
    Class:DBInstanceClass,
    Engine:Engine,
    Version:EngineVersion,
    Status:DBInstanceStatus,
    PerformanceInsights:PerformanceInsightsEnabled,
    ResourceId:DbiResourceId
  }'
```

Performance Insights API에는 DB identifier가 아니라 `DbiResourceId`가 필요하다.

```bash
export DB_RESOURCE_ID=$(
  aws rds describe-db-instances \
    --region "$REGION" \
    --db-instance-identifier "$DB_INSTANCE" \
    --query 'DBInstances[0].DbiResourceId' \
    --output text
)
```

### 4. RDS 연결 수와 자원 지표

다음 예시는 제보 전후 연결 수를 1분 단위로 조회한다.

```bash
aws cloudwatch get-metric-statistics \
  --region "$REGION" \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE" \
  --start-time 2026-07-27T09:30:00Z \
  --end-time 2026-07-27T11:15:00Z \
  --period 60 \
  --statistics Average Maximum \
  --output json
```

같은 방식으로 `CPUUtilization`, `FreeableMemory`, `DiskQueueDepth`,
`ReadLatency`, `WriteLatency`를 조회한다. 단위가 서로 다르므로 지표별로
조회하거나 별도의 MetricData query를 사용한다.

장애 순간의 값만 보지 말고 최소 7일 기준선도 비교한다.

```bash
aws cloudwatch get-metric-statistics \
  --region "$REGION" \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE" \
  --start-time 2026-07-20T00:00:00Z \
  --end-time 2026-07-27T11:15:00Z \
  --period 3600 \
  --statistics Average Maximum
```

### 5. Performance Insights 상위 SQL

상위 SQL을 DB Load 기여도 순으로 조회한다.

```bash
aws pi describe-dimension-keys \
  --region "$REGION" \
  --service-type RDS \
  --identifier "$DB_RESOURCE_ID" \
  --start-time 2026-07-27T09:30:00Z \
  --end-time 2026-07-27T11:15:00Z \
  --period-in-seconds 60 \
  --metric db.load.avg \
  --group-by '{"Group":"db.sql_tokenized","Limit":20}'
```

대기 이벤트별 부하:

```bash
aws pi describe-dimension-keys \
  --region "$REGION" \
  --service-type RDS \
  --identifier "$DB_RESOURCE_ID" \
  --start-time 2026-07-27T09:30:00Z \
  --end-time 2026-07-27T11:15:00Z \
  --period-in-seconds 60 \
  --metric db.load.avg \
  --group-by '{"Group":"db.wait_event","Limit":20}'
```

DB 사용자별 부하:

```bash
aws pi describe-dimension-keys \
  --region "$REGION" \
  --service-type RDS \
  --identifier "$DB_RESOURCE_ID" \
  --start-time 2026-07-27T09:30:00Z \
  --end-time 2026-07-27T11:15:00Z \
  --period-in-seconds 60 \
  --metric db.load.avg \
  --group-by '{"Group":"db.user","Limit":20}'
```

판단할 때 SQL의 총 실행 횟수만 보지 말고 `Total` DB Load, 대기 이벤트,
사용자 계정을 함께 본다. 이번 조사에서는 `gymboxx` 계정의
`wait/io/table/sql/handler`가 대부분을 차지했다.

### 6. 현재 MySQL 세션 분포

DB client 접근 권한이 있다면 다음 읽기 전용 쿼리로 사용자, 원본 호스트,
상태별 세션을 집계한다.

```sql
SELECT
  USER,
  SUBSTRING_INDEX(HOST, ':', 1) AS host,
  COMMAND,
  COUNT(*) AS sessions,
  MIN(TIME) AS min_seconds,
  MAX(TIME) AS max_seconds,
  ROUND(AVG(TIME), 1) AS avg_seconds
FROM information_schema.PROCESSLIST
GROUP BY USER, SUBSTRING_INDEX(HOST, ':', 1), COMMAND
ORDER BY sessions DESC;
```

connection 한도와 idle timeout도 함께 확인한다.

```sql
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_variables
WHERE VARIABLE_NAME IN (
  'max_connections',
  'wait_timeout',
  'interactive_timeout'
);
```

MySQL client가 로컬에 없으면 실행 중인 앱 파드의 `mysql2`와 파드 환경 변수를
사용해 조회할 수 있다. 다음 명령은 비밀번호를 출력하지 않는다.

```bash
POD=$(
  kubectl --context "$EKS_CONTEXT" \
    -n "$APP_NAMESPACE" \
    get pods -l app="$APP_LABEL" \
    -o jsonpath='{.items[0].metadata.name}'
)

kubectl --context "$EKS_CONTEXT" \
  -n "$APP_NAMESPACE" \
  exec "$POD" -- node -e '
const mysql = require("mysql2/promise")

async function main() {
  const connection = await mysql.createConnection({
    host: process.env.DB_ENDPOINT,
    user: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  })

  const [rows] = await connection.query(`
    SELECT USER, COMMAND, COUNT(*) sessions, MAX(TIME) max_seconds
    FROM information_schema.PROCESSLIST
    GROUP BY USER, COMMAND
    ORDER BY sessions DESC
  `)

  console.log(JSON.stringify(rows, null, 2))
  await connection.end()
}

main().catch((error) => {
  console.error(error.message)
  process.exit(1)
})
'
```

`Sleep` 세션은 그 자체로 누수가 아니다. 서비스 replica 수 × pool 크기와
일치하는지, 시간이 지나면서 제한 없이 증가하는지, open transaction이
있는지를 구분한다.

### 7. 테이블 인덱스와 실행 계획

문제 테이블 크기와 인덱스를 확인한다.

```sql
SELECT
  TABLE_SCHEMA,
  TABLE_NAME,
  TABLE_ROWS,
  DATA_LENGTH,
  INDEX_LENGTH
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'gymboxx_crm'
  AND TABLE_NAME = 'app_instance';

SHOW INDEX FROM gymboxx_crm.app_instance;
SHOW CREATE TABLE gymboxx_crm.app_instance;
```

실제 데이터를 변경하지 않고 UPDATE 실행 계획을 확인한다.

```sql
EXPLAIN
UPDATE gymboxx_crm.app_instance
SET last_used_at = NOW()
WHERE user_id = 0
  AND app_instance_id = 'diagnostic-nonexistent';
```

`possible_keys`가 없고 `rows`가 테이블 전체 행 수에 가까우면 조건 컬럼에
적절한 인덱스가 없는 상태다.

### 8. Lambda 설정과 처리량

환경 변수의 값은 출력하지 않고 함수 실행 설정만 조회한다.

```bash
aws lambda get-function-configuration \
  --region "$REGION" \
  --function-name "$CRM_FUNCTION" \
  --query '{
    FunctionName:FunctionName,
    Runtime:Runtime,
    MemorySize:MemorySize,
    Timeout:Timeout,
    LastModified:LastModified
  }'

aws lambda get-function-concurrency \
  --region "$REGION" \
  --function-name "$CRM_FUNCTION"

aws lambda list-event-source-mappings \
  --region "$REGION" \
  --function-name "$CRM_FUNCTION"
```

Lambda 지표는 CloudWatch의 `AWS/Lambda` namespace에서 확인한다.

```bash
aws cloudwatch get-metric-statistics \
  --region "$REGION" \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value="$CRM_FUNCTION" \
  --start-time 2026-07-27T09:30:00Z \
  --end-time 2026-07-27T11:15:00Z \
  --period 60 \
  --statistics Average Maximum
```

같은 방식으로 `Invocations`, `Errors`, `ConcurrentExecutions`, `Throttles`를
조회한다. `Invocations`와 `Errors`는 `Sum`, 동시성은 `Maximum`을 사용하는
것이 적절하다.

### 9. Lambda 오류 로그

`filter-log-events`의 시간은 Unix epoch millisecond다. KST 시각을 다음처럼
변환할 수 있다.

```bash
export LOG_START_MS=$(
  python3 -c \
    'from datetime import datetime; print(int(datetime.fromisoformat("2026-07-27T19:30:00+09:00").timestamp() * 1000))'
)
export LOG_END_MS=$(
  python3 -c \
    'from datetime import datetime; print(int(datetime.fromisoformat("2026-07-27T20:10:00+09:00").timestamp() * 1000))'
)
```

오류 로그 조회:

```bash
aws logs filter-log-events \
  --region "$REGION" \
  --log-group-name "/aws/lambda/$CRM_FUNCTION" \
  --start-time "$LOG_START_MS" \
  --end-time "$LOG_END_MS" \
  --filter-pattern 'ERROR' \
  --limit 1000
```

오류를 validation, 외부 API, DB, timeout으로 분류한다. 메시지 payload에는
개인정보가 포함될 수 있으므로 원문을 문서나 채팅에 그대로 붙이지 않는다.

### 10. SQS 현재 적체와 설정

Queue URL을 가져온다.

```bash
export CRM_QUEUE_URL=$(
  aws sqs get-queue-url \
    --region "$REGION" \
    --queue-name "$CRM_QUEUE" \
    --query QueueUrl \
    --output text
)
```

현재 backlog, visibility timeout, retention, DLQ 설정을 확인한다.

```bash
aws sqs get-queue-attributes \
  --region "$REGION" \
  --queue-url "$CRM_QUEUE_URL" \
  --attribute-names \
    ApproximateNumberOfMessages \
    ApproximateNumberOfMessagesNotVisible \
    ApproximateNumberOfMessagesDelayed \
    VisibilityTimeout \
    MessageRetentionPeriod \
    RedrivePolicy
```

메시지를 직접 `receive-message`로 읽으면 visibility 상태를 바꿀 수 있으므로
단순 조사에서는 사용하지 않는다.

### 11. SQS 유입량과 처리량

현재 수치만으로는 backlog 증가 속도를 알 수 없다. CloudWatch에서 다음
지표를 같은 시간 범위로 조회한다.

- `ApproximateNumberOfMessagesVisible`: backlog
- `ApproximateNumberOfMessagesNotVisible`: 처리 중 메시지
- `ApproximateAgeOfOldestMessage`: 지연 시간
- `NumberOfMessagesSent`: 유입량
- `NumberOfMessagesDeleted`: 처리 완료량

예시:

```bash
aws cloudwatch get-metric-statistics \
  --region "$REGION" \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value="$CRM_QUEUE" \
  --start-time 2026-07-27T09:30:00Z \
  --end-time 2026-07-27T11:15:00Z \
  --period 60 \
  --statistics Maximum
```

`NumberOfMessagesSent`와 `NumberOfMessagesDeleted`는 `Sum`으로 조회한다.
일정 구간에서 Sent가 Deleted보다 계속 크고 visible/oldest가 함께 증가하면
consumer 처리량이 유입량보다 낮다는 의미다.

### 12. 인덱스 적용 전후 비교

변경 전 다음 값을 기록한다.

- 문제 SQL의 실행 계획과 예상 탐색 행 수
- 문제 SQL의 DB Load
- RDS CPU와 주요 wait event
- Lambda 평균/p95에 가까운 duration과 concurrency
- SQS visible messages와 oldest message age

인덱스 적용 후 동일한 명령과 동일한 집계 주기로 다시 수집한다. 트래픽이
비슷한 시간대를 비교해야 하며, 단일 순간 값이 아니라 최소 10~30분 추세로
판단한다.

## AWS 콘솔에서 상위 SQL 확인

현재 권장 경로:

1. AWS Console에서 CloudWatch로 이동
2. `Insights` → `Database Insights`
3. `Database Instance` 선택
4. 리전을 `ap-northeast-2`로 설정
5. `gymboxx-prod` 선택
6. `Top SQL` 탭 선택

기존 Performance Insights 경로:

1. RDS → Databases
2. `gymboxx-prod`
3. Monitoring
4. Performance Insights

2026-07-27 19:30~20:10 KST 구간을 선택하면
`app_instance.last_used_at` UPDATE가 상위에 표시된다.

## 후속 확인 체크리스트

- [ ] 운영 DDL 적용 일정 결정
- [ ] 인덱스 추가 전후 실행 계획 저장
- [ ] 인덱스 추가 후 RDS AAS 감소 확인
- [ ] Lambda duration 및 concurrency 정상화 확인
- [ ] SQS backlog가 0으로 감소하는지 확인
- [ ] DLQ 및 partial batch response 적용
- [ ] malformed message producer 식별 및 수정
- [ ] Braze 빈 events 호출 방지
- [ ] mysql2 pool 옵션 수정
- [ ] QueryRunner 및 트랜잭션 외부 I/O 개선
