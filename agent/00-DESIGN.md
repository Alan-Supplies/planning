# Platform Boundary System — iac ↔ gitops 책임 계약 설계

> ArgoCD 운영 도입을 늦추는 진짜 원인은 "누가 뭘 소유하는가"가 문서로 고정되지 않은 것이다.
> AI 에이전트를 양쪽에 붙였을 때 이 모호함이 그대로 증폭된다.
> 해법: **자유 대화(티키타카)가 아니라 고정된 계약(contract)을 통해서만 주고받게 한다.**

---

## 1. 왜 티키타카만으로는 안 되는가

두 에이전트가 대화로 경계를 매번 재협상하면:

- 매 실행마다 경계가 미세하게 달라진다 (비결정적).
- 회색지대(namespace, secret, CRD, RBAC)를 서로 "네 거"라고 미룬다.
- 누구도 부트스트랩 chicken-and-egg를 책임지지 않는다.

즉 사람 팀에 경계 계약이 없으면 에이전트에도 없다. **경계를 먼저 코드로 박고**, 티키타카는 그 위에서 "검증 가능한 핑퐁"으로만 돌려야 한다.

---

## 2. 소유 경계 (Provisioning Plane vs Application Plane)

경계선은 **부트스트랩된 ArgoCD + root Application 하나**다.

### platform-iac 소유 (Provisioning Plane)
부트스트랩까지 전부.

- Cloud 인프라: VPC, subnet, 노드풀, IAM/IRSA(OIDC)
- Kubernetes 클러스터 자체
- ArgoCD **설치** (Helm/terraform-helm)
- 최초 `AppProject` + repo credential (secret)
- Git 한 경로를 가리키는 **root Application 하나** (app-of-apps 진입점)
- **산출물 = 타입이 박힌 outputs 계약** (§3)

### platform-gitops 소유 (Application Plane)
root Application 아래 전부.

- 모든 `Application` CR, sync wave, health check
- Helm values / Kustomize overlay
- Progressive delivery (Argo Rollouts 등), drift 관리
- **부트스트랩 이후 ArgoCD 자기 자신 관리 (self-management)**

### 회색지대 — 반드시 명시적으로 배정
| 항목 | 배정 | 근거 |
|---|---|---|
| Namespace 생성 | **gitops** (ArgoCD `CreateNamespace=true`) | 앱 수명주기와 함께 움직임. 단, kube-system 등 시스템 ns는 iac. |
| Secret / External Secrets Operator | ESO **설치는 iac**, SecretStore/ExternalSecret **정의는 gitops** | 설치는 provisioning, 사용은 application. |
| CRD | **컨트롤러를 설치하는 쪽이 소유** (대부분 gitops sync wave 0) | CRD와 컨트롤러는 붙어다녀야 함. |
| RBAC (cluster-level) | **iac** | 보안 경계는 provisioning plane. |
| RBAC (app namespace-level) | **gitops** | 앱과 함께 배포. |
| Bootstrap chicken-and-egg | **iac가 root App까지, 이후 self-management로 gitops 인계** | 인계 지점이 계약에 명시됨. |

> 회색지대 표는 조직에 맞게 조정하되, **떠다니는 항목이 0이 되는 것**이 목표다.

---

## 3. 좁은 인터페이스 (Narrow Waist)

두 에이전트/팀이 교환하는 것은 **오직 하나의 계약 파일**이다.
이 밖의 서로의 내부 구현(TF 모듈, Helm 차트)은 서로 들여다보지 않는다.

- iac는 이 계약을 **생산**한다 (Terraform outputs → JSON).
- gitops는 이 계약을 **소비**한다 (Application/values 렌더링 입력).
- 스키마는 `contract/platform-contract.schema.json` (검증용), 타입은 `contract/platform-contract.ts` (TS).

계약이 진실의 원천(source of truth)이므로, 에이전트가 늘거나 바뀌어도 혼란이 생기지 않는다.

---

## 4. arbiter — 경계 자체의 소유자

두 도메인 에이전트는 **경계를 일방적으로 바꿀 수 없다.**

- 계약 스키마(§3)와 회색지대 표(§2)를 수정할 권한은 **arbiter만** 가진다.
- 분쟁(둘 다 "내 거 아님" 또는 둘 다 "내 거") 발생 시 arbiter가 판정하고 계약/표를 갱신한다.
- arbiter의 판정은 diff로 남아 감사 가능(auditable)하다.

---

## 5. 티키타카 = 검증 가능한 핑퐁

자유 대화가 아니라 정해진 프로토콜(런북 `01-TIKITAKA-PROTOCOL.md`):

```
propose  →  계약 스키마 검증  →  accept / object  →  (분쟁 시) arbiter escalation
```

- 매 라운드는 잡담이 아니라 **spec diff**를 산출한다.
- object는 반드시 "계약의 어느 필드/어느 회색지대 행 위반인지"를 근거로 든다.
- 근거가 계약에 없으면 → 그건 arbiter로 escalation할 신호다.

---

## 6. 파일 구성

```
.
├── 00-DESIGN.md                        # (이 문서) 개념·경계·계약·arbiter 요약
├── 01-TIKITAKA-PROTOCOL.md             # 라운드별 프로토콜 런북
├── contract/
│   ├── platform-contract.ts            # TS 타입 (source of truth for types)
│   ├── platform-contract.schema.json   # JSON Schema (런타임 검증용)
│   └── example.contract.json           # iac가 생산하는 계약 예시
└── agents/                            # → 리포 루트의 .claude/agents/ 로 복사
    ├── iac-agent.md                    # Provisioning plane charter
    ├── gitops-agent.md                 # Application plane charter
    └── arbiter-agent.md                # 경계 소유·분쟁 판정 charter
```

## 7. 도입 순서 (처음 도입 시)

1. §2 회색지대 표를 팀과 함께 확정 (이게 제일 중요, 반나절).
2. `contract/` 스키마를 실제 TF outputs에 맞게 조정.
3. `.claude/agents/` charter를 리포지토리에 커밋 → 두 에이전트를 각 charter로 기동.
4. 첫 PR부터 프로토콜(§5)로 진행. 분쟁은 무조건 arbiter로.
5. 2~3회 반복 후 회색지대 표에 새로 발견된 항목을 arbiter가 추가.
