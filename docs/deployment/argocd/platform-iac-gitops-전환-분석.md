# platform-iac 를 GitOps 로 전환하는 것에 대한 분석 (Terraform 비교 포함)

> **목적**: 현재 Terraform(`platform-iac`)이 소유한 인프라를 GitOps(ArgoCD)로 옮기는 것이 타당한지, TF 와 비교해 분석한다.
> **배경**: TECH-147 파일럿에서 "order-server 의 ns 레벨 prereqs(env/secret/SA)를 누가 소유하나?"라는 질문이 나왔고,
> 이를 계기로 "인프라 전반을 GitOps 로 가는 것"의 타당성을 검토한다.
> **상태**: **분석/의사결정 문서 (미결정)**. 결론이 아니라 결정을 돕는 자료.
> 관련: [order-server-gitops-파일럿-runbook.md](./order-server-gitops-파일럿-runbook.md) · [환경별구조-TECH-147.md](./환경별구조-TECH-147.md)

---

## 1. TL;DR (결론 먼저)

- **"Terraform 을 통째로 GitOps 로"는 비권장.** ArgoCD 는 k8s 매니페스트만 배포하지, `terraform apply` 를 못 한다.
  하려면 `tf-controller`/Crossplane 같은 **별도 도구**가 필요하고, 성숙도·러닝커브·리스크가 크다.
- **권장 = Option B 하이브리드**: **클라우드 인프라(VPC/EKS/IAM/RDS)는 Terraform**, **클러스터 안 k8s 리소스는 GitOps**.
  이건 업계에서 가장 흔한 경계이고, 우리 파일럿 결과와도 잘 맞는다.
- 그래서 실제로 정해야 할 것은 "TF vs GitOps 전면 교체"가 아니라 **"ns 레벨 k8s 리소스(configmap/secret/SA/operator)를
  TF 가 계속 쥘 것인가, GitOps 로 넘길 것인가"라는 경계선** 하나다.
- 이 경계 결정은 파일럿의 **"prereqs → platform-iac 이관" track 을 재검토**하게 만든다(아래 §7).

---

## 2. 현재 상태 (무엇을 무엇이 관리하나)

| 대상 | 예시 | 현재 소유 |
|---|---|---|
| 클라우드 인프라 | VPC, EKS 클러스터, IAM, RDS, ECR | **Terraform** (`platform-iac`) |
| 클러스터 부트스트랩 | ArgoCD 설치, ESO 설치, ClusterSecretStore, storageclass, ingress-controller | **Terraform** (`stacks/eks/.../k8s`) |
| ns 레벨 리소스 | `env` ConfigMap, ExternalSecret(credentials/firebase/jwt), (SA) | **Terraform** (default ns) |
| 앱 워크로드 | Deployment/Service (order-server) | 기존=CodeBuild / 파일럿=**ArgoCD** |
| 앱의 ns 레벨 prereqs | preppers-dev 의 env/secret/SA | 파일럿=**ArgoCD**(임시) |

핵심: TF 가 **클라우드 + 클러스터 부트스트랩 + ns 레벨**까지 폭넓게 쥐고 있고, ArgoCD 는 최근 파일럿에서 앱 영역에 진입했다.

---

## 3. 반드시 두 레이어로 나눠서 봐야 한다

"인프라를 GitOps 로"를 한 덩어리로 논하면 틀린다. 레이어마다 답이 다르다.

### 레이어 1 — 클라우드 인프라 (VPC/EKS/IAM/RDS/ECR)
- k8s API 밖의 리소스. ArgoCD 가 **네이티브로 못 다룬다**.
- Terraform/OpenTofu 가 사실상 표준. provider 성숙도·plan 미리보기·의존성 그래프가 강점.
- GitOps 로 하려면 Crossplane/ACK(CRD 로 클라우드 리소스 표현) 또는 tf-controller 필요 → **레이어 1 은 TF 유지가 합리적**.

### 레이어 2 — 클러스터 안 k8s 리소스 (namespace/configmap/secret/SA/operator/CRD)
- 전부 k8s API 객체 → ArgoCD 가 **네이티브로 가장 잘 하는 영역**.
- 지속적 reconcile·self-heal·drift 감지·git 롤백의 이점이 그대로 적용.
- **여기가 진짜 논쟁 지점.** TF 도 할 수 있지만(지금 그렇게 함), GitOps 가 더 자연스러운 영역.

> 결론 방향: 레이어 1 = TF, 레이어 2 = GitOps 가 기본. 레이어 2 안에서도 "부트스트랩(ArgoCD/ESO 자체)"은
> 닭-달걀 문제로 TF 에 남기는 게 보통이다(ArgoCD 를 ArgoCD 가 설치할 수 없으므로).

---

## 4. Terraform vs GitOps 근본 비교

| 차원 | Terraform | GitOps (ArgoCD/Flux) |
|---|---|---|
| 대상 | 클라우드 + k8s(둘 다) | **k8s API 객체만** |
| 실행 모델 | **명령형 apply** (사람/CI 트리거) | **선언형 지속 reconcile** (컨트롤러가 상시) |
| 드리프트 | 다음 apply 전까지 방치(감지 안 됨) | **상시 감지 + self-heal** |
| 상태 | **state 파일**(락·민감정보·정합성 관리 필요) | 별도 state 없음(클러스터=실제, git=목표) |
| 변경 미리보기 | **`terraform plan`(강력)** | diff/dry-run(있으나 plan 만큼 정밀하진 않음) |
| 롤백 | state 되돌리기(까다로움) | **`git revert` + 자동 sync(쉬움)** |
| 순서/의존성 | **의존성 그래프 내장(강함)** | 앱 간 순서 보장 약함(sync wave/app-of-apps 필요) |
| 시크릿 | state 에 평문 유입 위험 | git 에 평문 금지 → ESO/sealed-secrets 필요 |
| 부트스트랩 | 자체로 가능 | 누군가 ArgoCD 를 먼저 깔아야 함(보통 TF) |
| 감사/승인 | PR + plan 리뷰(Atlantis/TFC) | **git 이력 = 감사 로그**, PR 리뷰 |
| 러닝커브 | HCL·state·provider | k8s·Helm/Kustomize·ArgoCD |
| 성숙도(클라우드) | **매우 높음** | 낮음(Crossplane 등 별도) |
| 성숙도(k8s 워크로드) | 보통(kubernetes provider 는 한계 있음) | **매우 높음** |

한 줄 요약: **TF = "한 번 맞추는" 프로비저닝에 강함(특히 클라우드). GitOps = "계속 맞춰두는" 운영에 강함(특히 k8s).**

---

## 5. 옵션

### Option A — 전부 Terraform (현재)
- 장점: 단일 도구, 팀이 이미 익숙, 클라우드까지 일관.
- 단점: k8s 리소스에 drift 방치·self-heal 없음, kubernetes provider 한계, `kubernetes_manifest`의 CRD 선행 문제.

### Option B — 클라우드=TF, 클러스터 k8s=GitOps ⭐ (권장)
- 경계: 레이어1(클라우드) + 부트스트랩(ArgoCD/ESO 설치)은 TF, 그 위 k8s 리소스/워크로드는 GitOps.
- 장점: 각 도구를 강점 영역에 배치, drift/self-heal 이점 확보, 업계 표준.
- 단점: 경계 관리 필요(어디까지 TF? 어디부터 GitOps?), 두 시스템 운영.

### Option C — 전부 GitOps (Crossplane/tf-controller 로 클라우드까지)
- 장점: 단일 reconcile 모델, 모든 것이 git 선언형.
- 단점: **도입 비용·성숙도·러닝커브 큼**, 클라우드 리소스를 CRD 로 다루는 리스크, state/import 마이그레이션 부담. 지금 단계엔 과함.

```
        클라우드 인프라        클러스터 k8s 리소스        앱 워크로드
A:      Terraform ───────────  Terraform ─────────────  ArgoCD(or CodeBuild)
B(권장): Terraform ───────────  ArgoCD ────────────────  ArgoCD
C:      Crossplane/tf-ctrl ──  ArgoCD ────────────────  ArgoCD
```

---

## 6. "Terraform 을 GitOps 로" 돌리는 도구들 (참고)

| 도구 | 방식 | 비고 |
|---|---|---|
| **Crossplane** | 클라우드 리소스를 k8s CRD 로 표현 → ArgoCD 가 관리, Crossplane 이 클라우드에 reconcile | TF 를 대체(레이어1까지 GitOps). 성숙 중, 러닝커브 큼 |
| **tf-controller (Flux)** | 기존 TF 코드를 k8s 컨트롤러가 plan/apply | TF 자산 재사용. Flux 종속 |
| **Atlantis / Terraform Cloud / Spacelift** | PR 기반 TF apply 자동화 | k8s 컨트롤러 아님. "TF 를 GitOps 스럽게" 운영(가장 현실적인 TF 개선안) |

> 즉 "platform-iac 를 ArgoCD app 으로"의 현실적 형태는 **Crossplane/tf-controller 도입**이거나, TF 는 그대로 두고
> **Atlantis 류로 PR-driven apply** 를 붙이는 것이다. 전자는 큰 결정, 후자는 GitOps 전환이라기보다 TF 워크플로 개선.

---

## 7. 이 조직 맥락에 적용 (파일럿 관찰 근거)

파일럿에서 관찰된 사실:
- ESO 설치·`ClusterSecretStore`(cluster-scoped)는 TF 관리이고 **잘 동작**한다 → 부트스트랩은 TF 유지가 자연스럽다.
- 반면 앱의 ns 레벨 prereqs(env/ExternalSecret/SA)를 **ArgoCD 로 관리해도 무리 없이 동작**했다(Synced/Healthy).
- `config.tf` 와 live 사이에 **drift**(`PREPPERS_ORDER_DB_NAME`)가 있었고, TF 는 이를 **감지·교정하지 않았다**
  → 레이어2 에서 GitOps 의 drift 감지·self-heal 이점이 실제로 의미 있음을 시사.

**함의**: runbook 의 track1("prereqs → platform-iac 이관")은 **Option A 전제**다. 만약 조직이 **Option B** 를 택하면,
prereqs 를 TF 로 되돌리지 않고 **GitOps 에 그대로 두는 것이 오히려 일관**된다. 즉 이 분석의 결론이 이관 track 방향을 바꿀 수 있다.

---

## 8. 권장안

1. **Option B 채택** — 클라우드 + 부트스트랩(ArgoCD/ESO/ClusterSecretStore)은 TF, 그 위 ns 레벨 k8s 리소스·워크로드는 GitOps.
2. 따라서 **prereqs 는 GitOps 에 유지**(track1 재검토). 단 "앱 전용 리소스"만 GitOps, "클러스터 공용 부트스트랩"은 TF 로 경계 유지.
3. **Option C(Crossplane 등)는 현시점 보류** — 필요성이 확인되면(예: 앱팀이 클라우드 리소스를 셀프서비스로 선언하고 싶을 때) 재검토.
4. TF 쪽 drift 리스크는 **정기 `plan` 점검**(또는 Atlantis 도입)으로 별도 완화.

---

## 9. 마이그레이션 시 고려사항 / 리스크

- **경계 문서화**: "무엇이 TF, 무엇이 GitOps"를 명확히(안 그러면 두 도구가 같은 리소스를 두고 싸움 → drift 전쟁).
- **이중 관리 금지**: 한 리소스를 TF 와 ArgoCD 가 동시에 소유하면 안 됨. 이관 시 한쪽에서 완전히 제거 후 다른 쪽에서 채택.
- **시크릿**: GitOps 로 넘겨도 평문은 git 금지 → ESO 유지(이미 그렇게 함).
- **부트스트랩 닭-달걀**: ArgoCD/ESO 자체는 TF 로 남겨야(ArgoCD 가 자신을 설치 못 함).
- **상태 import**: 기존 TF 관리 리소스를 GitOps 로 옮기면 TF state 에서 `terraform state rm` + ArgoCD 채택 순서 주의.
- **거버넌스**: prod 는 자동 sync 대신 수동 승인(sync window/manual)으로 안전장치 고려(TECH-146).

---

## 10. 열린 결정 & 다음 액션

| # | 결정 | 옵션 | 상태 |
|---|---|---|---|
| I | 인프라 관리 경계 | A(전부 TF) / **B(하이브리드)** / C(전부 GitOps) | **미정** (권장 B) |
| II | prereqs 최종 소유 | platform-iac(TF) / **GitOps 유지** | I 에 종속 |
| III | TF drift 완화 | 정기 plan / Atlantis / 방치 | 미정 |
| IV | APISIX consumer 소유 | 수동 kubectl(현재) / GitOps / TF | **미정**. 현재 둘 다 수동 kubectl(소유 약함). 단 `preppers-backend`는 order 소유 아님(공유), `<ns>_<name>` 규칙상 이동 시 whitelist 깨짐 → route 와 분리 결정. 상세=후속 runbook 결정 E |

다음 액션(결정 후):
1. Option 확정 → runbook 의 "향후 이관 트랙" 갱신(track1 유지/폐기).
2. TF ↔ GitOps 경계표를 팀 위키/README 에 확정 문서화.
3. (B 채택 시) prereqs 를 GitOps 정식 소유로 승격 + 클러스터 공용 부트스트랩만 TF 유지 명시.

---

## 변경 로그
- 2026-07-16: 최초 작성. 파일럿(TECH-147)에서 파생된 "인프라 GitOps 전환" 질문에 대한 분석. 권장 = Option B 하이브리드.
