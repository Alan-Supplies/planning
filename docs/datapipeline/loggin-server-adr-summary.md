# ADR-001: Mobile Event Logging Pipeline 도입

- **Status**: Accepted
- **Date**: 2026-08-12
- **Decision Makers**: Data Platform Team

# 배경

모바일 앱 이벤트를 BigQuery 기반 Data Platform(Data Lake → Warehouse → Mart)으로 축적해 BI/ML의 원천 데이터로 쓰는 것이 목표였고, 초기에는 Firebase Analytics + BigQuery Export로 해결할 수 있는지 검토했다. 처음 문제로 본 Daily Export의 100만 이벤트 제한은 Streaming Export에 적용되지 않는 것으로 확인되어, 수집량 자체는 제약 조건이 아니었다. 대신 Firebase Export가 Product Analytics 목적의 기능이고 Streaming Export가 best-effort라 완전성(completeness)을 보장하지 않는다는 점이, 회사의 Canonical Raw Data를 어디에 둘 것인가라는 결정으로 이어졌다.

# 검토한 선택지

## 이벤트 수집 경로

- **A안: Firebase Analytics + BigQuery Export** — 별도 서버·SDK 개발 없이 즉시 수집 시작, 운영 부담 없음 / Streaming Export가 best-effort라 유실 가능성을 배제할 수 없고, 수집 경로·스키마를 직접 통제할 수 없어 재처리(Reprocessing)와 스키마 버전 관리가 어려움
- **B안: 자체 Logging Pipeline** — 원본 이벤트를 Canonical Raw Data로 직접 보관, 수집 경로 통제·재처리·스키마 관리 가능, Product Analytics와 독립적으로 확장 가능 / Logging Server 운영과 Tracking SDK 개발이 필요하고 Cross Cloud 인증 관리 부담이 생김

## Logging Server 인프라

**공통 특성 (별도 Logging Server 구축)**
- Request Validation, Authentication, Event ID 생성/검증, Metadata·Timestamp 추가는 동일
- Message Queue를 통한 비동기 처리
- BigQuery와의 연동 구현 방식에만 차이

**구현 방식 선택**

- **A안: ECS/Fargate** — 장시간 실행·높은 지속 트래픽에 유리 / 운영 비용이 증가하고 현재 Logging Server 규모에는 과도함
- **B-1안: GCP Cloud Run** — BigQuery와 동일 플랫폼이라 Pub/Sub 연동이 간단하고 운영이 단순 / 회사 운영 인프라가 AWS 중심이라 운영 환경이 분산됨
- **B-2안: AWS Lambda** — 기존 AWS 운영 체계를 그대로 활용, 서버 운영 불필요, 짧고 Stateless한 이벤트 기반 API에 적합 / BigQuery 인증 설정이 필요하고 GCP와 Cross Cloud 구성이 됨

# 결정

**자체 Logging Pipeline을 구축하고, Logging Server는 AWS Lambda로 운영한다.** BigQuery RAW를 기업의 Canonical Raw Event 저장소로 삼고, Firebase Analytics는 필요한 경우 Product Analytics 용도로만 병행한다.

```text
Mobile App → Tracking SDK → HTTPS → Logging Server → Message Queue
  → BigQuery RAW → Dataform → Warehouse → Mart
```

결정적 이유는 두 가지다. 첫째, Firebase Export는 완전성을 보장하지 않아 데이터 자산의 원본으로 삼을 수 없다. 둘째, 인프라는 Cloud Run이 기술적으로 더 적합하지만 회사의 서버 운영 표준이 AWS이므로 **운영 일관성**을 우선했다.

Logging Server의 역할은 최소로 고정한다.

- **수행**: Request Validation, Authentication, Event ID 생성/검증, Metadata·Timestamp 추가, Message Queue Publish
- **미수행**: BI 집계, Session/Funnel 계산, Business Logic, Mart 생성 — 모든 변환은 BigQuery(Dataform)에서 수행

Cold Start는 Cloud Run/Lambda 모두 존재하지만 첫 요청의 Latency만 늘릴 뿐 이벤트 유실의 원인이 아니며(유실은 SDK Retry·Local Queue·Timeout·서버 응답 처리로 결정), 의사결정 요소에서 제외했다.

# 영향

**얻는 것**

- Canonical Raw Event 확보 및 Data Lake 구축
- 이벤트 스키마 직접 관리, 재처리 가능
- Firebase 의존성 감소, BI/ML 확장 용이

**감수하는 것**

- Logging Server 운영 부담 (Lambda 선택으로 최소화)
- Tracking SDK 자체 개발 필요
- AWS ↔ BigQuery Cross Cloud 인증 관리

**후속 결정 필요**

- Message Queue 선정 (Pub/Sub vs SQS/Kinesis)
- BigQuery 적재 방식, Event Schema Version 관리
- Retry / Dead Letter Queue, Event Batch 전송
- Monitoring 및 Alerting

# 관련 문서

- [BigQuery Export - Analytics Help](https://support.google.com/analytics/answer/9358801) — Daily Export 100만 이벤트 제한, Streaming Export의 best-effort 특성(완전성 미보장) 설명
- (TBD) Message Queue 선정 ADR
- (TBD) Event Schema 정의 문서
