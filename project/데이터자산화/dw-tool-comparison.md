# DW 후보 비교 — BigQuery vs 대안 (배치 파이프라인 전제)

> DA-P2-01(DW·제품분석·CDP 도구 선정)의 선행 검토 자료. L1/L2 정비(P0)와 병행 진행.
> 작성일 2026-08-05. **정성적 비교이며, 실제 볼륨/예산 기준 정량 견적은 후속 작업 필요.**

## 전제 조건

- **적재 방식은 배치(Batch)로 확정.** 실시간/스트리밍 요구 없음 → 서버리스 웨어하우스의 "쿼리당 과금" 구조가 유리해지는 방향.
- **기존 인프라**: L1 정본 DB는 AWS RDS MySQL(`ap-northeast-2`, `kds-dev`/`kds-prod`). 이벤트 파이프라인은 P0-12에서 **BigQuery Export를 이미 전제**로 잡아둔 상태 — 즉 이벤트 쪽은 GCP/BigQuery로 이미 절반쯀 정해져 있음.
- **리전**: 서비스가 한국 기준(ap-northeast-2)이라 데이터 국외이전 이슈(DA-P0-16, PII 법무 의뢰)와 별개로 검토 필요.

## 비교 후보

1. **BigQuery** (GCP)
2. **Snowflake** (멀티클라우드)
3. **Amazon Redshift** (AWS 네이티브, Serverless 옵션 포함)
4. **ClickHouse** (Cloud 관리형 또는 self-hosted)

---

## 비교 기준별 표

| 기준 | BigQuery | Snowflake | Redshift (Serverless) | ClickHouse |
|---|---|---|---|---|
| 배치 적재 방식 | GCS → load job (무료, 스토리지만 과금) | 외부 스테이지 → `COPY INTO` (컴퓨트 과금) | S3 → `COPY` (컴퓨트 과금) | `INSERT` / 파일 임포트 |
| 과금 모델 | 스토리지 + 쿼리 스캔바이트 (또는 flat-rate) | 스토리지 + 컴퓨트(크레딧, warehouse 가동시간) | 스토리지 + 컴퓨트(RPU 사용시간) | 인프라비용(self-hosted) 또는 관리형 과금 |
| 배치 워크로드 적합성 | 좋음 — 로드 자체가 무과금, 쿼리만 과금 | 좋음 — warehouse auto-suspend로 유휴비용 최소화 | 좋음 — Serverless라 유휴시 비용 거의 없음 | 좋음 — 상시 기동 필요(self-hosted 시 유휴비용 발생) |
| 운영 부담 | 서버리스, 관리 불필요 | 서버리스, 관리 불필요 | Serverless면 낮음 / 프로비저닝형이면 클러스터 관리 필요 | self-hosted면 높음(패치·백업·샤딩), Cloud면 중간 |
| 기존 인프라와의 리전 정합성 | GCP `asia-northeast3`(서울) 존재, 단 AWS와 별도 클라우드 | AWS 위탁 시 `ap-northeast-2` 지원 여부 확인 필요 | AWS 네이티브 — RDS와 **동일 리전, 크로스클라우드 이동 없음** | 배치를 어디에 두느냐에 따라 다름 |
| 이벤트 파이프라인(P0-12)과의 연계 | **이미 BigQuery Export로 전제됨 — 추가 이동 불필요** | 이벤트를 GCP→Snowflake로 재이동 필요(크로스클라우드 egress) | 이벤트를 GCP→AWS로 재이동 필요(크로스클라우드 egress) | 이벤트를 GCP→ClickHouse로 재이동 필요 |
| L1(RDS MySQL)과의 연계 | RDS→GCS 배치 export, AWS→GCP egress 비용 발생 | RDS→외부스테이지, 리전에 따라 egress 발생 가능 | RDS→S3, **동일 리전이라 egress 없음** | RDS→목적지, 배치 export 스크립트 필요(공통) |
| SQL/생태계 | Standard SQL, dbt-bigquery 성숙, GA4/Firebase Analytics 네이티브 연동 | ANSI SQL 유사, dbt 원조 지지 플랫폼, 커넥터 풍부 | PostgreSQL 방언, AWS Glue/QuickSight 등 AWS 생태계 연계 | SQL 유사하나 일부 문법 상이, 초고속 집계 특화 |
| team 학습곡선 | P0-12로 이미 손대는 중 → 추가 학습비용 최소 | 신규 학습 필요 | 신규 학습 필요(단 AWS는 이미 씀) | 신규 학습 + 운영 지식 필요 |

---

## 비용 비교 (2026년 기준 참고 단가)

> 공식 가격 페이지가 아닌 조사 시점 기준 참고치. 리전 프리미엄·실제 볼륨에 따라 달라지므로 **견적이 아니라 단가 감(感)**으로만 사용.

| 항목 | BigQuery | Snowflake (Standard) | Redshift Serverless | ClickHouse Cloud |
|---|---|---|---|---|
| 스토리지 | $0.02/GB/월(활성, 90일 이내) → **TB당 약 $20/월**, 90일 초과분은 **TB당 $10/월**로 절반 | 스토리지 별도 과금, TB당 대략 **$23~40/월**(리전별) | RA3 관리형 스토리지, TB당 대략 **$20대/월** | 모든 티어 공통 **TB당 $25.30/월** |
| 컴퓨트(배치 쿼리) | **$6.25/TB 스캔**(온디맨드), 월 1TB 스캔 무료 | Warehouse 크레딧: X-Small 1credit/h ~ Medium 4credit/h. Standard 크레딧 단가 US 기준 **$2/credit**, 비US 리전은 **30~60% 프리미엄** | **$0.375/RPU-hour**(us-east-1 기준), 최소 4RPU(=$1.50/h)부터 60초 단위 과금 | Compute unit-hour당 **$0.22(Basic)~$0.39(Enterprise)** |
| 유휴 시 과금 | **없음** — 쿼리를 안 돌리면 $0 | Auto-suspend 설정 시 **없음** | Serverless는 사용 시간만 과금 | 상시 기동 필요 — Basic(개발용) 최소 **$67/월**부터 고정 발생 |
| 배치 1회 실행 감(예시) | 100GB 스캔 배치 쿼리 1회 ≈ **$0.6** | Small(2credit/h) warehouse 10분 가동 ≈ **$0.7~1.3** | 4RPU 10분 가동 ≈ **$0.25** | 6h/일 가동 기준 개발 티어 ≈ **$67/월 고정** |

**해석**:
- 배치 위주(하루 1~수회, 짧은 실행)라는 전제와 가장 잘 맞는 건 **BigQuery**(로드 자체 무과금 + 유휴 시 $0)와 **Redshift Serverless**(유휴 시 $0) — 둘 다 "쓴 만큼만" 구조.
- **Snowflake**도 auto-suspend로 유휴비용을 없앨 수 있지만, 한국(비US) 리전 크레딧 프리미엄(최대 60%)이 붙어 단가 자체가 더 비쌈.
- **ClickHouse Cloud**는 상시 기동이 기본 전제라 배치처럼 짧게 쓰고 끄는 워크로드엔 구조적으로 불리함(최소 월 고정비 발생). self-hosted로 돌리면 이 고정비는 없어지지만 그만큼 운영 부담이 팀으로 넘어옴.
- 크로스클라우드 egress(AWS RDS → GCP BigQuery, 또는 반대 방향)는 위 표에 없음 — 이건 실제 배치 볼륨이 나와야 계산 가능(미확정 사항 참고).

---

## 핵심 트레이드오프

- **BigQuery**: 이벤트 쪽은 이미 결정된 것과 같음(P0-12). L1(RDS)→BigQuery 배치 이동만 AWS→GCP 크로스클라우드가 되어 egress 비용/지연이 생기지만, **이벤트+DB를 한 곳에서 조인**할 수 있다는 이득이 큼. 이 문서의 비교 기준 대부분에서 "추가 이동이 없다"는 항목을 이벤트 쪽에서 이미 확보한 상태.
- **Redshift**: L1(RDS)과 **동일 리전·동일 클라우드**라 정본 DB 이동은 가장 저렴/단순. 하지만 이벤트(BigQuery)를 다시 AWS로 끌고 와야 해서, 결국 어느 한쪽은 크로스클라우드 이동이 발생함 — "이동을 어느 방향으로 감당할지"의 문제로 귀결.
- **Snowflake**: 멀티클라우드라 이론상 양쪽과 다 붙을 수 있지만, 실제로는 어느 한 클라우드에 프로비저닝되므로 위 두 후보와 동일한 트레이드오프를 갖고 추가 비용(멀티클라우드 데이터 전송)이 발생할 수 있음. 대신 벤더 중립성·풍부한 커넥터 생태계가 강점.
- **ClickHouse**: 비용은 가장 낮게 만들 수 있으나(self-hosted), 배치 파이프라인 운영·스키마 마이그레이션·백업을 팀이 직접 감당해야 함. 지금 Alan 1인에게 P0 8건이 집중된 상황(alan-실행순서.md 참고)에서 추가 운영 부담을 지는 선택.

## 초안 권고

**BigQuery가 기본 후보**로 보입니다 — 이벤트 파이프라인이 이미 그쪽으로 전제돼 있어(P0-12), DW를 다른 곳에 두면 오히려 이벤트-DB 조인을 위해 데이터를 또 옮겨야 하는 역행이 됩니다. Redshift의 "동일 리전" 장점은 L1 쪽에만 해당되고 이벤트 쪽 이동 비용을 상쇄하지 못할 가능성이 큽니다.

다만 이건 정성적 판단이며, 아래 미확정 사항이 확인되기 전에는 **가결정(tentative)**으로만 취급해야 합니다.

## 확인이 필요한 미확정 사항

- [ ] 테이블별 예상 row 수 / 일일 증가량 (특히 payment_history 5.65M행 등 대형 테이블의 배치 이동 시간·비용)
- [ ] 배치 주기(1일 1회 vs 시간 단위) — 과금 구조에 영향
- [ ] 예산 상한
- [ ] **데이터 국외이전 법무 검토**(DA-P0-16과 연계) — GCP/AWS 리전이 한국(`asia-northeast3`/`ap-northeast-2`)이어도, 외국계 클라우드 사업자에 대한 개인정보 처리위탁·국외이전 신고 이슈는 별도로 발생할 수 있음. 신체정보(체지방률 등) 처리 위탁 범위와 함께 법무 확인 필요.
- [ ] AWS→GCP 크로스클라우드 egress 비용 실측 (RDS 배치 export 볼륨 기준)

## 비용 조사 출처

각 벤더 공식 가격 페이지 대신 조사 시점(2026-08) 기준 3자 집계 자료를 인용함 — 실제 계약 전 공식 페이지로 재검증 필요.

- [BigQuery Pricing Guide 2026 (Airbyte)](https://airbyte.com/data-engineering-resources/bigquery-pricing)
- [BigQuery Cost per TB Explained (yukidata)](https://yukidata.com/bigquery-cost-per-tb/)
- [Amazon Redshift Pricing Guide 2026 (CloudZero)](https://www.cloudzero.com/blog/redshift-pricing/)
- [Amazon Redshift Pricing (공식, AWS)](https://aws.amazon.com/redshift/pricing)
- [Snowflake Pricing Guide 2026 (redresscompliance)](https://redresscompliance.com/snowflake-pricing-guide-2026.html)
- [Snowflake Pricing Explained 2026 (FinOps Daily)](https://finopsdaily.com/snowflake-pricing/)
- [ClickHouse Pricing Teardown 2026 (DEV Community)](https://dev.to/beton/clickhouse-pricing-teardown-2026-209h)
- [ClickHouse Cloud Pricing Guide (Pulse Support)](https://pulse.support/kb/clickhouse-cloud-pricing-guide)
