# GCP 구조 — 조직과 프로젝트 (초안)

> 상태: 초안, 2026-10-20. 이 문서는 GCP 를 어떤 구조로 쓸지 정하기 위한 조사의 첫 단계다.
> 이번 판은 **조직과 프로젝트가 무엇인지**, **우리 조직이 지금 어떤 상태인지**, 그리고 데이터 프로젝트 결정(§9)을 다룬다.
> best practice 조사와 AWS 구성 비교는 이어서 채운다(§8).

## 1. 리소스 계층

GCP 의 모든 리소스는 하나의 나무 구조에 매달린다. 위에서 아래로 조직, 폴더, 프로젝트, 리소스다.

```
조직 (Organization)        suppliesfitness.com · 442346822205
 ├─ 폴더 (Folder)          선택. 지금은 없다
 │   └─ 프로젝트 ...
 └─ 프로젝트 (Project)     supplies-bigquery-dev · supplies-platform-sso · ...
     └─ 리소스             BigQuery dataset · 서비스 계정 · OAuth 클라이언트 · Firebase 앱 ...

결제 계정 (Billing account) 계층 밖에 따로 있다. 프로젝트마다 하나를 연결한다
```

이 계층이 중요한 이유는 **권한과 정책이 위에서 아래로 상속되기 때문이다.** 조직에 준 권한은 그 아래 모든 폴더와
프로젝트에 적용된다. 그래서 어느 층에 무엇을 거느냐가 곧 구조 설계다.

## 2. 조직 (Organization)

**회사 하나를 나타내는 계층의 뿌리다.** 공식 문서의 정의는 "회사 같은 실체를 나타내고 리소스 계층의 루트 노드" 다.

| 항목 | 내용 |
| -- | -- |
| 무엇과 묶이나 | Google Workspace 또는 Cloud Identity 계정 하나. 계정 하나에 조직은 정확히 하나다 |
| 어떻게 생기나 | 그 도메인 사용자가 처음 프로젝트를 만들 때 자동으로 생긴다 |
| 누가 관리하나 | Workspace 최고 관리자가 도메인을 관리하고, GCP 쪽에서는 조직 관리자(Organization Administrator) 역할을 누구에게 줄지 정한다 |
| 처음 상태 | 새 조직은 **도메인 전체에 프로젝트 생성자와 결제 계정 생성자 역할**을 준 채로 시작한다 |
| 소유자 | Workspace 고객 ID. 바꿀 수 없다 |

**조직이 주는 것**은 회사가 프로젝트를 소유한다는 점이다. 조직 안 프로젝트는 만든 사람이 퇴사해도 회사에 남는다.
조직 정책으로 "외부 계정 공유 금지", "허용 리전 제한" 같은 규칙을 모든 프로젝트에 한 번에 걸 수 있다.

**처음 상태가 위험하다.** 도메인의 누구나 프로젝트와 결제 계정을 만들 수 있다. 그 결과가 §6 의 "조직 밖 프로젝트
10개" 와 "용도를 모르는 프로젝트" 다. 조직을 정리할 때 가장 먼저 이 기본 역할을 거둘지 정해야 한다.

## 3. 폴더 (Folder)

**조직과 프로젝트 사이의 선택적 묶음이다.** 부서, 팀, 제품, 환경처럼 프로젝트를 모으는 단위로 쓴다. 폴더 안에 폴더를
둘 수 있고, 조직이 있어야만 쓸 수 있다.

| 쓰는 이유 | 예 |
| -- | -- |
| 권한을 한 번에 준다 | `gymboxx` 폴더에 준 역할이 그 안 모든 프로젝트에 상속된다 |
| 정책을 한 번에 건다 | `prod` 폴더에만 "서비스 계정 키 발급 금지" 를 건다 |
| 관리를 위임한다 | 폴더 관리자를 정해 그 아래 프로젝트 생성을 맡긴다 |

우리 조직에는 지금 폴더가 없다. `supplies-bigquery-dev` 는 조직 직속이다(2026-09-03 결제 연결 때 확인).
폴더를 어떤 축으로 나눌지(env, 제품, 팀)가 이 조사의 핵심 질문 중 하나다(§8).

## 4. 프로젝트 (Project)

**GCP 에서 리소스를 담는 기본 단위다.** 모든 리소스는 정확히 한 프로젝트에 속한다.

### 식별자 세 가지

| 식별자 | 예 | 정하는 사람 | 바꿀 수 있나 | 유일성 |
| -- | -- | -- | -- | -- |
| 프로젝트 ID | `supplies-bigquery-dev` | 만드는 사람 | **바꿀 수 없다** | 전 세계에서 유일. **삭제한 프로젝트의 ID 도 다시 쓸 수 없다** |
| 프로젝트 번호 | `426079268838` | GCP 가 자동 부여 | 바꿀 수 없다 | 유일 |
| 프로젝트 이름(표시 이름) | `supplies-bigquery-dev` | 만드는 사람 | 언제든 | 유일하지 않아도 된다 |

- **ID 형식:** 6~30자, 소문자로 시작, 소문자·숫자·하이픈만, 하이픈으로 끝나지 않는다
- **코드와 설정은 ID 와 번호를 쓴다.** 표시 이름은 어디에도 쓰지 않는다. 우리 코드에서는 platform-iac 의 Terraform 기본값과 WIF
  audience, platform-gitops 의 Airflow ADC 설정, data-warehouse 의 dbt profiles 와 로더가 ID 나 번호를 쓴다
- 그래서 "프로젝트 이름을 바꾼다" 는 말은 두 뜻이 된다. 표시 이름이면 아무 영향이 없고, ID 면 새 프로젝트를 만들어
  옮기는 일이다

### 프로젝트에 묶이는 것

프로젝트는 "함께 지워지고, 함께 과금되고, 같은 사람이 관리하는 묶음" 이다. 아래가 모두 프로젝트 단위다.

| 묶이는 것 | 뜻 |
| -- | -- |
| 결제 | 결제 계정이 프로젝트 단위로 연결된다. BigQuery 쿼리 비용은 job 을 실행한 프로젝트에 청구된다 |
| API 와 쿼터 | BigQuery API, IAM Credentials API 등을 프로젝트마다 켠다. 쿼터도 프로젝트마다 따로다 |
| IAM | 프로젝트 IAM 정책. 위 계층의 권한과 합쳐져 적용된다 |
| 삭제 | 프로젝트를 지우면 안의 리소스가 모두 지워진다. 30일 동안은 복구할 수 있고, 그 뒤 완전히 지워진다 |
| 프로젝트당 하나뿐인 설정 | OAuth 동의 화면, Firebase BigQuery 내보내기 대상 등 |

### 조직 밖 프로젝트

조직 없이 만든 프로젝트는 부모가 없고, **만든 사람의 개인 계정이 owner** 가 된다. 회사는 그 프로젝트를 통제하지 못한다.
나중에 조직 안으로 옮길 수 있다. 우리 조직에는 이런 프로젝트가 10개 있고, 그중 운영 중인 Firebase 프로젝트
`gymboxx-app` 이 있다(§6).

## 5. 결제 계정과 권한 상속

### 결제 계정은 계층 밖에 있다

결제 계정은 조직 아래의 노드가 아니라 **별도 리소스**다. 프로젝트마다 결제 계정 하나를 연결하고, 연결 권한은 결제 계정
쪽에 따로 있다. 2026-09-03 `supplies-bigquery-dev` 를 연결할 때, 프로젝트 owner 권한이 있어도 결제 계정 쪽
`billing.resourceAssociations.create` 가 없어 막힌 것이 그 예다.

- 우리 결제 계정: `01469E-D5C0F3-C0D338`("Product Team")
- 결제 계정을 여러 개 두면 청구서를 나눌 수 있다. 사업이 별도 법인으로 갈리는 경우가 여기에 해당한다(ADR 0021)

### 계층을 따라 내려가는 것

| 정책 | 상속 방식 |
| -- | -- |
| IAM 허용 정책(allow) | 위에서 준 역할이 아래로 상속된다. 실제 권한은 자기 정책과 모든 조상 정책의 합이다 |
| IAM 거부 정책(deny) | 위에서 건 거부가 아래로 내려간다. 허용보다 우선한다 |
| 조직 정책(organization policy) | 위에서 건 제약이 아래로 상속된다 |

**합집합이라는 점이 핵심이다.** 조직에서 넓게 준 권한은 프로젝트에서 빼앗을 수 없다. 그래서 위로 갈수록 권한은 좁게 주고,
아래에서 필요한 만큼 더한다.

## 6. 우리 조직의 현황

2026-10-19 alan·tech 두 계정으로 본 15개 프로젝트 기준이다. 전체 목록과 판정은 bible PR #168
`tech/conventions/ops/naming-gcp-resources.md` §7 에 있다. 두 계정 모두 조직 단위 조회 권한이 없어, 둘 다 접근하지
못하는 프로젝트는 빠졌을 수 있다.

| 항목 | 상태 |
| -- | -- |
| 조직 | `suppliesfitness.com` / `442346822205` |
| 조직 관리자 | **확인되지 않는다.** alan·tech 모두 조직 단위 권한이 없다 |
| 폴더 | 없다. 프로젝트가 모두 조직 직속이거나 조직 밖이다 |
| 조직 안 프로젝트 | 5개. `supplies-bigquery-dev`, `supplies-platform-sso`, `preppers-988ff`, `preppers-dev-86f89`, `document-automation-502007` |
| 조직 밖 프로젝트 | **10개.** 운영 중인 `gymboxx-app`, `preppers-kds-prod` 포함 |
| 라벨 | 규칙 라벨(`env`·`product`·`role`)이 붙은 프로젝트 0개 |
| 결제 연결 | 5개. `supplies-bigquery-dev` 와 Firebase 4개(`gymboxx-app`·`-dev`, `preppers-kds-prod`·`-dev`). 나머지는 결제 없이 무료 한도로만 쓰거나 쓰지 않는다 |

용도별로 보면 지금 프로젝트는 세 종류다.

| 종류 | 프로젝트 | 특징 |
| -- | -- | -- |
| 앱 백엔드(Firebase) | `gymboxx-app`, `gymboxx-app-dev`, `preppers-kds-prod`, `preppers-kds-dev` 등 | 앱 바이너리에 프로젝트 정보가 박혀 다시 만들 수 없다. 대부분 조직 밖이다 |
| 웨어하우스 | `supplies-bigquery-dev` | 다시 만들 수 있다. CI 가 관리한다. ADR 0021 이 `dev-gymboxx-warehouse` 로 재생성을 제안했다 |
| 사내 로그인 | `supplies-platform-sso` | OAuth 클라이언트 14개 |

## 7. AWS 와의 대응

자세한 비교는 다음 단계에서 채운다. 우선 같은 자리에 오는 개념만 맞춰 둔다.

| GCP | AWS | 차이 |
| -- | -- | -- |
| 조직 | AWS Organizations 의 조직(관리 계정) | GCP 는 Workspace 도메인에 묶인다 |
| 폴더 | 조직 단위(OU) | |
| 프로젝트 | 계정(account) | 격리 단위로서 같은 자리다. 우리는 GCP 에서 프로젝트를 여러 개 쓰고, AWS 에서는 계정을 하나만 쓴다 |
| 조직 정책 | 서비스 제어 정책(SCP) | |
| 결제 계정 | 관리 계정의 통합 결제 | GCP 는 결제 계정을 여러 개 두고 프로젝트마다 고를 수 있다 |

**우리 AWS 는 계정 `699016088228` 하나에 dev·prod 가 함께 있다.** 그래서 AWS 에서는 리소스 이름이 env 경계이고,
GCP 에서는 프로젝트가 env 경계다. 같은 회사가 두 클라우드에서 env 를 다르게 나누고 있다는 점을 비교 단계에서 다룬다.

## 8. 다음에 조사할 것

이 초안을 바탕으로 정해야 하는 질문이다.

1. **조직 관리자를 누구로 할지.** 이것이 정해지지 않으면 조직 밖 프로젝트 편입, 폴더 도입, 조직 정책 확인이 모두 막힌다
2. **처음 상태의 기본 역할을 거둘지.** 도메인 전체의 프로젝트 생성자·결제 계정 생성자 역할
3. **폴더를 어떤 축으로 나눌지.** env(`dev`/`prod`) 우선인지, 제품(`gymboxx`/`preppers`) 우선인지. 권한과 정책을 어디에
   거느냐로 판정한다
4. **조직 밖 프로젝트 10개를 어떻게 옮길지.** 옮기는 데 필요한 권한, 옮길 때 Firebase·결제에 미치는 영향
5. **조직 정책 기본값.** 서비스 계정 키 발급 금지, 허용 리전, 외부 도메인 공유 금지 등 무엇을 켤지
6. **best practice:** Google 의 엔터프라이즈 기반 청사진(enterprise foundations blueprint)과 랜딩 존 권장 구조를 읽고, 우리
   규모에 맞는 만큼만 가져온다
7. **AWS 구성과 비교해 반영할 것:** 계정 하나 구조인 AWS 와 프로젝트 여러 개 구조인 GCP 의 규칙을 어떻게 맞출지

## 9. 결정 — 데이터 프로젝트는 `prod-supplies-data` (2026-10-20)

**웨어하우스 GCP 프로젝트를 `prod-supplies-data` 로 한다.** 제품별로 나누지 않고, 모든 제품의 데이터를 env 별
프로젝트 하나에 담는다. dev 짝은 같은 규칙으로 `dev-supplies-data` 로 본다(확정 필요).

### 근거

- **GCP 는 데이터 용도로만 쓴다.** 앱 서버 같은 서비스를 GCP 에 올릴 계획이 당분간 없다. Firebase 도 지금은 데이터
  수집 용도로 쓰고 있다. 그래서 프로젝트를 나눌 축은 제품이 아니라 env 하나로 충분하다
- **격리는 env 단위로 한다.** dev 와 prod 는 보안 정책이 다르다. 서비스 경계(VPC Service Controls)와 조직 정책은
  프로젝트 단위로 걸리므로 env 는 프로젝트로 나눈다. AWS 의 `dev-vpc` / `prod-vpc` 와 같은 자리다
- **제품은 dataset 으로 가른다.** AWS 도 계정 하나에 전 제품을 두고 이름과 태그로 가른다. 같은 방식을 따른다
- **이름:** `{env}-{product}-{role}` 에서 product 는 플랫폼 공용인 `supplies`, role 은 `data` 다

### 구조

```
조직 suppliesfitness.com
 ├─ dev-supplies-data      raw_gymboxx · silver_gymboxx · mart_gymboxx (· 다른 제품 dataset)
 ├─ prod-supplies-data     같은 구조. 서비스 경계·엄격한 조직 정책을 여기에 건다
 └─ Firebase 프로젝트들     gymboxx-app 등. 다시 만들 수 없어 제자리에 두고, 데이터 프로젝트가 건너 읽는다
```

- **dataset 이름은 지금대로 `<layer>_<product>` 를 유지한다.** 프로젝트가 env 경계이고 제품은 dataset 이름이
  가르므로, 명명 컨벤션이 미결로 남긴 "product 세그먼트 중복" 문제가 생기지 않는다
- 데이터 프로젝트가 둘뿐이라 폴더는 지금 필요하지 않다. 프로젝트가 늘거나 env 별 정책을 여러 프로젝트에 걸어야 할 때 둔다

### 따라오는 일

| 할 일 | 위치 |
| -- | -- |
| ADR 0021 을 이 결정으로 고쳐 썼다(`0021-data-project-per-env.md`) | bible PR #168, 2026-10-20 반영 |
| GCP 명명 컨벤션의 role `warehouse` 를 `data` 로 바꿨다 | bible PR #168 §5, 2026-10-20 반영 |
| `supplies-bigquery-dev` 를 `dev-supplies-data` 로 다시 만든다. dataset 2개, SA 2개, WIF pool·provider 2쌍, ADC 파일 | Linear TECH-3111. platform-iac `bootstrap/gcp`, `stacks/data/bigquery/dev` |
| prod 보안 경계 설계. 서비스 경계 dry-run, 출발지(prod NAT IP·사무실), VPN 필요 여부 | prod 프로젝트 생성 때 |

## 참고

- GCP 리소스 계층: https://cloud.google.com/resource-manager/docs/cloud-platform-resource-hierarchy
- 프로젝트 만들기와 관리(ID 규칙, 삭제): https://cloud.google.com/resource-manager/docs/creating-managing-projects
- bible PR #168 — GCP 리소스 명명 컨벤션(감사 결과)과 ADR 0021(웨어하우스 제품별 프로젝트)
- platform-iac `docs/data-pipeline/2026-09-03-gcp-billing-permission-request.md` — 결제 계정 연결 경위
