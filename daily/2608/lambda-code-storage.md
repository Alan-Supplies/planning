# Lambda 코드 스토리지 한도 초과 (2026-08-28)

## 요약

`preppers-kds-serverless-dev` 배포가 실패했다. 원인은 이 프로젝트가 아니라
**AWS 계정 전체의 Lambda 코드 스토리지 한도 소진**이다.

```
UPDATE_FAILED: OpenCardRegistrationLambdaFunction (AWS::Lambda::Function)
Resource handler returned message: "Code storage limit exceeded.
(Service: Lambda, Status Code: 400, Request ID: 3dcf31e9-4cdb-46f3-b3c6-17e53dcb05b3)"
```

계정(699016088228 / ap-northeast-2) 현황:

| 항목 | 값 |
|---|---|
| 한도 (`TotalCodeSize`) | 91,268,055,040 B (85.0 GB) |
| 사용량 | 91,281,377,284 B (85.01 GB) |
| 여유 | **-13 MB (초과)** |
| 함수 수 | 318개 |
| 함수 버전 수 | 3,687개 |

한도를 13MB 초과한 상태라 **어떤 프로젝트든 신규 배포가 전부 막힌다.**
이 프로젝트만의 문제가 아니므로, 조치도 계정 단위로 해야 한다.

## 조사 방법

```sh
# 계정 한도/사용량
aws lambda get-account-settings --region ap-northeast-2

# 함수 목록
aws lambda list-functions --region ap-northeast-2 \
  --query 'Functions[].FunctionName' --output text | tr '\t' '\n' > funcs.txt

# 함수별 버전 수 / 총 코드 크기
cat > vers.sh <<'EOF'
#!/bin/bash
f="$1"
aws lambda list-versions-by-function --function-name "$f" --region ap-northeast-2 \
  --query 'Versions[].[Version,CodeSize]' --output text 2>/dev/null \
  | awk -v F="$f" '{n++; s+=$2} END {print F"\t"n"\t"s}'
EOF
chmod +x vers.sh && xargs -P 16 -n 1 ./vers.sh < funcs.txt > sizes.tsv
```

Lambda Layer는 총 3개(`slackBotLayer` 2버전, `preppersAdminLayer` 2버전, `chromium` 1버전)로
영향이 미미하다. 함수 버전이 사실상 전부다.

## 프로젝트별 현황

각 함수당 **최근 5개 버전 + alias가 참조 중인 버전**을 남긴다고 가정했을 때의 회수량이다.

| 프로젝트 | 사용량 | 버전 수 | 함수 수 | 버전당 평균 | 회수 가능 | 삭제 버전 |
|---|---:|---:|---:|---:|---:|---:|
| gymboxx-user-app-batch | 35.20 GB | 716 | 106 | 50.3 MB | 3.93 GB | 82 |
| crm-batch | 14.42 GB | 935 | 12 | 15.8 MB | **13.42 GB** | 863 |
| payment-lambda | 11.08 GB | 846 | 8 | 13.4 MB | **9.47 GB** | 798 |
| preppers-admin-serverless | 9.30 GB | 472 | 118 | 20.2 MB | 0 | 0 |
| preppers-kds-serverless | 6.04 GB | 160 | 32 | 38.7 MB | 0 | 0 |
| gymboxx-messaging-lambda | 3.02 GB | 120 | 2 | 25.8 MB | 2.73 GB | 108 |
| common-message-lambda | 2.17 GB | 255 | 6 | 8.7 MB | 1.86 GB | 219 |
| app-web-socket | 1.63 GB | 88 | 8 | 18.9 MB | 0.76 GB | 40 |
| marketing-help-lambda | 0.59 GB | 8 | 4 | 75.8 MB | 0 | 0 |
| preppers-sales-bot | 0.48 GB | 6 | 6 | 81.2 MB | 0 | 0 |
| naver-place-ranking | 0.45 GB | 5 | 1 | 92.3 MB | 0 | 0 |
| s3-handler-lambda | 0.32 GB | 39 | 6 | 8.4 MB | 0.05 GB | 8 |
| image-resize-to-save-lambda | 0.27 GB | 18 | 4 | 15.4 MB | 0.08 GB | 5 |
| common-messaging-lambda | 0.06 GB | 7 | 1 | 8.8 MB | 0.01 GB | 1 |
| spoany-bot | 0.03 GB | 9 | 1 | 3.4 MB | 0.01 GB | 3 |
| **합계** | **85.06 GB** | **3,687** | **318** | | **32.31 GB** | **2,127** |

### 버전이 가장 많이 쌓인 함수 TOP 10

| 함수 | 사용량 | 버전 수 |
|---|---:|---:|
| payment-lambda-dev-handlePayment | 3.25 GB | 288 |
| payment-lambda-dev-savePaymentHistory | 2.81 GB | 248 |
| gymboxx-messaging-lambda-dev-sendAppPush | 2.21 GB | 88 |
| crm-batch-dev-updateUser | 2.06 GB | 131 |
| crm-batch-dev-updateNotStartedMembership | 2.06 GB | 131 |
| crm-batch-dev-updateUpsellProductStatistics | 2.04 GB | 130 |
| crm-batch-dev-updateMembershipStatistics | 2.04 GB | 130 |
| crm-batch-dev-updateCurrentMembership | 2.04 GB | 130 |
| crm-batch-dev-updateInRealtime | 1.76 GB | 109 |
| payment-lambda-dev-getBillKey | 1.65 GB | 140 |

## 원인 분석

용량 문제는 두 갈래로 나뉜다.

### 1. 버전 미정리 (즉시 회수 가능)

`crm-batch`, `payment-lambda`, `gymboxx-messaging-lambda`, `common-message-lambda`는
배포할 때마다 새 버전이 쌓이는데 오래된 버전을 지우지 않는다.
`payment-lambda`는 함수당 평균 105.8개, `crm-batch`는 77.9개 버전을 들고 있다.
`payment-lambda`는 `serverless-prune-plugin`이 `serverless.yml`·`package.json`·`node_modules`
어디에도 없는 것을 확인했다. `crm-batch`는 로컬 클론이 없어 확인하지 못했지만 같은 상태로 보인다.

이 네 프로젝트가 회수 가능한 32.31 GB 중 **27.48 GB(85%)** 를 차지한다.

### 2. 패키지 크기 과다 (구조 개선 필요)

`gymboxx-user-app-batch`는 버전이 함수당 6.8개로 정상 범위인데도 35.20 GB를 쓴다.
**함수 106개 × 버전당 50.3 MB** 구조 자체가 원인이다.
버전을 5개로 줄여도 3.93 GB밖에 회수되지 않는다.
`serverless-esbuild` 도입, 공통 의존성 Layer 분리, 함수 통합 같은 별도 과제가 필요하다.

`preppers-kds-serverless`도 버전당 38.7 MB로 작지 않다.
[serverless.yml](../serverless.yml)의 prune 설정(`number: 4`) 덕에 회수 가능량은 0이지만,
계정 전체가 다시 차오르면 같은 문제를 겪는다.

### preppers-kds-serverless는 결백하다

```yaml
# serverless.yml
custom:
  prune:
    automatic: true
    number: 4
```

이 설정이 정상 동작해 함수당 평균 5.0개 버전만 유지 중이다.
같은 기준(최근 5개 보존)으로 **회수 가능량 0** — 이 레포는 이미 최소 상태다.
보존 개수를 4→3으로 낮추면 1.21 GB를 짜낼 수 있으나 임시방편에 그친다
(자세한 내용은 [조치 방안](#조치-방안) 참고).

## 조치 방안

### `sls prune`으로 해결되는가?

`serverless-prune-plugin`은 **배포 없이 정리만 실행하는 CLI 명령**을 제공한다.

```sh
npx sls prune -n 5 -s dev          # 최근 5개만 남기고 삭제
npx sls prune -n 5 -s dev --dryRun # 삭제 대상만 출력
```

단, `sls prune`은 **그 `serverless.yml`에 정의된 함수만** 건드린다.
계정 전체를 훑지 않으므로 레포마다 따로 실행해야 한다.

**이 레포에서 그냥 `sls prune`을 때리면 0바이트가 나온다.** 이미 `number: 4`로
함수당 4~5개만 유지 중이기 때문이다. 보존 개수를 낮춰야 회수가 생긴다.

| `-n` 값 | 회수량 | 삭제 버전 | 비고 |
|---:|---:|---:|---|
| 4 (현재 설정) | 0 GB | 0 | 이미 정리 완료 |
| 3 | 1.21 GB | 32 | **13MB만 초과한 상태라 이것으로 배포가 뚫린다** |
| 2 | 2.42 GB | 64 | |
| 1 | 3.63 GB | 96 | 롤백 여유 없음 |

즉 **급하게 배포를 뚫는 최단 경로**는 이 레포에서 다음을 실행하는 것이다.

```sh
npx sls prune -n 3 -s dev --dryRun   # 먼저 대상 확인
npx sls prune -n 3 -s dev
```

다만 이건 **임시방편이다.** 1.21 GB는 dev 배포 30여 회 분량이라 곧 다시 찬다.
근본 원인은 다른 레포에 있다.

### 근본 조치: 버전이 쌓인 레포에서 prune 실행

문제는 정작 용량을 먹는 레포에 **플러그인이 설치조차 되어 있지 않다**는 점이다.
`payment-lambda`(로컬 `~/workspace/supplies/payment-lambda`)를 확인한 결과:

```yaml
# payment-lambda/serverless.yml
plugins:
  - serverless-plugin-typescript
  - serverless-offline
  - serverless-plugin-lambda-insights
  # serverless-prune-plugin 없음
```

`package.json`에도 `node_modules`에도 없다. 함수당 105.8개 버전이 쌓인 이유다.
`crm-batch`는 로컬에 없어 확인하지 못했지만 함수당 77.9버전이면 같은 상태로 보인다.

해결은 간단하다. **플러그인만 추가하면 배포 없이 정리할 수 있다.**

```sh
cd ~/workspace/supplies/payment-lambda
npm i -D serverless-prune-plugin
# serverless.yml plugins 에 - serverless-prune-plugin 추가

npx sls prune -n 5 -s dev --dryRun
npx sls prune -n 5 -s dev     # 9.47 GB 회수
```

`crm-batch`도 같은 방식으로 13.42 GB를 회수할 수 있다.
이 둘만으로 **22.89 GB**가 확보된다.

### 플러그인 없이 정리하려면

레포에 손대지 않고 AWS CLI로 직접 정리할 수도 있다.
각 함수에서 최근 5개 버전과 alias 참조 버전을 보존하고 나머지를 삭제한다.

```sh
#!/bin/bash
# prune-lambda-versions.sh <함수이름-패턴>
# 예: ./prune-lambda-versions.sh 'payment-lambda-dev-'
REGION=ap-northeast-2
KEEP=5
PATTERN="$1"

aws lambda list-functions --region $REGION \
  --query 'Functions[].FunctionName' --output text | tr '\t' '\n' \
| grep -E "$PATTERN" | while read -r f; do
  aliases=$(aws lambda list-aliases --function-name "$f" --region $REGION \
    --query 'Aliases[].FunctionVersion' --output text 2>/dev/null | tr '\t' '\n')

  aws lambda list-versions-by-function --function-name "$f" --region $REGION \
    --query 'Versions[].Version' --output text 2>/dev/null | tr '\t' '\n' \
  | grep -v '^\$LATEST' | sort -n | head -n -$KEEP \
  | while read -r v; do
      if echo "$aliases" | grep -qx "$v"; then
        echo "SKIP (alias) $f:$v"; continue
      fi
      echo "DELETE $f:$v"
      # 실제 삭제는 아래 주석을 해제한다
      # aws lambda delete-function --function-name "$f" --qualifier "$v" --region $REGION
    done
done
```

**먼저 주석 상태로 실행해 삭제 대상을 확인한 뒤** 주석을 해제한다.

### 범위별 회수량 (최근 5개 보존 기준)

| 범위 | 회수량 | 삭제 버전 |
|---|---:|---:|
| crm-batch + payment-lambda의 dev만 | 19.12 GB | 1,386 |
| 모든 프로젝트의 dev 스테이지 | 25.14 GB | 1,728 |
| 전체 (prod 포함) | 32.31 GB | 2,127 |

### 안전성

- alias, provisioned concurrency, 이벤트 소스 매핑이 참조 중인 버전은
  AWS가 `ResourceConflictException`으로 삭제를 거부하므로 운영 중단 위험은 낮다.
- 다만 **삭제한 버전으로는 롤백할 수 없다.** 그보다 오래된 배포로 되돌리려면 재배포해야 한다.
- 대상이 타 팀 소유 리소스(`crm-batch`, `payment-lambda`, `gymboxx-*`)이므로
  **실행 전 각 담당자 합의가 필요하다.**

### 대안: 한도 증량

삭제 없이 Service Quotas에서 `Function and layer storage` 한도 상향을 신청할 수 있다.
AWS 승인까지 시간이 걸려 당장의 배포는 뚫지 못하며, 근본 원인(버전 미정리)은 그대로 남는다.
정리와 병행하는 편이 좋다.

## 재발 방지

버전이 쌓이는 프로젝트에 `serverless-prune-plugin`을 도입한다.
`preppers-kds-serverless`가 쓰는 설정을 그대로 옮기면 된다.

```yaml
plugins:
  - serverless-prune-plugin

custom:
  prune:
    automatic: true
    number: 4   # 배포 후 최근 4개 버전만 유지
```

적용 대상 (버전 수 기준 우선순위):

1. `payment-lambda` — 함수당 평균 105.8버전
2. `crm-batch` — 함수당 평균 77.9버전
3. `gymboxx-messaging-lambda` — 함수당 평균 60.0버전
4. `common-message-lambda` — 함수당 평균 42.5버전

`gymboxx-user-app-batch`는 prune만으로 해결되지 않는다.
버전당 50.3 MB × 함수 106개라는 패키지 크기 자체를 줄여야 한다 (별도 과제).

## 모니터링

한도의 80%를 넘으면 알림이 오도록 정기 점검을 걸어둔다.

```sh
aws lambda get-account-settings --region ap-northeast-2 \
  --query '{한도:AccountLimit.TotalCodeSize, 사용량:AccountUsage.TotalCodeSize, 함수수:AccountUsage.FunctionCount}'
```

---

조사일: 2026-08-28 / 리전: ap-northeast-2 / 계정: 699016088228
