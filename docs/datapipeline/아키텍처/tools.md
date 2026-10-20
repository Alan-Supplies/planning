# 데이터 도구 — 각 도구가 무엇이고 왜 쓰는가

> 상태: 초안, 2026-10-20. `research.md` 의 "Data tool 이해" 항목에 답한다.
> 이 문서는 **도구가 무엇인지, 우리 파이프라인에서 어느 자리를 맡는지, 왜 그것을 골랐는지**만 다룬다.
> 각 구간의 상세 설계는 맨 아래 "참고" 의 원문 문서에 있다. 값(버전·이름)이 이 문서와 코드가 다르면 코드가 맞다.

## 1. 한 장 그림

```
gymboxx MySQL ──DMS──▶ S3 Bronze ──Airflow 적재 task──▶ BigQuery raw_gymboxx ──dbt──▶ silver_gymboxx ──dbt──▶ mart_gymboxx ──▶ Metabase
 (원천 DB)    (수집)  (원본 로그)      (적재)              (착륙)                (변환)   (SSOT)          (변환)  (Gold)         (소비)
                         │
                         └─ Glue Catalog + Athena : Bronze 를 SQL 로 바로 들여다보는 조사·검증용 창구

Airflow : 위 적재·변환 task 를 언제, 어떤 순서로 돌릴지 정한다 (오케스트레이션)
```

| 레이어 | 어디에 있나 | 맡는 도구 |
| -- | -- | -- |
| Bronze | S3 `supplies-bronze-dev` (Parquet) | DMS 가 쓰고, Glue/Athena 로 조회 |
| (착륙) raw | BigQuery `raw_gymboxx` | Airflow task(`loaders/bronze_to_raw.py`)가 Bronze 를 그대로 옮긴다 |
| Silver | BigQuery `silver_gymboxx` | dbt 증분 MERGE |
| Gold | BigQuery `mart_gymboxx` (예정) | dbt |
| 소비 | Metabase, BigQuery 직접 조회 | — |

## 2. 도구를 계층으로 나눠 보기

"ETL 툴" 이라는 말은 서로 다른 일을 뭉뚱그린다. 도구마다 맡는 일이 다르고, **대부분은 서로의 대안이 아니라 함께 쓰는
것**이다. 예를 들어 Airflow 와 dbt 는 경쟁 관계가 아니다 — Airflow 가 "언제 돌릴지", dbt 가 "무엇을 만들지" 를 맡는다.

| 계층 | 하는 일 | 우리 도구 | 업계에서 같은 자리의 다른 도구 |
| -- | -- | -- | -- |
| 원천 | 서비스가 실제로 읽고 쓰는 DB | MySQL (gymboxx) | — |
| 수집(Extract) | 원천의 데이터와 변경분을 빼낸다 | AWS DMS | Debezium, Airbyte, Fivetran |
| 저장(Lake) | 빼낸 원본을 싸게, 오래, 그대로 쌓는다 | S3 + Parquet | GCS, ADLS |
| 카탈로그·즉석 조회 | 파일 더미를 테이블처럼 보이게 하고 SQL 로 읽는다 | Glue Data Catalog + Athena | Hive Metastore + Trino/Presto |
| 적재(Load) | 레이크의 파일을 웨어하우스 테이블로 옮긴다 | Airflow task (Python, BigQuery load job) | BigQuery Data Transfer Service, Airbyte |
| 웨어하우스 | 정제된 데이터를 저장하고 분석 쿼리를 빠르게 돌린다 | BigQuery | Redshift, Snowflake |
| 변환(Transform) | SQL 로 데이터를 정제·조합해 Silver/Gold 를 만든다 | dbt Core | Dataform, SQLMesh |
| 오케스트레이션 | 작업의 순서·주기·재시도·의존을 관리한다 | Airflow | Dagster, Prefect, Step Functions |
| 소비(BI) | 사람이 차트·대시보드로 데이터를 본다 | Metabase | Looker Studio, Superset, Tableau |
| 기반 | 위 도구를 띄우고 인증·배포한다 | EKS, Helm, ArgoCD, git-sync, ECR, Terraform, IRSA·WIF | — |

## 3. 도구별 정리

각 도구를 같은 틀로 적는다 — **무엇인가 / 우리 파이프라인에서 하는 일 / 왜 이것인가 / 주의할 점.**

### 3.1 AWS DMS (Database Migration Service)

**무엇인가.** AWS 의 관리형 데이터 복제 서비스다. 원천 DB 에 붙어 두 가지를 한다.

- **Full Load:** 테이블의 현재 상태를 통째로 한 번 떠 온다 (스냅샷)
- **CDC (Change Data Capture):** 그 뒤로 일어나는 INSERT·UPDATE·DELETE 를 DB 의 변경 로그(MySQL binlog)에서 읽어 계속 흘려보낸다

**우리 파이프라인에서 하는 일.** gymboxx MySQL 의 변경을 S3 Bronze 에 Parquet 파일로 떨어뜨린다. full 은 `full/<날짜>/`,
cdc 는 `cdc/<테이블>/<날짜>/` 아래에 쌓인다. 행마다 DMS 가 메타 컬럼 두 개를 붙인다.

| 컬럼 | 뜻 |
| -- | -- |
| `Op` | `I`(insert)·`U`(update)·`D`(delete) |
| `dms_commit_ts` | 원천에서 그 변경이 커밋된 시각 |

**왜 이것인가.**

- **커넥터를 직접 만들지 않는다**는 원칙 때문이다. 변경분 추출을 직접 짜면 누락·순서·재시작을 우리가 책임져야 하고, 이것이
  데이터 파이프라인에서 가장 흔한 실패 지점이다
- 원천 DB 가 AWS(RDS)에 있어 같은 클라우드의 관리형 서비스가 붙이기 가장 쉽다
- 주기적인 `SELECT` 덤프와 달리 binlog 를 읽으므로 **DELETE 도 잡히고**, 운영 DB 에 무거운 쿼리를 날리지 않는다

**주의할 점.**

- **at-least-once 다.** 재시작이나 full load 도중 쓰기가 몰리면 같은 변경이 두 번 들어올 수 있다. 중복 제거는 Silver MERGE 의 책임이다
- 같은 트랜잭션 안의 변경은 `dms_commit_ts` 가 같아 순서를 가를 수 없다. 그래서 파일 이름과 파일 안 행 순서(`_bronze_file`, `_bronze_row`)로 tie-break 한다
- 원천에 컬럼이 추가되면 **그 뒤 파일부터** 새 구조로 쓰고 기존 파일은 고치지 않는다. 한 경로 안에 스키마가 다른 파일이 섞이는 것이 정상이다
- 압축 기본값이 `none` 이라 `gzip` 을 명시해야 한다(실측 -81.7%)

### 3.2 Amazon S3 + Parquet — Bronze

**무엇인가.**

- **S3** 는 AWS 의 오브젝트 스토리지다. 용량 제한 없이 싸게 파일을 쌓는다
- **Parquet** 는 컬럼 단위로 저장하는 파일 포맷이다. 같은 컬럼 값이 모여 있어 압축이 잘 되고, 필요한 컬럼만 읽을 수 있어
  분석 쿼리가 싸다. 스키마(컬럼 이름·타입)가 파일 안에 함께 들어 있다

**우리 파이프라인에서 하는 일.** Bronze 다. **원천의 변경 이력을 손실·변형 없이 쌓아 둔 원본 로그**이고, 목적은 하나 —
**Silver 를 언제든 처음부터 다시 만들 수 있게 하는 것**이다. S3 는 Bronze 전용이고 Silver/Gold 는 BigQuery 에만 있다.

| 원칙 | 뜻 |
| -- | -- |
| append-only / immutable | 한 번 쓴 파일은 고치지 않는다. 쓰는 주체는 DMS 하나뿐이다 |
| 변환 금지 | 타입 변환·마스킹·파생 컬럼 없음. DMS 메타 컬럼만 예외 |
| 중복 허용 | 중복 제거는 Silver 에서 한다 |
| 보존 기간 내 삭제 금지 | Bronze 를 지우면 재구축 능력이 사라진다 |

**왜 이것인가.**

- 원천이 AWS 에 있으니 수집 결과를 같은 클라우드에 먼저 내려놓는 것이 가장 싸고 단순하다
- 웨어하우스(BigQuery)가 바뀌거나 Silver 로직이 틀려도 **원본이 남아 있으면 다시 만들면 된다.** 웨어하우스와 원본 보관을 분리하는 이유다
- Parquet 는 Athena 와 BigQuery 가 모두 읽는 공통 포맷이다

**주의할 점.** 순수 파일 레이크는 "특정 회원 데이터만 지우기" 가 어렵다(개인정보 삭제 요구와 immutable 원칙의 충돌).
Iceberg 같은 테이블 포맷이 이 문제의 답이지만, 실제 삭제 요구가 생길 때 켜는 옵션으로 미뤄 두었다.

### 3.3 AWS Glue Data Catalog + Amazon Athena — Bronze 조회 창구

**무엇인가.**

- **Glue Data Catalog** 는 "S3 의 이 경로에 있는 파일들은 이런 컬럼을 가진 테이블이다" 라는 **메타데이터 저장소**다. 데이터는 S3 에 그대로 있고, 정의만 등록한다
- **Athena** 는 그 카탈로그를 보고 S3 파일에 바로 SQL 을 던지는 서버리스 쿼리 엔진이다(Presto/Trino 기반). 스캔한 바이트만큼 과금한다

**우리 파이프라인에서 하는 일.** **조사와 검증용**이다. 상시 지표 서비스에는 쓰지 않는다.

- DMS 가 제대로 쌓고 있는지 확인한다 (TECH-862 완료 기준이 Athena 로 INSERT/UPDATE/DELETE 를 확인하는 것)
- `*_current` 뷰로 PK 별 최신 상태를 만들어 **Silver 행 수와 대조**한다 (2026-10-19 대조에서 차이 원인을 찾은 것이 그 예)
- 장애 때 "그 이벤트가 Bronze 에 들어왔는가" 를 BigQuery 를 거치지 않고 바로 본다

**왜 이것인가.** 원본이 S3 에 있으니 옮기지 않고 그 자리에서 보는 가장 싼 방법이다. 별도 서버가 없다.

**왜 이것만으로 끝내지 않는가 — "Athena 로도 되는데 왜 BigQuery?"** 자주 나오는 질문이라 경계를 못 박는다.

| | Athena | BigQuery |
| -- | -- | -- |
| 맡는 일 | 원본 조사·검증 | Silver/Gold 저장, 상시 지표·BI |
| 데이터 | S3 파일 그대로 (immutable) | 정제·MERGE 된 테이블 |
| 행 단위 갱신 | 어렵다 | `MERGE` 로 된다 |
| 마케팅 데이터(GA4·광고·Firebase) | 없다 | 네이티브 연동 |

**주의할 점.** Athena 는 파일 안 행 순서를 알 수 없어 같은 트랜잭션 동점에서 `*_current` 뷰가 Silver 와 다른 행을 고를 수 있다.
Glue 테이블 정의는 Terraform 이 소유하고, DMS 의 `GlueCatalogGeneration` 은 쓰지 않는다.

### 3.4 Google BigQuery — 웨어하우스

**무엇인가.** Google Cloud 의 서버리스 데이터 웨어하우스다. 서버·클러스터를 띄우지 않고 SQL 을 던지면 Google 이 알아서
병렬로 처리한다. 컬럼 저장이라 대량 집계가 빠르고, 기본 과금은 **쿼리가 스캔한 바이트(on-demand)** + 저장 용량이다.

주요 개념:

| 개념 | 뜻 | 우리 예 |
| -- | -- | -- |
| 프로젝트 | 과금·권한의 단위 | `supplies-bigquery-dev` (→ `dev-supplies-data` 로 재생성 예정, `GCP_구조.md` §9) |
| dataset | 테이블을 담는 폴더. 리전과 권한이 여기 붙는다 | `raw_gymboxx`, `silver_gymboxx`, `mart_gymboxx` |
| 파티션 | 테이블을 날짜 등으로 쪼개 필요한 부분만 스캔 | raw 의 `_bronze_date` |
| 클러스터링 | 파티션 안에서 컬럼 값으로 정렬해 스캔을 줄임 | Silver 의 `id` |
| load job | 파일을 테이블로 넣는 작업. 무료다 | Bronze Parquet → `raw_gymboxx` |

**우리 파이프라인에서 하는 일.** **정본 DW 다.** raw(착륙)·Silver·Gold 가 모두 여기 있고, Metabase 와 분석가가 여기서 읽는다.

**왜 이것인가 — 원천은 AWS 인데 웨어하우스만 GCP 인 이유.**

- **마케팅·행동 데이터가 이미 그쪽에 있다.** Firebase Analytics(앱 이벤트)는 BigQuery 내보내기를 켜는 것만으로 들어온다(ADR 0014·0015). GA4·광고 데이터도 네이티브 연동이다
- **서버를 관리하지 않는다.** 데이터 전담 인력이 없는 지금 클러스터 사이징·튜닝 부담이 없다
- 캠페인 도구들이 BigQuery 직접 연동을 지원해 Reverse ETL 도구를 따로 들이지 않아도 된다

**대가.** 클라우드가 둘이라 AWS → GCP 이동 비용·지연이 생기고, 권한 관리가 이원화된다(IRSA·WIF, §3.8). 그래서 두 클라우드
사이 이동은 Airflow 한 곳에서만 한다.

**Redshift 는?** `prod-dw`(Redshift Serverless)는 TECH-1631(PASS 선수금 부채) 전용 **별개 트랙**이다. 이 파이프라인과 엮지 않는다.

### 3.5 Bronze → raw 적재 — Airflow task (BigQuery load job)

**무엇인가.** 별도 제품이 아니라 우리 코드다. `loaders/bronze_to_raw.py` 가 S3 Parquet 을 읽어 BigQuery load job 으로
`raw_gymboxx.<table>_<cdc|full>` 에 올린다. `bronze_to_raw_gymboxx` DAG 가 매시 부른다.

**하는 일.**

- (테이블, 날짜 폴더) 단위로 그 날짜 파티션을 **통째로 교체**한다 → 몇 번 다시 돌려도 결과가 같다(멱등)
- 원본을 바꾸지 않고 추적용 컬럼만 붙인다: `_bronze_date`, `_bronze_file`, `_bronze_row`
- 테이블은 S3 폴더에서 발견한다 — DMS 에 테이블을 추가하면 다음 실행부터 따라온다

**왜 이 방식인가.** 대안 넷을 견줬다(`bronze-to-bigquery-load-design.md` §1).

| 방법 | 판정 |
| -- | -- |
| **Airflow 가 직접 load job (채택)** | 이미 깔린 권한(IRSA 로 S3 읽기, WIF 로 BigQuery 쓰기)과 정확히 같은 모양. 새 인프라가 dataset 하나뿐 |
| S3 → GCS 복사 후 load | 버킷·권한·복사 단계가 는다. 지금 볼륨에서 얻는 것이 없다 |
| BigQuery Data Transfer Service | 기본이 AWS 장기 액세스 키라 "장기 키를 없앤다" 원칙과 충돌 |
| BigQuery Omni (S3 를 제자리에서 조회) | Silver 는 모든 행을 읽어야 해 결국 전량이 매 실행 옮겨진다 |

> 초기 결정(TECH-864 runbook)은 "S3 → BigQuery 적재 주체는 dbt Core" 였으나, 2026-10-16 설계에서 **적재는 Airflow task,
> 변환만 dbt** 로 나뉘었다. dbt 는 SQL 변환 도구라 S3 파일을 옮기는 일에 맞지 않는다.

**주의할 점.** 파일이 worker 메모리를 거쳐 업로드되므로 prod 볼륨에서는 GCS 경유로 바꿀지 다시 본다. 바뀌어도 raw 테이블 계약은 그대로다.

### 3.6 dbt Core — 변환

**무엇인가.** SQL `SELECT` 문으로 테이블을 정의하면, 그것을 웨어하우스에 `CREATE TABLE`·`MERGE` 로 바꿔 실행해 주는 변환
도구다. 직접 데이터를 옮기거나 저장하지 않는다 — **웨어하우스 안에서 SQL 을 만들어 던질 뿐**이다. "Core" 는 오픈소스 CLI
판이고, 유료 SaaS 판(dbt Cloud)은 쓰지 않는다.

dbt 가 주는 것:

| 기능 | 뜻 | 우리 예 |
| -- | -- | -- |
| 모델 | `.sql` 파일 하나 = 테이블 하나 | `dbt/models/gymboxx/user_exercise_session.sql` |
| `ref()` / `source()` | 모델 간 의존을 선언하면 실행 순서를 알아서 정한다 | `_sources.yml` 이 raw 테이블을 선언 |
| materialization | 테이블을 어떻게 만들지 — `table`, `view`, `incremental` | Silver 는 `incremental` + `merge` |
| 매크로 | SQL 을 함수처럼 재사용 (Jinja) | `cdc_current.sql` — full ∪ cdc 에서 PK 별 최신 행 고르기 |
| 테스트 | `unique`, `not_null` 등을 선언하면 검사 쿼리를 돌린다 | `dbt build` 가 모델 직후 테스트, 실패하면 task 실패 |
| 문서·계보 | 모델 설명과 의존 그래프를 생성 | (아직 쓰지 않음) |

**우리 파이프라인에서 하는 일.** raw → Silver(지금), Silver → Gold(예정). `silver_gymboxx` DAG 가
`dbt build --select supplies_dw.gymboxx` 를 부른다.

**왜 이것인가.**

- **지표 정의가 이 프로젝트의 핵심 자산이다.** dbt 를 쓰는 진짜 이유는 편의가 아니라 정의를 git 으로 관리하고, 테스트와 이력을 붙일 수 있다는 것이다
- SQL 만 알면 쓸 수 있다. 데이터 전담 인력이 붙어도 학습 비용이 낮고, 사실상 업계 표준이라 자료가 많다
- 대안 Dataform 은 BigQuery 전용이라 도구 수는 줄지만, 웨어하우스에 묶인다

**주의할 점.** DAG 파일에서 dbt 를 모듈 레벨로 `import` 하지 않는다 — scheduler 는 공식 이미지라 dbt 가 없다. `BashOperator` 로 실행 시점에 부른다.

### 3.7 Apache Airflow — 오케스트레이션

**무엇인가.** 작업(task)의 **순서·주기·재시도·의존**을 Python 코드(DAG)로 정의하고 실행하는 워크플로 스케줄러다. 스스로
데이터를 변환하지 않는다 — "매시 정각에 적재를 돌리고, 성공하면 dbt 를 돌려라. 실패하면 5분 뒤 한 번 더" 를 관리한다.

주요 개념:

| 개념 | 뜻 | 우리 예 |
| -- | -- | -- |
| DAG | 작업들의 순서 그래프 하나 | `bronze_to_raw_gymboxx`, `silver_gymboxx` |
| task / operator | DAG 안의 작업 단위 | `BashOperator` 로 스크립트·dbt 실행 |
| schedule | 언제 돌릴지. cron 또는 데이터 이벤트 | 적재는 `@hourly`, Silver 는 `raw_gymboxx` Asset 이벤트 |
| Asset | "이 데이터가 갱신됐다" 이벤트로 다음 DAG 를 깨운다 (Airflow 3) | 적재 성공 → Silver 실행 |
| executor | task 를 어디서 실행할지 | KubernetesExecutor — task 마다 pod 를 띄웠다 지운다 |

**우리 파이프라인에서 하는 일.** Bronze → raw 적재와 raw → Silver 변환을 순서대로 돌리고, AWS ↔ GCP 경계를 넘는 유일한 자리다.
dev-eks 에 Airflow 3.2.2 로 떠 있다(2026-10-16 배포).

**왜 이것인가.**

- **사실상 표준이다.** 자료·채용·연동(provider) 생태계가 가장 크다
- **EKS self-host** 로 띄운다. 이미 EKS·ArgoCD·Helm 운영 체계가 있어 추가 비용이 작다. 관리형(MWAA, Cloud Composer)은 운영이 편한 대신 상시 비용이 든다
- **KubernetesExecutor:** 파이프라인이 얼마나 늘지 미리 예측할 필요가 없다. task 마다 pod 를 띄우므로 cluster autoscaler 가 흡수한다

**주의할 점.**

- worker 이미지(Dockerfile)의 Airflow 버전은 Helm 차트의 `appVersion` 과 같아야 한다
- DAG 는 git-sync 로 실어 나르므로 **push 하면 반영된다.** 이미지 재빌드는 Dockerfile·dbt 의존성이 바뀔 때만
- 무거운 로직을 DAG 파일에 두지 않는다 — scheduler 가 파싱할 때마다 import 가 실행된다. 그래서 `loaders/` 를 `dags/` 밖에 둔다

### 3.8 기반 도구 — 띄우고, 배포하고, 인증한다

데이터 도구는 아니지만 위 도구들이 돌아가려면 필요하다.

| 도구 | 무엇인가 | 우리 파이프라인에서 하는 일 |
| -- | -- | -- |
| EKS (Kubernetes) | AWS 의 관리형 Kubernetes | Airflow 가 사는 곳. `dev-eks` 의 전용 nodepool `dev-eks-airflow-2a` |
| Helm | Kubernetes 앱 패키지 관리자 | 공식 Airflow 차트(1.22.0)로 설치 |
| ArgoCD | git 의 선언을 클러스터에 맞추는 GitOps 도구 | `platform-gitops` 의 `airflow` Application 을 배포 |
| git-sync | git 레포를 pod 안 디렉터리로 주기적으로 당기는 사이드카 | 이 레포 전체를 `/opt/airflow/dags/repo` 로 실어 나른다 |
| ECR | AWS 컨테이너 이미지 저장소 | worker 이미지 `airflow/worker` (태그 IMMUTABLE) |
| Terraform | 인프라를 코드로 선언하는 도구 | DMS·S3·Glue·BigQuery dataset·IAM·WIF 를 `platform-iac` 에서 관리 |
| IRSA | EKS pod 에 AWS IAM 역할을 주는 방식 | worker 가 S3 Bronze 를 읽는다 |
| WIF (Workload Identity Federation) | 외부(AWS) 신원을 GCP 서비스 계정으로 바꿔 주는 방식 | worker 가 **SA 키 파일 없이** BigQuery 에 붙는다 |

**IRSA + WIF 가 클라우드 둘을 잇는 고리다.** worker pod 는 IRSA 로 AWS 신원을 얻고, 그 신원을 WIF 로 GCP 서비스 계정
`dev-airflow-dbt-core` 토큰으로 바꾼다. 장수명 키를 어디에도 저장하지 않는다. 그래서 BigQuery 에 붙는 명령은 모두
`bin/with-aws-env` 로 감싼다(README "GCP 인증").

### 3.9 Metabase — 소비 (BI)

**무엇인가.** 오픈소스 BI 도구다. 웨어하우스에 연결해 SQL 이나 클릭으로 질문을 만들고, 차트·대시보드로 공유한다.
self-host(오픈소스, 무료)와 Metabase Cloud(유료) 두 형태가 있다.

**우리 파이프라인에서 하는 일.** `research.md` 가 정한 **첫 번째 소비처**다 — 운동기록 데이터를 Metabase 로 본다.
Gold(`mart_gymboxx`)의 fact/dim 테이블을 읽는 것이 목표다. 두 번째 소비처(Austin·Connor)는 Metabase 가 아니라 BigQuery 직접
조회 + HQ 다.

**왜 이것인가.** 비개발자가 SQL 없이도 질문을 만들 수 있고, self-host 하면 라이선스 비용이 없다. BigQuery 커넥터를 기본 지원한다.

**미정.** 어디에 띄울지(EKS self-host vs Cloud), 연결 서비스 계정과 권한 범위, Metabase 가 읽을 dataset 을 Gold 로만 제한할지는
아직 정하지 않았다(§5).

### 3.10 Firebase Analytics → BigQuery 내보내기 — 이벤트 수집 (참고)

이 레포의 파이프라인은 아니지만 같은 웨어하우스로 들어오는 두 번째 수집 경로다. 앱·키오스크·웹의 클라이언트 이벤트는 Firebase
Analytics 의 BigQuery 실시간 내보내기로 적재하고, 자체 수집 서버는 만들지 않는다(ADR 0014). 대가는 best-effort 전달 — 유실된
이벤트는 복구되지 않으므로 정산·감사 용도로 쓰지 않는다.

## 4. 자주 헷갈리는 것

| 질문 | 답 |
| -- | -- |
| Airflow 는 GCP 에 있나? | **아니다. AWS 에 있다.** dev-eks(`ap-northeast-2`, 계정 `699016088228`)의 `airflow` 네임스페이스에 ArgoCD `airflow` 앱으로 떠 있다(2026-10-20 pod·노드 확인). Cloud Composer 는 쓰지 않는다. 결과물(raw·Silver)이 BigQuery 에 생겨 "GCP Airflow" 로 부르기 쉽지만, 실제로는 AWS 의 worker pod 가 IRSA → WIF 로 GCP 토큰을 받아 BigQuery 에 쿼리를 던진다 (§3.8) |
| dbt 는 GCP 에 있나? raw → Silver 가 GCP 안에서 도는데? | **dbt 도 AWS 에 있다.** 별도 서버가 아니라 worker 이미지에 설치된 CLI 로, Airflow task pod(dev-eks) 안에서 `dbt build` 로 실행된다. dbt 는 데이터를 옮기지 않고 **SQL 문자열을 BigQuery API 로 보낼 뿐**이며, `MERGE` 는 BigQuery 가 자기 안에서 실행한다. 명령은 AWS 에서 나가고 데이터는 GCP 안에서만 움직인다. 반면 Bronze → raw 는 Python 스크립트가 파일을 worker 를 거쳐 실제로 옮긴다 (§3.5, §3.6) |
| Airflow 와 dbt 중 하나만 쓰면 안 되나? | 하는 일이 다르다. Airflow 는 "언제·어떤 순서로", dbt 는 "어떤 테이블을 어떤 SQL 로". dbt 는 스케줄러가 없고, Airflow 는 SQL 모델·테스트 관리가 없다 |
| Athena 가 있는데 왜 BigQuery 가 필요한가? | Athena 는 immutable 원본을 조사하는 창구, BigQuery 는 정제된 SSOT 와 상시 지표를 맡는다. 마케팅·이벤트 데이터도 BigQuery 에 있다 (§3.3) |
| Bronze 가 S3 에 있는데 BigQuery 에 raw 가 또 있는 이유? | dbt 는 BigQuery 안에서만 SQL 을 돌린다. S3 파일을 BigQuery 테이블로 한 번 옮겨 둬야 이후 변환이 모두 GCP 안에서 끝난다. raw 는 Bronze 의 사본이지 새 레이어가 아니다 |
| DMS 가 BigQuery 로 바로 쓰면 안 되나? | DMS 의 타깃에 BigQuery 가 없다. 또 원본을 웨어하우스와 분리해 두어야 Silver 를 다시 만들 수 있다 |
| Redshift 는 왜 따로 있나? | TECH-1631 전용 PoC 트랙이다. 이 파이프라인과 엮지 않는다 |

## 5. 아직 정하지 않은 것

1. **Metabase 배포 위치와 권한.** EKS self-host vs Metabase Cloud, BigQuery 연결 서비스 계정, 읽기 범위(Gold 만인지)
2. **prod 구성.** 지금은 dev(dev-eks, `supplies-bigquery-dev`)만 있다. prod Airflow 위치와 `prod-supplies-data` 프로젝트
3. **prod 볼륨에서의 적재 방식.** Airflow 직접 업로드를 유지할지, GCS 경유로 바꿀지 (§3.5)
4. **원본이 GCP 로 넘어가도 되는가.** 개인정보 정책을 정할 때 다시 연다. 안 된다면 Omni 로 방향이 바뀐다
5. **dbt 문서·계보(`dbt docs`)를 쓸지.** 소비자가 늘면 테이블 설명을 어디서 볼지와 함께 정한다

## 참고

| 문서 | 위치 | 내용 |
| -- | -- | -- |
| 분석 레이크 계층 원칙 | bible `tech/architecture/데이터/분석_레이크_계층_원칙.md` | 계층별 소유 경계(§5), 원칙 준수 현황(§6) |
| (옛) 데이터 플랫폼 — 레이크 경계와 계층별 도구 선택 | bible `tech/architecture/data/data-platform.md` — **main 에 없다.** dbcc84a(#141, 2026-10-02) 이전 커밋에만 있다 | 이 문서의 도구별 대안 비교와 "웨어하우스만 GCP 인 이유" 의 출처. 재편 때 이 내용은 빠졌다 |
| Lake(Bronze) S3 구조 설계 | platform-iac `docs/data-pipeline/2026-08-20-lake-bronze-s3-design.md` | Bronze 원칙, DMS 설정값, Glue/Athena 연결 |
| Airflow / dbt Core dev-eks runbook | platform-iac `docs/data-pipeline/2026-08-19-airflow-dbt-dev-eks-runbook.md` | executor·실행 위치·인증 결정 |
| GCP 프로젝트·WIF 설계 | platform-iac `docs/data-pipeline/2026-09-02-bigquery-warehouse-gcp-wif-design.md` | IRSA → WIF 경로 |
| S3 Bronze → BigQuery 적재 설계 | platform-iac `docs/data-pipeline/2026-10-16-bronze-to-bigquery-load-design.md` | 적재 방식 4안 비교, raw 테이블 계약 |
| Silver 스키마 설계 | `docs/2026-10-20-silver-schema-design.md` | Silver grain·키·MERGE 정책 |
| GCP 구조 | `docs/아키텍처/GCP_구조.md` | 조직·프로젝트, 데이터 프로젝트 결정 |
| ADR 0014 · 0015 | bible `tech/adr/` | Firebase 이벤트 적재 경로, Firebase 프로젝트 통합 |
