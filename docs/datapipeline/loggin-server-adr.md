# ADR-001: Mobile Event Logging Pipeline 도입

- **Status**: Accepted
- **Date**: 2026-08-12
- **Decision Makers**: Data Platform Team

---

# Context

모바일 앱 이벤트를 BigQuery 기반의 Data Platform으로 구축한다.

목표는 단순 Product Analytics가 아니라 다음과 같다.

- 모바일 이벤트를 기업의 데이터 자산(Data Asset)으로 축적
- BigQuery를 Data Lake로 활용
- Data Warehouse → Data Mart 계층 구축
- BI 및 ML의 원천 데이터 제공

초기에는 Firebase Analytics + BigQuery Export를 검토하였다.

---

# Problem

Firebase Analytics는 모바일 이벤트를 수집하고 BigQuery Export를 제공한다.

처음에는 Daily Export의 **100만 이벤트 제한** 때문에 별도의 Logging Server가 필요한 것이 아닌가 검토하였다.

그러나 조사 결과 Streaming Export는 이벤트 수 제한이 없음을 확인하였다.

따라서 **100만 이벤트 제한은 Logging Server 도입의 핵심 이유가 아니다.**

---

# Decision Drivers

Data Platform 관점에서 중요한 요구사항은 다음과 같다.

- 원본 이벤트를 Canonical Raw Data로 보관
- 이벤트 수집 경로를 직접 통제
- 재처리(Reprocessing) 가능
- 이벤트 Schema 관리
- 향후 다양한 시스템으로 확장 가능
- Product Analytics와 독립적인 Data Pipeline 구축

Firebase Export는 Product Analytics를 위한 기능이며,

Streaming Export는 **best-effort** 방식으로 완전성(completeness)을 보장하지 않는다.

Data Platform의 Source of Truth로 사용하기에는 설계 목적이 다르다고 판단하였다.

---

# Decision

모바일 앱 이벤트는 자체 Logging Pipeline을 구축한다.

```
Mobile App
    │
Tracking SDK
    │
HTTPS
    ▼
Logging Server
    │
Publish
    ▼
Message Queue
    │
    ▼
BigQuery RAW
    │
Dataform
    ▼
Warehouse
    │
    ▼
Mart
```

Firebase Analytics는 필요한 경우 Product Analytics 용도로만 병행 사용한다.

BigQuery RAW를 기업의 Canonical Raw Event 저장소로 사용한다.

---

# Logging Server 검토

Logging Server의 역할은 최소한으로 유지한다.

수행 기능

- Request Validation
- Authentication
- Event ID 생성/검증
- Metadata 추가
- Timestamp 추가
- Message Queue Publish

수행하지 않는 기능

- BI 집계
- Session 계산
- Funnel 계산
- Business Logic
- Mart 생성

모든 데이터 변환은 BigQuery(Dataform)에서 수행한다.

---

# Infrastructure Options

## Option 1. GCP Cloud Run

```
App
 │
 ▼
Cloud Run
 │
 ▼
Pub/Sub
 │
 ▼
BigQuery
```

장점

- BigQuery와 동일 플랫폼
- Pub/Sub 연동이 간단
- 운영이 단순

단점

- 회사 운영 인프라가 AWS 중심
- 운영 환경이 분산됨

---

## Option 2. AWS Lambda

```
App
 │
 ▼
API Gateway
 │
 ▼
Lambda
 │
 ▼
BigQuery
```

장점

- 기존 AWS 운영 체계 활용
- 별도 서버 운영 불필요
- 이벤트 기반 구조에 적합
- 짧은 API 처리에 적합

단점

- BigQuery 인증 설정 필요
- GCP와 Cross Cloud 구성

---

## Option 3. ECS/Fargate

```
App
 │
 ▼
ALB
 │
 ▼
Fargate
 │
 ▼
BigQuery
```

장점

- 장시간 실행 서비스에 적합
- 높은 지속 트래픽에 유리

단점

- 운영 비용 증가
- 현재 Logging Server 규모에는 과도함

---

# Decision

Logging Server는 **AWS Lambda**를 사용한다.

선정 이유

- 회사의 서버 운영 표준이 AWS
- Logging API는 Stateless
- 비즈니스 로직이 거의 없음
- 이벤트 기반 처리와 적합
- 서버 운영 부담 최소화

Cloud Run은 기술적으로 적합하지만,
운영 일관성 측면에서 Lambda가 더 적합하다고 판단하였다.

---

# Cold Start 검토

Cloud Run/Lambda 모두 Cold Start가 존재한다.

그러나 Cold Start는 이벤트 유실의 원인이 아니다.

Cold Start는 첫 요청의 Latency를 증가시킬 뿐이며,

이벤트 유실 여부는 다음 요소에 의해 결정된다.

- SDK Retry
- SDK Local Queue
- Timeout 설정
- Logging Server 응답 처리

따라서 Cold Start는 현재 아키텍처의 주요 의사결정 요소에서 제외하였다.

---

# Consequences

장점

- Canonical Raw Event 확보
- Data Lake 구축 가능
- Firebase 의존성 감소
- BI/ML 확장 용이
- 이벤트 스키마 직접 관리 가능

단점

- Logging Server 운영 필요
- SDK 개발 필요
- Cross Cloud(BigQuery) 인증 관리 필요

---

# Future Considerations

향후 검토 항목

- Message Queue 선정 (Pub/Sub 또는 SQS/Kinesis)
- BigQuery 적재 방식
- Event Schema Version 관리
- Retry 및 Dead Letter Queue
- Event Batch 전송
- Monitoring 및 Alerting