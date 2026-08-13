# ADR-0002: CI 제어 평면을 GitHub Actions로 일원화한다

| | |
|---|---|
| 상태 | 제안됨 — 합의 대기 |
| 작성일 | 2026-08-12 |
| 작성자 | alan |
| 결정자 | *(합의 후 기재)* |
| 발단 | 슬랙 `[CI 툴 선택의 시간]` 스레드 (2026-08-11 16:01, Vince) — 팀 의견 수렴 후 결론·Action Item 요청 |
| 관계 | [ADR-0001](ADR001-supplies.md) **개정** (§6) · platform-iac PR #103 / #108 **수용** (§4) |

---

## 요약

세 줄로 줄이면 이렇다.

1. **"GHA를 도입할 것인가"는 이미 지난 질문이다.** 저장소 72개 중 36개가 이미 GHA를 쓰고 최근 7일에만 395번 돌았다. 실제 질문은 **CodeBuild를 실행 계층에서도 걷어낼 것인가**이고, 답은 "대부분 그렇다, 단 잔여분이 있다"이다.
2. **미결 2건은 둘 다 답이 나왔다.** VPC 내부 Terraform은 PR #103이 이미 풀었고 독립 실측으로 설계가 검증됐다. Docker Hub rate limit은 **지금이 아니라 이관하는 순간** 위험해진다 — 현재 19개 중 17개가 인증 pull인데 그 인증을 GHA로 안 들고 가면 익명 공유 IP로 떨어진다.
3. **진짜 병목은 아무도 말하지 않은 곳에 있다.** Team 플랜 포함분 3,000분/월 중 7월에 2,621분(87%)을 썼고, `platform-iac`의 `main`에는 브랜치 보호가 하나도 없는데 PR #103은 main 머지 시 자동 apply를 붙인다.

---

## 1. 배경

### 스레드 경위

Vince가 2026-08-11 16:01에 스레드를 열고 퇴근 전 의견 정리를 요청했다. 결과는 **만장일치 GitHub Actions**.

| 의견자 | 시각 | 근거 |
|---|---|---|
| Austin | 17:18 | CodeBuild는 AWS 리소스 생성 수고 · 플랜별 동시 잡 60이면 충분 · 빌드 캐시 설정 간편 |
| Connor | 17:47 | 파일 간 include/import 문법 · Marketplace 생태계 · migration 불필요 |
| Alan | 17:51 | 위 전부 동의 + OIDC로 access_key→role 전환 시 보안 문제 동시 해소, 비용 낮음 |

이후 Vince가 검토 항목 2건을 추가했고(17:55), 8/12 11:09에 결론과 Action Item을 요청했다.

### 이 문서를 쓰기 전에 알아야 할 사실

**스레드가 열리기 1시간 7분 전에 이미 설계가 올라와 있었다.** platform-iac PR #103(`feat(ci): Terraform CI — bastion-vpc self-hosted EC2 러너 + GitHub Actions`)은 2026-08-11 14:54 KST 생성, +591/-0. 스레드는 그 설계에 대한 팀 합의를 받는 자리였다.

따라서 이 문서는 **경쟁 설계를 제안하지 않는다.** PR #103을 독립 검증하고, 그것이 답하지 않는 범위(앱 CI 이관, Docker Hub, 비용, ADR-0001 정합성)를 채운다.

---

## 2. 실측이 뒤집은 전제 5가지

### 2-1. GHA는 도입 대상이 아니라 이미 절반이다

| 항목 | 실측값 |
|---|---|
| 조직 저장소 | 72개 (private 71 / public 1) |
| **워크플로 보유 저장소** | **36개 — 정확히 절반** |
| 워크플로 파일 | 51개 |
| 최근 7일 실행 | 395건 (22개 저장소) |
| self-hosted 러너 | 0개 — 전부 GitHub-hosted<sup>†</sup> |

<sup>†</sup> 조직 레벨 조회는 `admin:org` 스코프가 없어 403. 주요 7개 저장소(`platform-iac`, `platform-gitops`, `preppers-order-server`, `supplies-desktops`, `preppers-kds-server`, `bible`, `supplies-apps`) 레벨에서 전부 `total_count: 0` 확인.

특히 **16개 저장소는 이미 GHA가 진입점**이고, CodeBuild를 `aws-actions/aws-codebuild-run-build`로 호출만 하고 있다. 예를 들어 `preppers-server/.github/workflows/deploy.yml`은 모노레포 변경 감지(`detect-changes` job)까지 GHA에서 하고 마지막에 CodeBuild를 부른다.

```yaml
# preppers-server/.github/workflows/deploy.yml (발췌)
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}      # ← 장기 키
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      - uses: aws-actions/aws-codebuild-run-build@v1.0.3
        with:
          project-name: preppers-kds-server-dev
```

**이관 작업의 실체는 "GHA 도입"이 아니라 "이 마지막 step을 buildspec 내용으로 치환하는 것"이다.** 난이도가 완전히 다르다.

> 부수 효과: 위 발췌의 `secrets.AWS_ACCESS_KEY_ID`는 장기 자격증명이다. 스레드에서 내가 말한 "access_key를 role로 바꾸면 보안 문제도 해결"은 **가정이 아니라 지금 있는 부채**를 가리킨다.

### 2-2. e2e 테스트의 GHA 실행 가능성은 이미 실증됐다

Connor가 난이도로 꼽은 "action preppers CI 테스트코드 옮기기"는 **이미 끝나 있다.**

`preppers-server/.github/workflows/test.yml`이 `mysql:8.0` 서비스 컨테이너를 띄우고 `apps/kds`의 unit + e2e를 돌린 뒤 Codecov에 올린다. `preppers-order-server`는 `mysql:8.0` + `amazon/dynamodb-local` 2개를 띄운다. 테스트 코드가 RDS 호스트를 하드코딩하지 않고 `DB_ENDPOINT` 환경변수를 읽으며(`apps/kds/test/support/create-test-app.ts`), TypeORM `synchronize: true`로 빈 DB에 스키마를 만들기 때문에 덤프도 필요 없다.

**"GHA에서 DB 테스트가 되는가"는 미해결 리스크가 아니다. 해결된 선례다.**

### 2-3. VPC 연결 — 내 슬랙 발언을 정정한다

내가 8/11 18:01에 "VPC는 연결은 실제 사용 안 하는 것으로 보입니다. 빌드상 필요 없습니다"라고 답했다. 정확히 하면 이렇다.

| | 실측 |
|---|---|
| CodeBuild 프로젝트 | **91개** |
| 그중 VPC 연결 설정 보유 | **57개 (63%)** |
| Terraform으로 관리되는 것 | **3개** (`stacks/codebuild/dev`) — 나머지 88개는 IaC 밖 |

**"설정이 없다"가 아니라 "설정은 있으나 무효"다.** 무효인 근거:

- VPC 연결의 용도는 유형 B(=`kubectl apply`) 7개 저장소의 EKS API 접근이다.
- 그런데 `eks_dev` / `eks_prod` / `preppers-cluster` 세 클러스터는 **`endpointPrivateAccess: false`** 다. 사설 경로 자체가 꺼져 있어서 VPC 안에 있어도 EKS API는 공개 엔드포인트로만 닿는다.
- 실제로 `preppers-auth-api-prod`에는 preppers-cluster의 cluster SG(`sg-093743349e63fb6d2`)가 붙어 있는데, private access가 꺼져 있으므로 이 SG 소속은 EKS API 접근에 아무 역할도 하지 않는다.

즉 **결론(빌드상 불필요)은 맞지만, 근거(설정이 없다)는 틀렸다.** 57개에 남아 있는 VPC 설정은 잔재이고, 걷어낼 때는 프로젝트별 확인이 필요하다.

> NAT 비용 각도는 실측 후 기각한다. 러너가 놓일 `supplies-eks-dev-vpc`의 NAT는 14일간 인바운드 15.5 GB로, 데이터 처리 요금이 유의미하지 않다.
> 다만 **`eks-vpc`의 NAT는 14일간 인바운드 8,073 GB**로 자릿수가 다르다. CI와 무관한 애플리케이션 트래픽이지만 별건으로 볼 값어치가 있다.

### 2-4. VPC 내부가 필요한 Terraform 스택은 4개 VPC에 흩어져 있다

`platform-iac` 스택 43개를 전수 분류했다.

| 분류 | 개수 | 내용 |
|---|---|---|
| GitHub-hosted로 충분 | **37개** | `aws` provider만. `vpcs/*`, `iam/*`, `rds/*`, `ecr/*`, `codebuild/*`, `entry/*`, `hris/*`, `eks/*/cluster` |
| **VPC 내부 필수** | **5개** | `eks/{eks_dev,eks_prod,preppers-cluster,supplies-eks-dev}/k8s` (opensearch) + `eks/dev-eks/k8s` |

`opensearch` provider가 걸림돌인 이유는 IAM으로 우회가 안 되기 때문이다. `sign_aws_requests = false`로 basic auth를 쓰므로 **네트워크 도달성이 유일한 게이트**다.

그리고 이 4개가 서로 다른 VPC에 있다.

| OpenSearch 내부 ALB | 소속 VPC | CIDR |
|---|---|---|
| `dev-pp-logs-api.supp.fitness` | supplies-eks-dev-vpc | 10.8.0.0/16 |
| `prod-pp-logs-api.supp.fitness` | db-vpc | 172.31.0.0/16 |
| `dev-gbx-logs-api` / `prod-gbx-logs-api` | eks-vpc | 172.16.0.0/16 |
| (dev-eks 사설 엔드포인트) | dev-vpc | 10.20.0.0/16 |

피어링은 bastion-vpc를 허브로 한 스타 구조이고 **전이되지 않는다**. 라우트 테이블을 직접 확인한 결과:

- `bastion-rtb-public`에 스포크 4개 경로가 전부 있다 — `172.16`(pcx-06a3c6a4ddd7192b4) · `172.31`(pcx-0b316c29a986a622c) · `10.8`(pcx-0de018668f9de449b) · `10.20`(pcx-02297daafb56502c8)
- 역방향도 확인했다. OpenSearch ALB가 놓인 서브넷의 라우트 테이블 **전부**에 `10.0.0.0/16` 경로가 있다.
- OpenSearch ALB의 SG는 **4개 전부 `443 from 0.0.0.0/0`** 이다 → SG 변경 불필요.
- DNS는 public zone `supp.fitness`의 CNAME이라 **어디서든 해석된다**. `dig dev-pp-logs-api.supp.fitness` → `10.8.157.6`. private hosted zone 연결은 필요 없다.

**→ bastion-vpc가 유일한 단일 러너 위치라는 PR #103의 판단은 독립 실측으로 확인된다.**

### 2-5. Docker Hub — GHA 이관이 위험이 아니라 해법이다

> **정정 (2026-08-12 재조사).** 초판은 "이관하는 순간 위험해진다"로 썼으나 **틀렸다.** GitHub 공식 문서가 *"GitHub-hosted runners are not subject to these limits **based on an agreement between GitHub and Docker**"*(public 이미지 한정)를 명시한다. self-hosted 러너와 private 이미지만 한도 적용 대상이다. 상세는 [결론 문서 §2-1](ci-툴-선택-결론.md).

| 항목 | 실측 |
|---|---|
| Dockerfile | 19개 |
| 베이스 이미지 출처 | **Docker Hub 100%** (`node:22-alpine` 16회, `node:24-alpine` 4회 등). ECR/미러 **0건** |
| `docker build` 하는 buildspec | 19개 |
| 그중 `docker login -u gymboxx`로 **인증** pull | **17개** |
| 미인증 | **2개** — `slack-bot/buildspec.yml`, `web-socket-server/buildspec.yaml` |

익명 pull만 IP 단위로 세고 인증 pull은 계정 단위로 센다. **17개가 이미 인증하고 있으므로 현재 CodeBuild 경로의 IP 기반 리스크는 낮다.**

문제는 두 곳이다.

1. **이관 시 인증이 유실되면** 익명 + GHA 공유 IP 조합이 되어 지금보다 나빠진다.
2. **GHA 서비스 컨테이너는 이미 미인증이다.** `preppers-server`/`order-server`/`kds-lib`의 test 워크플로가 `mysql:8.0`, `amazon/dynamodb-local`을 인증 없이 당긴다. `preppers-order-server`는 누적 1,327런이다.

즉 Vince의 우려는 타당하되 **대상이 CodeBuild가 아니라 GHA 쪽**이다.

---

## 3. 결정

### D1. CI 제어 평면은 GitHub Actions로 단일화한다

팀 만장일치 + §2-1의 실태(이미 절반). 트리거·오케스트레이션·게이트는 전부 GHA가 소유한다.

### D2. CodeBuild는 폐기가 아니라 축소한다

"CodeBuild vs GHA"는 잘못된 이분법이다. 실행 컴퓨트는 별개 축이다.

| 대상 | 실행 주체 | 근거 |
|---|---|---|
| Terraform 스택 37개 | GHA (self-hosted EC2 러너) | PR #103 |
| Terraform 스택 5개 (VPC 필수) | 동일 러너 (bastion-vpc) | §2-4 |
| 앱 빌드 유형 A·C·D (23 buildspec) | GHA (GitHub-hosted) | VPC 불필요 |
| 앱 빌드 유형 B (7 buildspec) | **당분간 CodeBuild 잔존** | §5-2 |

### D3. Terraform CI는 PR #103 설계를 채택한다 — 단 선행 조건 2개는 협상 불가

PR #103의 self-hosted EC2(`t4g.small`, bastion-vpc) 선택을 지지한다. CodeBuild-hosted 러너를 기각한 근거("VPC ENI가 공인 IP를 못 받는데 bastion-vpc에 NAT이 없어 월 $43 신설 필요")는 실측·공식 문서 양쪽과 일치한다 — bastion-vpc의 NAT Gateway는 **0개**이고 유일한 서브넷은 `0.0.0.0/0 → IGW`에 `MapPublicIpOnLaunch: false`이며, AWS 문서가 이를 명시적으로 막는다.

> *"You need a NAT gateway or NAT instance to use CodeBuild with your VPC... **You cannot use the internet gateway instead of a NAT gateway**."* — [CodeBuild VPC 지원](https://docs.aws.amazon.com/codebuild/latest/userguide/vpc-support.html)

**공정을 기하기 위해 기록한다 — CodeBuild-hosted 러너 자체는 성립했다.** platform-iac 선행 문서가 미검증으로 남긴 "CODECONNECTIONS가 러너 프로젝트에 쓰이는지"는 **공식 지원**으로 확인됐고(GitHub App connection은 AWS CodeConnections 경유, 서울 리전 엔드포인트 존재), `WORKFLOW_JOB_QUEUED` Terraform 예시도 공식 문서에 있다. 즉 두 안 다 실현 가능했고 **NAT 신설 비용이 갈랐다.**

다만 서울 리전에는 CodeBuild의 콜드스타트 완화 수단이 없다는 점도 같이 기록한다 — **Lambda compute와 Reserved capacity fleet 둘 다 `ap-northeast-2` 미지원**이다(도쿄는 지원). 향후 CodeBuild 러너를 재검토하더라도 이 제약은 유지된다.

| CodeBuild 서울 리전 요금 (Linux on-demand) | 분당 |
|---|---|
| `general1.small` | $0.005 |
| `arm1.small` | $0.00385 |
| `general1.medium` | $0.010 |

**선행 조건** (PR #103 본문에도 "선택이 아니다"로 명시됨):

1. `platform-iac`의 `main`에 branch protection — plan 체크 필수화
2. GitHub Environment `dev` 생성 + **required reviewers 지정**

이게 협상 불가인 이유: 현재 `main`에 **보호 규칙도 룰셋도 0개**이고, 최근 머지 15건이 **전부 리뷰 0건**이다. 여기에 main 머지 자동 apply를 붙이면 **리뷰 없는 셀프 머지가 곧바로 인프라 apply가 된다.** 러너 롤은 day-1 타협으로 `AdministratorAccess`다.

### D4. Docker Hub는 ECR Public으로 옮긴다 — Pull Through Cache가 아니라

platform-iac 문서(`docs/2026-08-11-gha-vpc-runner-dockerhub-rate-limit.md`)는 ECR Pull Through Cache를 1차 해법으로 잡았다. **PR #108이 채택한 ECR Public이 더 낫다.**

```dockerfile
# Before
FROM node:22-alpine
# After (PR #108 선례)
FROM public.ecr.aws/docker/library/node:22-alpine
```

| | ECR Public | Pull Through Cache |
|---|---|---|
| Secrets Manager 크리덴셜 | 불필요 | 필요 (`ecr-pullthroughcache/` 접두사 규칙) |
| 신규 Terraform 스택 | 불필요 | 필요 |
| Docker Hub 유료 계정 | 불필요 | 사실상 필요 |
| tag immutability 함정 | 없음 | 있음 (IMMUTABLE이면 캐시 갱신 불가) |
| 적용 단위 | Dockerfile 1줄 | 레지스트리 + 저장소 템플릿 + 사용처 전부 |

PTC는 사설 ECR 캐시가 필요할 때(예: private 이미지, 대역폭 최적화) 유효하다. 우리가 쓰는 건 `node`, `golang`, `alpine`, `mysql` 같은 **전부 공개 공식 이미지**라 ECR Public 미러로 충분하다.

**단, GHA 서비스 컨테이너(`services.mysql.image`)에도 같이 적용해야 한다** — §2-5의 진짜 노출 지점이다.

**긴급도 판정: 낮음.** Docker는 2025-04-01 시행 예정이던 강화안(익명 10/hr, Personal 100/hr)을 **철회**했고, pull 종량 과금도 전면 취소했으며 **"향후 시행은 최소 6개월 전에 공지한다"**고 약속했다.
→ 별도 과제로 만들 일이 아니라 **이관 작업에 끼워서 처리**하면 된다.

**적용 범위 정정**: ECR Public은 **AWS 안에서 도는 빌드에만** 이점이 있다. Docker 공식 블로그가 *"you should generally use the Docker Hub addresses if you are pulling from outside AWS"*라고 못박는다 — ECR Public 익명 한도는 1 pull/sec + 500GB/월이고, GitHub-hosted에서는 Docker Hub 면제를 버리는 셈이 되기 때문이다.

**알 수 없는 것 2가지** (설계 전제로 쓰지 말 것): ① 6시간 윈도가 롤링인지 고정 리셋인지 Docker가 문서화한 적이 없고 `ratelimit-reset` 헤더도 없다. ② `docs.docker.com`(100/6h) · `docker.com/pricing`(100/hr, 철회된 정책 잔재) · **실서버 헤더(`100;w=3600`)** 가 서로 다르다. 숫자는 문서가 아니라 실측으로 확인한다.

### D5. ADR-0001은 개정한다 (§6)

---

## 4. 진행 중인 작업 — 이 결정과의 정합성

| PR | 내용 | 상태 | 판단 |
|---|---|---|---|
| platform-iac **#103** | Terraform CI — bastion-vpc EC2 러너 + GHA | OPEN, +591/-0 | **D3로 채택.** 선행 조건 2개 확인 후 머지 |
| platform-iac **#108** | `supplies-auth` ECR push용 GHA OIDC role | OPEN, +115/-0 | **채택.** D4의 ECR Public 선례이기도 함 |
| platform-iac #25 / #51 | #103의 구 설계 | OPEN | #103 머지 후 닫는다 |
| platform-iac #98 | auth 빌드 경로 필터 수정 | OPEN | #108 완료 시 대상 소멸 → 닫기 검토 |

`tech/adr/0009`(CI 실행 평면 단일화)가 PR #108에서 참조되나 **위치를 찾지 못했다.** 이 ADR과의 번호·범위 정합성 확인이 필요하다(→ AI-1).

---

## 5. 앱 CI 이관 범위 — 아무도 정리하지 않은 부분

buildspec 30개 / 28개 저장소를 전수 분류하면 **템플릿은 4종뿐**이다.

| 유형 | 하는 일 | 개수 | 난이도 | 비고 |
|---|---|---|---|---|
| **A** | Docker build → ECR push (배포는 ArgoCD) | 12 | 하 | 그대로 이식 |
| **B** | Docker build → ECR push → **`kubectl apply`** | 7 | **상** | §5-2 |
| **C** | Serverless Framework → Lambda | 6 | 하 | Docker 불필요 |
| **D** | 정적 빌드 → S3 sync | 5 | 하 | |

### 5-1. GHA로 옮기면 오히려 나아지는 것

- **캐시**: CodeBuild 프로젝트가 전부 `NO_CACHE`이고 buildspec에 `cache:` 블록 0건. GHA의 `actions/cache` + buildx 캐시를 붙이면 빌드가 빨라진다. Austin이 꼽은 "빌드 캐시 설정 간편"이 실측으로 뒷받침된다.
- **시크릿**: 이미 전부 Secrets Manager(ARN 3개로 수렴). plaintext 0건. OIDC role에 읽기 권한만 주면 그대로 간다.
- **CodeBuild 고유 기능 의존**: `batch`·`reports`·`artifacts`·Parameter Store·커스텀 이미지 **전부 미사용**. 1:1 대응이 안 되는 건 VPC 배치 하나뿐이다.

### 5-2. 유형 B 7개가 진짜 블로커다

`gymboxx-branch-admin-server` · `gymboxx-headquarter-server` · `gymboxx-trainer-server` · `gymboxx-web` · `preppers-auth-api` · `preppers-orderinfo-batch-go` · `slack-bot`

이들은 `aws eks update-kubeconfig` 후 `kubectl apply`로 직접 배포한다(`gymboxx-web`은 rollout status 확인·좀비 pod 정리까지 약 100줄).

**해법은 러너를 VPC에 넣는 게 아니라 ArgoCD로 넘기는 것이다.** 유형 A 12개가 이미 그 경로로 갔고 buildspec 주석에 "prod 인수 완료(2026-08-03)" 기록이 있다. 유형 B를 마저 넘기면 VPC 요구가 소멸하고, 그때 GHA 이관은 유형 A와 같은 난이도가 된다.

→ **앱 CI 이관의 선행 과제는 GHA 준비가 아니라 ArgoCD 인수 완료다.**

---

## 6. ADR-0001 개정

[ADR-0001](ADR001-supplies.md)(2026-08-10, 제안됨·합의 대기)은 **CodePipeline 제거 + CodeBuild 네이티브 webhook 전환**을 결정했다. 그 대안 비교표에서 `C. GH Actions → start-build`를 이렇게 기각했다.

> **C 기각** — repo마다 워크플로와 자격증명 경로가 필요하다. B는 앱 repo를 건드리지 않는다.
> 단 preppers dev가 C로 돌고 있어 **C의 흡수는 별도 결정으로 남긴다.**

이 ADR이 그 "별도 결정"이다. 개정 내용:

| ADR-0001 항목 | 처리 |
|---|---|
| CodePipeline 삭제 | **유지.** GHA 채택과 무관하게 순이득 |
| CodeBuild webhook 신설 (결정 1) | **폐기.** GHA 워크플로가 트리거를 소유한다 |
| 대안 C 기각 | **번복.** 기각 근거였던 "repo마다 워크플로 필요"가 §2-1로 무력화 — 16개 저장소에 이미 있다 |
| 결정 2·3 (`TARGET_ENV` 이관, `PODS_NUM` 폐기) | **유지.** 이관 경로가 CodeBuild 프로젝트에서 GHA로 바뀔 뿐 |
| 결정 4 (`concurrentBuildLimit: 1`) | **대체.** GHA `concurrency` 그룹으로 |

**실무상 중요한 귀결: ADR-0001의 webhook 전환을 지금 실행하면 헛수고가 된다.** 대상이 GitOps 인수 완료 서비스(=유형 A)인데, 그게 정확히 GHA로 가장 먼저 옮길 대상이다. webhook을 붙였다가 곧 떼게 된다.

---

## 7. 아무도 보지 않은 리스크

### 7-1. Team 플랜 포함분이 87% 소진 상태다

| 월 | 표준 Linux 사용 | 포함분 대비 |
|---|---|---|
| 2026-06 | 2,153분 | 72% |
| **2026-07** | **2,621분** | **87%** |
| 2026-08 (12일차) | 1,241분 | — |

Team 플랜 포함분은 **3,000분/월**. 헤드룸이 379분밖에 없는데 앱 CI를 GHA로 옮기면 CodeBuild가 하던 **하루 ~50건**(최근 2일 100건 실측)이 여기로 들어온다.

완화 요인:
- PR #103이 Terraform CI를 self-hosted로 보내 Actions 분을 **0** 쓴다.
- 현재 실청구액($69.27/7월)은 전부 larger runner(`ubuntu-24-4c`, `windows-2022-x64-8c`)에서 나온다. 표준 Linux는 $0.

그래도 **이관 순서를 정할 때 분 소비를 같이 봐야 한다.** 초과분은 $0.008/분(Linux 2-core)이라 파산할 금액은 아니지만, 예산 승인 없이 넘어가는 건 다른 문제다.

### 7-2. `platform-iac` main에 브랜치 보호가 없다

§D3에서 다뤘다. 요약: 보호 규칙 0개 + 룰셋 0개 + 최근 15머지 리뷰 0건 + 러너 롤 `AdministratorAccess` + main 머지 자동 apply = **리뷰 없는 커밋이 인프라를 바꾼다.**

### 7-3. CodeBuild 88개가 IaC 밖이다

Terraform이 아는 CodeBuild 프로젝트는 3개(`stacks/codebuild/dev`), 실재는 91개. "CodeBuild 자산을 재활용한다"는 논거를 쓸 때 **그 88개가 콘솔 수기 관리라는 사실과 병기해야 한다.** 이관 대상 목록을 만들 때도 IaC가 아니라 계정을 조회해야 한다.

### 7-4. "plan 전용 read-only role"은 생각만큼 깔끔하지 않다

platform-iac 선행 문서 §B-4 #6이 `code-build-service-role`의 광범위한 권한을 문제 삼으며 plan 전용 read-only role 분리를 제안했다. 방향은 옳지만 **두 가지 함정**이 있다.

1. **plan도 state에 쓰기가 필요하다.** 백엔드가 `use_lockfile = true`(S3 네이티브 잠금)이므로 plan이 `.tflock` 오브젝트에 `s3:GetObject` / `PutObject` / `DeleteObject`를 요구한다. "AWS 리소스는 read-only, state는 write"라는 비대칭 정책을 써야 하고, 완전한 read-only는 `-lock=false`를 써야만 가능하다(HashiCorp 비권장 — PR #103의 plan 잡은 실제로 `-lock=false`를 쓴다).
2. **HashiCorp이 분리 자체를 경고한다.**
   > *"Terraform can't automatically detect if the credentials used to create a plan grant access to the same resources used to apply that plan."*

   plan 자격증명과 apply 자격증명이 다르면 **plan에선 안 보이던 실패가 apply에서 터진다.**

→ 권한 축소는 role 분리보다 **OIDC `sub` 조건 또는 GitHub Environment 승인**으로 거는 편이 안전하다. PR #103이 `environment: dev` + required reviewers를 택한 것이 이 관점에서 맞다. 러너 롤의 `AdministratorAccess` 축소는 day-1 타협 목록에 이미 올라 있다.

### 7-5. 조직 계정 위생

- 시트 **10/10 만석** — 신규 합류 시 좌석 구매 선행
- **2FA 미강제** (`two_factor_requirement_enabled: false`)
- `sha_pinning_required: false` — 서드파티 액션 SHA 고정 미강제. Connor가 장점으로 꼽은 "거대한 Marketplace 생태계"의 이면이다.

---

## 8. Action Items

우선순위 순. 담당자는 제안이며 합의 시 확정한다.

| # | 항목 | 제안 담당 | 선행 | 완료 조건 |
|---|---|---|---|---|
| **AI-1** | `tech/adr/0009` 위치 확인 및 이 ADR과 번호·범위 정합 | Vince | — | 두 문서가 서로를 참조하거나 하나로 통합 |
| **AI-2** | `platform-iac` main 브랜치 보호 + Environment `dev` required reviewers | Vince | — | PR #103 머지 **전** 완료 |
| **AI-3** | PR #103 리뷰·머지 후 활성화 절차 6단계 수행 | Vince | AI-2 | `iac-runner` idle 확인 + 첫 plan 코멘트 |
| **AI-4** | PR #108 apply → `supplies-auth` 워크플로 머지 → `verify`를 required check로 | Alan | — | GHA 빌드 1회 성공 후 `dev-auth-api` 블록 제거(별도 PR) |
| **AI-5** | 미인증 Docker Hub pull 2건에 인증 또는 ECR Public 적용 | Austin | — | `slack-bot`, `web-socket-server` |
| **AI-6** | GHA 서비스 컨테이너 이미지를 ECR Public으로 전환 | Austin | — | `mysql:8.0`, `amazon/dynamodb-local` 사용 워크플로 전부 |
| **AI-7** | 앱 CI 이관 순서 확정 — 유형 A·C·D 23개 | Connor | — | 저장소별 순서 + 분 소비 추정 |
| **AI-8** | 유형 B 7개의 ArgoCD 인수 계획 | Alan | — | §5-2. 이게 끝나야 GHA 이관 가능 |
| **AI-9** | Actions 포함분 초과 시 대응 합의 (예산 승인 or self-hosted 확대) | Vince | AI-7 | 초과 진입 전 결정 |
| **AI-10** | ADR-0001 상태를 "개정됨"으로 변경, webhook 전환 중단 | Alan | 이 ADR 합의 | ADR-0001 헤더 갱신 |
| AI-11 | CodeBuild 88개 IaC 편입 또는 이관 대상 목록화 | Austin | AI-7 | 목록 확보 (편입은 별건) |
| AI-12 | 조직 2FA 강제 검토 | Vince | — | 별건이나 기록 |

---

## 9. 재검토 조건

- 유형 B의 ArgoCD 인수가 6개월 내 불가로 판명되면 → 해당 저장소용 VPC 러너를 별도 검토한다. (VPC별 CodeBuild 러너는 `supplies-eks-dev-vpc`/`eks-vpc`/`db-vpc` 전부 NAT 있는 private 서브넷이 있어 **신규 네트워크 0으로 가능**하다 — 단일 러너보다 복잡하므로 지금은 채택하지 않는다.)
- Actions 포함분 초과가 상시화되면 → self-hosted 러너를 앱 빌드로 확대할지 재검토. **self-hosted는 GitHub Actions 분을 소비하지 않고 과금도 없다**(공식: *"GitHub Actions usage is free for self-hosted runners"*).
- `eks_dev`/`eks_prod`/`preppers-cluster`의 `endpointPrivateAccess`를 켜고 public CIDR을 좁히면 → k8s 스택 3개가 (조건부)에서 (필수)로 이동. bastion-vpc 러너는 그대로 커버하나 EKS access entry를 prod까지 확장해야 한다.
- 상주 러너의 운영 부담(AMI 패치·잡 간 잔류·단일 장애점)이 실제로 문제가 되면 → **아래 "검토하지 않은 축"을 연다.**

### 검토하지 않은 축 — 기록만 남긴다

지금까지의 비교(CodeBuild / ARC / EC2)는 전부 **"러너를 VPC 안으로 옮긴다"**는 한 축이다. 다른 축이 두 개 있고, 이번에는 채택하지 않지만 존재를 기록해 둔다.

| 축 | 방식 | 성격 |
|---|---|---|
| 네트워크를 러너로 가져온다 | Tailscale/WireGuard 오버레이 + VPC subnet router · Depot VPC peering | GitHub-hosted 유지, 러너 인프라 운영 0. 대신 Actions 분은 계속 소비 |
| **Terraform 실행을 러너 밖으로 뺀다** | **HCP Terraform agents** · Atlantis · Spacelift/env0 self-hosted worker | VPC 안 agent가 plan/apply 수행. GHA는 트리거만. state 잠금·감사·정책이 딸려온다 |

두 번째 축은 **AWS 공식 Prescriptive Guidance가 권고 항목으로 올려둔 방식**이다.

> *"**Run GitHub Actions remotely on HCP Terraform** — Configure GitHub Actions workflows to run Terraform remotely on HCP Terraform workspaces. Rely on dynamic credentials and remote state locking instead of GitHub secrets management."*
> — [Terraform AWS Provider Best Practices — Security](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/security.html)

**지금 채택하지 않는 이유**: PR #103이 이미 구현·검증(plan 16 to add)까지 끝나 있고, 도입 비용이 월 $12로 낮으며, HCP Terraform은 요금제 티어별 agent 개수를 확인하지 못했다(외부 SaaS 의존 판단이 별도로 필요). **다만 "3안 중 최선"이 아니라 "3안 밖에도 축이 있었다"는 사실은 남겨 둔다.**

참고로 **GitHub 자체 기능으로 AWS VPC에 붙는 방법은 2026-08 현재 존재하지 않는다.** GitHub의 private networking은 Azure VNET injection 전용이다.

---

## 부록 A. 실측 근거

전부 2026-08-12 기준, 계정 `699016088228` / 조직 `suppliesfitness`.

```bash
# CodeBuild 91개 중 VPC 연결 57개
aws codebuild list-projects --query 'length(projects)'
# → 91  (프로젝트별 vpcConfig.vpcId 조회로 57개 확인)

# GitHub OIDC provider — 이미 존재 (2026-07-28 생성)
aws iam list-open-id-connect-providers
# → .../oidc-provider/token.actions.githubusercontent.com
#   신뢰 롤 2개: gha-supplies-desktops-publish, shared-bible-index-writer-role

# ECR Pull Through Cache 룰
aws ecr describe-pull-through-cache-rules
# → []  (0개)

# EKS 엔드포인트 공개 범위
aws eks describe-cluster --name dev-eks \
  --query 'cluster.resourcesVpcConfig.{pub:endpointPublicAccess,cidrs:publicAccessCidrs}'
# → dev-eks: 211.218.29.135/32 (사무실 전용, private=true)
#   eks_dev / eks_prod / preppers-cluster: 0.0.0.0/0, private=false
#   supplies-eks-dev: 0.0.0.0/0, private=true

# OpenSearch 내부 ALB DNS — public zone CNAME, 어디서든 해석
dig +short dev-pp-logs-api.supp.fitness
# → internal-supplies-eks-dev-logs-api-679998355...  10.8.157.6  10.8.129.239

# bastion-vpc 허브 경로 (bastion-rtb-public)
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-01a6b8b0ba1c5dc59"
# → 172.16.0.0/16 · 172.31.0.0/16 · 10.8.0.0/16 · 10.20.0.0/16 · 0.0.0.0/0(IGW)
#   NAT Gateway: 0개

# 최근 CodeBuild 활동
aws codebuild list-builds --sort-order DESCENDING
# → 최근 100건이 2026-08-10 11:32 ~ 08-12 11:37 사이 (약 50건/일)
```

```bash
# 조직 플랜 및 사용량
gh api /orgs/suppliesfitness --jq '{plan:.plan.name, seats:"\(.filled_seats)/\(.seats)"}'
# → {"plan":"team","seats":"10/10"}
gh api /organizations/85172941/settings/billing/usage
# → 2026-07 표준 Linux 2,621분 / 포함분 3,000분

# platform-iac 브랜치 보호
gh api /repos/suppliesfitness/platform-iac/branches/main/protection
# → HTTP 404 "Branch not protected"
gh api /repos/suppliesfitness/platform-iac/rulesets
# → []
```

## 부록 B. 참고 문서

### 사내

- platform-iac `docs/2026-08-11-gha-vpc-runner-dockerhub-rate-limit.md` — 선행 조사. 이 ADR과의 관계는 부록 C
- platform-iac PR #103 본문 — bastion-vpc 선택 근거, EKS access entry 필요성, day-1 타협 목록
- platform-iac PR #108 본문 — OIDC 신뢰 정책 형태, ECR Public 전환 선례
- [ADR-0001](ADR001-supplies.md) — §6에서 개정

### 외부 (전부 2026-08-12 확인)

- [CodeBuild-hosted GitHub Actions runner](https://docs.aws.amazon.com/codebuild/latest/userguide/action-runner.html) — `runs-on` 문법, `WORKFLOW_JOB_QUEUED` Terraform 예시
- [CodeBuild GitHub App connection](https://docs.aws.amazon.com/codebuild/latest/userguide/connections-github-app.html) — CodeConnections 지원 근거
- [CodeBuild VPC 지원](https://docs.aws.amazon.com/codebuild/latest/userguide/vpc-support.html) — NAT 필수, IGW 대체 불가
- [CodeBuild Lambda compute](https://docs.aws.amazon.com/codebuild/latest/userguide/lambda.html) / [Reserved fleet](https://docs.aws.amazon.com/codebuild/latest/userguide/fleets.html) — 둘 다 서울 리전 미지원
- [GitHub Actions 한도](https://docs.github.com/en/actions/reference/limits) — 플랜별 동시 잡
- [GitHub Actions 과금](https://docs.github.com/en/billing/concepts/product-billing/github-actions) — 포함분, self-hosted 무료
- [Docker Hub usage and limits](https://docs.docker.com/docker-hub/usage/pulls/) · [정책 철회 공지(2025-02)](https://www.docker.com/blog/revisiting-docker-hub-policies-prioritizing-developer-experience/)
- [Terraform AWS Provider Best Practices — Security](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/security.html) — OIDC 권고, HCP Terraform 원격 실행 권고
- [Terraform state locking](https://developer.hashicorp.com/terraform/language/state/locking) · [Automating Terraform](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform) — plan/apply 자격증명 분리 경고

---

## 부록 C. 선행 조사 문서와의 차이

platform-iac `docs/2026-08-11-gha-vpc-runner-dockerhub-rate-limit.md`에 대한 검증 결과. 대부분은 유효하며, 아래만 갱신이 필요하다.

| 선행 문서 서술 | 검증 결과 |
|---|---|
| B-1 스택 분류 (aws-only 다수 / opensearch 4곳 필수) | ✅ 유효. 실측 37 + 4 일치 |
| B-1 "모든 클러스터가 `publicAccessCidrs: 0.0.0.0/0`" | ❌ **부정확.** `dev-eks`는 `211.218.29.135/32`(사무실)로 이미 잠김 → `dev-eks/k8s`는 지금도 GitHub-hosted 불가 |
| B-1 (미언급) | ❌ **누락.** `eks_dev`/`eks_prod`/`preppers-cluster`는 `endpointPrivateAccess: false` → public CIDR을 좁히면 VPC 러너로도 EKS API 접근 불가. private access 활성화가 선행 |
| B-2 안 A: supplies-eks-dev-vpc에 러너 배치 | ❌ **불충분.** 피어링 비전이성으로 OpenSearch ALB 4개 중 1개만 도달 (§2-4) |
| B-4 #2 "private hosted zone 해석 확인 필요" | ⚠️ **기우.** public zone CNAME이라 어디서든 해석됨. `dig`로 확인 |
| B-4 #2 "내부 ALB SG 확인 필요" | ✅ **해소.** 4개 전부 `443 from 0.0.0.0/0` |
| B-4 #4 "CODECONNECTIONS가 러너에 쓰이는지 검증 필요" | ✅ **해소.** 공식 지원 (부록 B) |
| B-4 #6 "plan 전용 read-only role 검토" | ⚠️ **보정 필요.** §7-4 |
| A-3 "PTC가 1차 해법 (결정됨)" | 🔄 **대체.** ECR Public이 더 단순 (D4) |
| A-1 Docker Hub 한도 수치 | ✅ 유효. 다만 2025 강화안 철회 맥락 추가 (D4) |
| B-2 "CodeBuild 91개는 재활용 가능한 자산" | ⚠️ **맥락 누락.** IaC 관리는 3개, 88개는 콘솔 수기 (§7-3) |
| (미언급) | ❌ **누락.** k8s 스택 5개 전부 `kubernetes_manifest` 사용 → **plan 단계에서도** 클러스터 API 필요. plan/apply 러너 분리 불가 |
