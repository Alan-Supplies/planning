# 문제 2. VPC 안에서만 접근되는 Terraform을 GitHub Actions로 돌리기

> 이 문서는 `GHA-문제-조사.md`의 **문제 2만** 떼어내, 배경 지식이 없어도 읽을 수 있게 다시 쓴 것입니다.
> 공식 문서와 대조해 표현을 정정한 부분은 각 항목에 표시했습니다. Docker Hub rate limit(문제 1)은 원본 문서를 참고하세요.

---

## 0. 용어 5개만 먼저

| 용어 | 한 줄 설명 |
| --- | --- |
| **GitHub Actions** | GitHub에 코드를 푸시하면 자동으로 명령을 실행해주는 CI 서비스. |
| **러너(runner)** | 그 명령을 **실제로 실행하는 컴퓨터**. GitHub이 빌려주는 게 `GitHub-hosted`, 우리가 직접 준비하는 게 `self-hosted`. |
| **VPC / private subnet** | AWS 안에 만든 우리 전용 사설 네트워크. private subnet에 있는 것은 **인터넷에서 직접 접근 불가**. |
| **NAT gateway** | private subnet의 서버가 "밖으로 나가는" 통신만 가능하게 해주는 출구. 밖에서 들어오는 건 안 됨. |
| **Terraform provider** | Terraform이 특정 대상(AWS, Kubernetes, MySQL…)과 대화할 때 쓰는 플러그인. **provider마다 접속하는 주소가 다르다**는 게 이 문서의 핵심. |

---

## 1. 문제가 뭔가

GitHub-hosted 러너는 **인터넷에 있는 남의 컴퓨터**입니다. 우리 사설망(VPC) 안의 것에는 손이 닿지 않습니다.

```text
[GitHub-hosted 러너]  ──인터넷──▶  AWS API (EC2/S3/IAM …)        ✅ 잘 됨
                      ──인터넷──▶  private EKS API                ❌ 막힘
                      ──인터넷──▶  internal ALB / RDS / OpenSearch ❌ 막힘
```

그래서 **모든 Terraform 스택이 문제인 게 아니라, 특정 provider를 쓰는 스택만** 문제가 됩니다.

| 스택이 쓰는 provider | 접속 대상 | GitHub-hosted로 가능? |
| --- | --- | --- |
| `aws` (+ S3 backend) | AWS 공개 API 엔드포인트 | ✅ 가능 |
| `kubernetes`, `helm` | EKS API 서버 — private-only거나 CIDR allowlist인 경우 | ❌ 불가 |
| `mysql`, `postgresql`, `opensearch` | internal ALB·private subnet 안의 엔드포인트 | ❌ 불가 |

**정리: VPC 안에서 실행해야 하는 건 "사설 엔드포인트에 직접 붙는 provider를 쓰는 스택"뿐입니다.**

### ⓞ 현상 유지 — 손댈 필요가 없는 스택 (기준선)

위 표에서 ✅인 스택은 **아무것도 바꾸지 않습니다.** GitHub-hosted 러너로 계속 돌립니다. 이 문서의 ①~⑤는 ❌인 스택**만**을 위한 선택지이므로, 가장 먼저 할 일은 **"우리 스택 중 실제로 ❌가 몇 개인지 세는 것"** 입니다.

이걸 기준선으로 명시하는 이유:

- ❌ 스택이 1~2개뿐이라면 워크플로를 나눠서 그 job만 self-hosted로 보내면 됩니다. 전체 CI를 옮길 필요가 없습니다.
- GitHub-hosted에는 **Docker Hub rate limit 면제**가 걸려 있습니다(§5). 남겨둘 수 있는 job은 남겨두는 게 이득입니다.
- self-hosted 러너는 보안·운영 부담을 만듭니다. 노출 면적을 필요한 만큼만 늘립니다.

```yaml
# 같은 워크플로 안에서 job별로 러너를 다르게 쓰는 예
jobs:
  plan-aws:              # aws provider만 쓰는 스택 → 그대로 GitHub-hosted
    runs-on: ubuntu-latest
  plan-k8s:              # kubernetes/helm provider 스택 → VPC 안 러너
    runs-on: <아래 ①~③에서 고른 러너 라벨>
```

---

## 2. 자주 하는 오해 두 가지

### 오해 ①: "`plan`은 읽기만 하니까 괜찮겠지"

아닙니다. Terraform은 `plan` 단계에서 **현재 실제 상태를 확인(refresh)** 합니다. 즉 `kubernetes` provider가 있으면 `plan`도 EKS API에 접속을 시도하고, **`plan`부터 실패합니다.** PR에서 diff를 보여주는 것조차 안 된다는 뜻입니다.

### 오해 ②: "네트워크만 뚫으면 되겠지"

네트워크는 **필요조건일 뿐**입니다. EKS는 여기에 두 단계가 더 있습니다.

1. **인증** — `aws` CLI로 토큰을 받아오는 exec auth 설정 필요
2. **인가** — 그 IAM 주체가 클러스터 안에서 무엇을 할 수 있는지 등록 (**EKS access entry** 또는 구방식 `aws-auth` ConfigMap)

이게 빠지면 네트워크가 뚫려 있어도 **401 Unauthorized**로 끝납니다. 러너를 어디에 두든 이 작업은 별도로 해야 합니다.

---

## 3. 해결 방법 5가지 (❌ 스택을 어떻게 처리할까)

각 방안이 **어떤 러너를 쓰는지**를 먼저 봐두면 이해가 빠릅니다.

| | 러너 종류 |
| --- | --- |
| ① EC2 상주 / ② CodeBuild / ③ ARC | **self-hosted** — 러너를 우리가 VPC 안에 준비 |
| ④ VPN 터널 / ⑤ 엔드포인트 공개 | **GitHub-hosted 유지** — 러너는 GitHub 것을 그대로 쓰고, 경로나 엔드포인트를 바꿈 |

②는 헷갈리기 쉽습니다. AWS가 실행 환경을 관리해주더라도 **GitHub 입장에서는 self-hosted 러너**로 등록됩니다(→ §5의 Docker Hub 면제 대상이 아님).

### ① VPC 안에 EC2 러너를 상주시킨다

**어떻게 동작하나**
VPC 안에 EC2 한 대를 띄우고, 그 안에 GitHub Actions runner 프로그램을 설치해 우리 저장소에 등록합니다. 그 뒤로 GitHub은 job을 **그 컴퓨터에게** 보내고, 그 컴퓨터는 이미 VPC 안에 있으니 사설 엔드포인트에 그냥 접속됩니다.

**좋은 점**

- **가장 단순합니다.** 새로 배울 개념이 거의 없습니다.
- public subnet에 두고 **EIP**(고정 공용 IP)를 붙이면 NAT gateway 없이도 인터넷으로 나갈 수 있습니다 → NAT 비용 절약.

**주의할 점**

- **러너를 어느 VPC에 두는지가 닿을 수 있는 범위를 결정합니다.** VPC peering은 *transitive(전이적)* 하지 않습니다 — A-B가 연결되고 B-C가 연결돼도 A는 C에 못 닿습니다. 여러 VPC를 건드려야 하면 **허브 역할 VPC**에 두어야 합니다.
- **상주하는 관리자 권한 박스가 하나 생깁니다.** GitHub 공식 경고: *"Self-hosted runners for GitHub do not have guarantees around running in ephemeral clean virtual machines, and can be persistently compromised by untrusted code in a workflow."* (한 번 오염되면 계속 오염된 채 남는다는 뜻)
- **동시 처리량 제약** ✏️*(원본 문서 표현 정정)*
  - GitHub은 **러너 하나에 job 하나**만 배정합니다. 다만 이건 *러너 프로세스 단위*이지 *EC2 한 대 단위*가 아닙니다. 한 대에 러너를 여러 개 등록하면 병렬 실행은 가능합니다.
  - 단, GitHub은 상주(persistent) 러너를 늘리는 방식보다 **일회용(ephemeral) 러너 + 오토스케일**을 권장합니다.
  - job이 배정된 뒤 **60초 안에 러너가 집어가지 않으면** 다른 러너로 재배정됩니다.
  - job이 큐에서 **24시간**을 넘기면 취소/실패 처리됩니다.
- OS 패치, 디스크 정리 같은 운영 부담이 생깁니다.

**위험 완화책**

- 러너를 `--ephemeral`로 등록해 job 1개 처리 후 스스로 해제되게 하기
- 인바운드 보안그룹 규칙을 아예 열지 않고 접속은 **SSM Session Manager**로만
- `plan`은 read-only 역할, `apply`만 관리자 역할로 분리

---

### ② CodeBuild가 만들어주는 일회용 GHA 러너 (VPC 연결)

**어떻게 동작하나**

```text
1. GitHub: "job이 큐에 들어갔다" 웹훅 발송 (WORKFLOW_JOB_QUEUED)
2. CodeBuild: 빌드 1개를 띄워 일회용 GitHub Actions 러너를 실행
3. 그 러너가 job 1개를 처리
4. 끝나는 즉시 러너와 빌드 프로세스가 종료됨 (상주 없음)
```

AWS 공식 문서 원문: *"For each job in the workflow, CodeBuild starts a build to run an ephemeral GitHub Actions runner… Once the job is completed, the runner and the associated build process will be immediately terminated."*

워크플로에서는 `runs-on`만 이렇게 바꿉니다.

```yaml
runs-on: codebuild-<project>-${{ github.run_id }}-${{ github.run_attempt }}
```

웹훅은 이렇게 걸어둡니다.

```hcl
resource "aws_codebuild_webhook" "runner" {
  project_name = aws_codebuild_project.runner.name
  build_type   = "BUILD"
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }
  }
}
```

**좋은 점**

- **상주 인스턴스가 없습니다.** 유휴 비용 0, OS 관리 불필요, 매 job이 깨끗한 환경.
- 라벨로 image·instance-size·fleet을 job마다 덮어쓸 수 있어, matrix job이 서로 다른 스펙을 쓸 수 있습니다.

**주의할 점**

- **compute type은 EC2로 고정해야 합니다.** ✏️*(정정: 근거 보강)* CodeBuild의 Lambda compute는 **VPC 연결뿐 아니라 Docker 빌드/실행, privileged mode, 캐싱, 15분 초과 실행도 미지원**입니다.
- **NAT gateway가 사실상 필수입니다.** ✏️*(정정)* CodeBuild는 자신이 만드는 네트워크 인터페이스(ENI)에 공용 IP를 붙일 수 없어서, AWS 문서가 *"internet gateway로 NAT를 대체할 수 없다"* 고 명시합니다. 러너는 GitHub·액션 다운로드 등 퍼블릭 엔드포인트를 반드시 타므로 **private subnet + NAT** 구성이 필요합니다.
  - VPC endpoint(PrivateLink)는 NAT의 대체재가 아니라 **AWS 서비스 트래픽만 사설 경로로 우회**시키는 보조 수단입니다.
- **동시 빌드 쿼터를 미리 올려둬야 합니다.** ✏️*(정정)* "쿼터까지 자동 확장"은 맞지만, 기본값이 리전·compute type별로 **1**입니다(일부 플랫폼 20, Linux/2XLarge·GPU는 0). 전부 조정 요청 가능하지만 **사전에 증설 신청**이 필요합니다.
- 앱 빌드용 CodeBuild와 **같은 동시 빌드 쿼터를 공유**합니다.
- **shared VPC(공유 VPC)에는 CodeBuild VPC 연결이 지원되지 않습니다.** ✏️*(추가)*
- buildspec은 기본적으로 **무시**됩니다. 필요하면 라벨에 `buildspec-override:true`를 붙여야 하며, 이때 `BUILD` phase에는 명령을 넣을 수 없고 소스 다운로드도 제한됩니다.

**준비물**: runner용 CodeBuild 프로젝트 생성 + 웹훅 설정 (buildspec은 override를 쓸 때만 작성)

#### 왜 "VPC에 연결하지 않은 CodeBuild"는 후보가 아닌가

CodeBuild는 기본값이 **VPC 미연결**입니다. 이때는 AWS 관리 네트워크에서 인터넷을 통해 나가므로, **우리 private 엔드포인트에는 GitHub-hosted 러너와 똑같이 도달하지 못합니다.** 즉 이 문제를 전혀 풀지 못합니다.

거기에 더해 **ⓞ(GitHub-hosted 유지)보다 순수하게 불리합니다.**

| | ⓞ GitHub-hosted | VPC 미연결 CodeBuild |
| --- | --- | --- |
| private 엔드포인트 도달 | ❌ | ❌ (동일) |
| Docker Hub rate limit 면제 | **유지** | **이탈** (GitHub 입장에선 self-hosted) |
| 운영 부담 | 없음 | 프로젝트·웹훅 관리 |
| 비용 | GHA 사용량 | GHA 사용량 + CodeBuild 빌드 시간 |
| AWS 자격증명 | OIDC로 역할 assume | IAM 역할 직접 (차이 없음) |

**"고정 egress IP를 얻으려고" 붙이는 것도 VPC 미연결로는 목적을 못 이룹니다.** VPC 미연결 CodeBuild의 출발 IP는 AWS가 [ip-ranges.json](https://ip-ranges.amazonaws.com/ip-ranges.json)의 `CODEBUILD` 서비스로 공개하는 대역이고, `ap-northeast-2`는 `13.124.145.16/29`, `3.38.90.8/29`(총 16개 주소)로 GHA meta 대역보다 훨씬 좁긴 합니다. 하지만 이건 **같은 리전의 모든 AWS 고객 CodeBuild가 공유하는 멀티테넌트 대역**이므로, allowlist에 넣으면 ⑤-a와 똑같은 문제(남의 빌드도 들어올 수 있음)가 남습니다.

> **반대로 ②처럼 VPC에 연결하면** egress가 우리 NAT gateway의 **EIP 하나**로 고정됩니다. 이건 우리만 쓰는 단일 테넌트 IP이므로, EKS API를 public+allowlist로 운영해야 하는 상황에서는 **⑤-b(Team 플랜 불가)의 실질적 대안**이 됩니다. VPC 연결의 가치가 "private 도달"만이 아니라는 뜻입니다.

**결론: VPC 미연결 CodeBuild는 "문제를 못 푸는데 ⓞ의 장점만 잃는" 조합이라 제외합니다.**

---

### ③ ARC (Actions Runner Controller) on EKS

**어떻게 동작하나**
EKS 클러스터 안에 컨트롤러를 설치하면, job이 큐에 쌓일 때마다 **Pod로 일회용 러너를 띄우고 끝나면 없애는** 방식으로 자동 확장합니다. GitHub 공식 문서는 ARC를 *"the recommended Kubernetes-based solution for autoscaling self-hosted runners"* 로 표현합니다. ✏️*(정정: 이 문구는 ARC 개념 페이지가 아니라 [Self-hosted runners reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners) 페이지에 있습니다.)*

**좋은 점**

- 동시성 확장과 러너 정리(cleanup)가 가장 깔끔합니다. CI 물량이 많을 때 유리.

**주의할 점**

- **순환 의존(circular dependency)에 주의.** Terraform이 관리하는 클러스터 안에 러너가 살면, 그 클러스터가 망가졌을 때 고치러 갈 러너도 같이 사라집니다. 별도 클러스터를 두거나 비상용 부트스트랩 경로를 확보해야 합니다.
- ARC 자체 운영 부담(컨트롤러 업그레이드, GitHub App 자격증명 관리)이 생깁니다.
- 이미 EKS 운영이 익숙한 팀에서만 이득이 남습니다.

---

### ④ VPN / Tailscale 터널로 GitHub-hosted 유지

**어떻게 동작하나**
GitHub-hosted 러너가 job 시작 시점에 우리 VPN 네트워크(예: tailnet)에 **임시 노드로 참가**해서 사설 IP에 접근합니다. 러너는 계속 GitHub 것을 씁니다.

**좋은 점**

- VPC 안에 러너를 만들지 않아도 됩니다.

**주의할 점**

- 외부 SaaS 의존과 ACL 관리 업무가 새로 생깁니다. 이미 자체 VPN이 있으면 중복 투자.
- 결국 VPC 쪽에 **subnet router 한 대는 상주**해야 하므로 "상주 0"은 아닙니다.

---

### ⑤ 엔드포인트를 공개하고 IP allowlist — 비권장

러너를 옮기는 대신 **접속 대상 쪽을 인터넷에 열고, 들어오는 IP만 제한**하는 방식입니다. 두 갈래가 있습니다.

#### ⑤-a. GitHub Actions 전체 IP 대역을 allowlist — 선택하지 않습니다

EKS API를 public으로 열고 GitHub이 [meta API](https://api.github.com/meta)로 공개하는 Actions IP 대역을 허용합니다.

- 대역이 **매우 넓고 수시로 바뀝니다** → 실질적으로 **전 세계 GHA 사용자에게 여는 것과 비슷**해집니다. 남의 저장소 워크플로도 그 대역에서 나옵니다.
- 대역이 바뀔 때마다 allowlist를 갱신해야 합니다.
- internal ALB에는 아예 적용할 수도 없습니다.

#### ⑤-b. larger runner에 고정 IP를 받아 allowlist — **우리 플랜에서는 불가**

GitHub-hosted **larger runner**에 GitHub IP 풀에서 고정 IP 대역을 할당받아, 그 좁은 대역만 여는 방법입니다. ⑤-a의 "너무 넓다"는 약점은 해결됩니다.

> **결론: 현재 우리는 GitHub Team 플랜이라 사용할 수 없습니다.** 이 기능은 **GitHub Enterprise Cloud 전용**입니다. 아래는 나중에 플랜이 올라갈 경우를 위한 기록입니다.

- 고정 IP 대역을 쓰는 러너 풀은 **총 10개까지**, 초과 시 GitHub Support 문의
- **90일간 미사용이면 IP 대역이 자동 회수되며 복구 불가** → 자주 안 쓰는 파이프라인에는 부적합
- macOS larger runner는 고정 IP·Azure private networking 미지원
- 플랜이 올라가더라도 **엔드포인트가 public이어야 한다**는 전제는 그대로입니다. EKS API를 public+allowlist로 운영하는 경우에만 유효하고, **internal ALB나 private subnet의 MySQL·OpenSearch에는 무효**입니다.

**따라서 ⑤는 현재 후보에서 제외합니다.**

---

## 4. 한눈에 비교

| | ⓞ 현상 유지 | ① EC2 상주 | ② CodeBuild 러너 | ③ ARC on EKS | ④ VPN 터널 | ⑤ 엔드포인트 공개 |
| --- | --- | --- | --- | --- | --- | --- |
| 러너 | GitHub-hosted | self-hosted | self-hosted | self-hosted | GitHub-hosted | GitHub-hosted |
| 적용 대상 | **사설 엔드포인트 안 쓰는 스택** | ❌ 스택 | ❌ 스택 | ❌ 스택 | ❌ 스택 | EKS API public인 경우만 |
| 도입 난이도 | 없음 | 가장 낮음 | 낮음~중간 | 높음 | 중간 | 낮음 |
| 상주 리소스 | 없음 | EC2 1대 | 없음 | EKS 컨트롤러 | subnet router | 없음 |
| 유휴 비용 | 0 | 있음 | 0 | 있음 | 있음 | 0 |
| 동시 실행 | GitHub 기본 | 러너 수만큼 | 쿼터까지(증설 필요) | 가장 유연 | GitHub 기본 | GitHub 기본 |
| NAT 필요 | 불필요 | 불필요(public+EIP) | **필요** | 클러스터 구성에 따름 | 불필요 | 불필요 |
| 보안 리스크 | 가장 낮음 | 상주 admin 박스 | 낮음 | 중간 | ACL 관리 | **높음** |
| OS 운영 | 없음 | 필요 | 불필요 | 컨트롤러 운영 | router 운영 | 없음 |
| Docker Hub 면제(§5) | **유지** | 이탈 | 이탈 | 이탈 | 유지 | 유지 |
| 현재 채택 가능? | ✅ | ✅ | ✅ | ✅ | ✅ | ⑤-a 비권장 / ⑤-b **불가**(Team) |

---

## 5. 문제 1(Docker Hub rate limit)과 이어지는 지점

self-hosted 계열(①②③)로 가면 **문제 1이 새로 활성화됩니다.**

```text
VPC 안 self-hosted 러너 도입
  → GitHub-hosted에만 적용되던 "Docker Hub rate limit 면제"에서 이탈
  → 러너의 외부 통신이 VPC NAT의 단일 공용 IP로 나감
  → 같은 NAT를 쓰는 EKS 노드 등과 "미인증 100 pulls / 6시간" 버킷을 공유
  → 문제 1의 ③(ECR Pull-Through Cache)을 먼저 해두면 원천 차단
```

지금 당장은 급하지 않습니다. **Terraform CI만 돌리는 러너는 컨테이너 이미지를 당기지 않으므로 pull이 0**입니다. 다만 **lint/test/보안스캔용 Docker 기반 액션(tflint, checkov 등)을 붙이는 순간 시작됩니다.**

---

## 6. 결론

- **먼저 ⓞ로 최대한 남깁니다.** ❌ 스택만 골라내 그 job만 옮깁니다. 전체 CI를 옮기지 않습니다.
- **상주를 감수하고 가장 빨리 붙이려면 ①** (EC2 + `--ephemeral` + SSM 전용 + 역할 분리)
- **상주 없이 가려면 ②** — 단 **NAT 구성**과 **동시 빌드 쿼터 증설**이 선행 조건
- **이미 EKS 운영이 익숙하고 CI 물량이 많으면 ③**
- **VPC에 아무것도 만들고 싶지 않으면 ④**
- **⑤는 제외합니다.** ⑤-a는 보안상 비권장, ⑤-b(고정 IP)는 **Enterprise Cloud 전용이라 현재 Team 플랜에서 불가**

### 어떤 방식을 고르든 반드시 함께 해야 하는 일

1. **EKS access entry(또는 `aws-auth`) 등록** — 없으면 네트워크가 뚫려도 401
2. **`plan` / `apply` 권한 분리** — plan은 read-only 역할로
3. 러너를 둘 **VPC 선택** — peering은 전이되지 않으므로 허브 VPC 기준으로 판단

### 결정 전에 확인할 것

- **VPC에 접근해야 하는 Terraform 스택이 실제로 몇 개인지 (provider 기준)** — ⓞ로 남길 범위를 먼저 확정
- 현재 EKS API 엔드포인트 설정 (private-only / public+allowlist / public)
- NAT gateway가 이미 있는지 (② 선택 시 비용 차이가 여기서 갈립니다)

### 확인된 전제

- **GitHub 플랜: Team** (2026-08-12 기준) → larger runner 고정 IP·Azure private networking 등 **Enterprise Cloud 전용 기능은 사용 불가**

---

## 출처

**GitHub**

- [Actions limits](https://docs.github.com/en/actions/reference/limits) — 큐 24시간 초과 시 자동 취소
- [Self-hosted runners reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners) — ARC를 "recommended Kubernetes-based solution"으로 표현
- [Actions Runner Controller](https://docs.github.com/en/actions/concepts/runners/actions-runner-controller) — ARC 개념
- [Autoscaling with self-hosted runners](https://docs.github.com/en/enterprise-cloud@latest/actions/hosting-your-own-runners/managing-self-hosted-runners/autoscaling-with-self-hosted-runners) — 러너당 job 1개, ephemeral 권장, 60초 미픽업 시 재큐
- [Security hardening for GitHub Actions](https://docs.github.com/en/actions/reference/security/secure-use) — self-hosted 러너 오염 경고
- [Larger runners](https://docs.github.com/en/actions/reference/runners/larger-runners) — 고정 IP는 Enterprise Cloud 전용, 풀 10개 제한, 90일 미사용 시 회수
- [GitHub meta API](https://api.github.com/meta) — Actions IP 대역 (⑤-a)

**AWS**

- [CodeBuild-hosted GitHub Actions runner](https://docs.aws.amazon.com/codebuild/latest/userguide/action-runner.html) — 일회용 러너 동작, 라벨 문법, buildspec override
- [Use CodeBuild with Amazon VPC](https://docs.aws.amazon.com/codebuild/latest/userguide/vpc-support.html) — NAT 필수, IGW 대체 불가, shared VPC 미지원
- [Run builds on AWS Lambda compute](https://docs.aws.amazon.com/codebuild/latest/userguide/lambda.html) — VPC·Docker·privileged·캐싱 미지원
- [CodeBuild quotas](https://docs.aws.amazon.com/codebuild/latest/userguide/limits.html) — 동시 빌드 기본값과 조정 가능 여부
