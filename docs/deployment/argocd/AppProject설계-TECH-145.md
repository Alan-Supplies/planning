# ArgoCD AppProject 설계 (TECH-145)

> **관련 이슈**: [TECH-145 App Project 설계](https://linear.app/suppliesfitness/issue/TECH-145/app-project-설계)
> 상위: [TECH-126 ARGOCD 진행](https://linear.app/suppliesfitness/issue/TECH-126/argocd-진행) · 전제: [TECH-147 환경별 구조](./환경별구조-TECH-147.md) · 정책: [TECH-146 배포 정책]
> 실행 맥락: [order-server GitOps 후속 runbook](./order-server-gitops-후속-runbook.md) (결정 C / 작업 5)
> **성격**: 설계 + 적용 절차 문서 · **담당**: alan · **작성**: 2026-07-20 · **상태**: 🔶 미적용(전 앱 `project: default`)

---

## 1. 요약 (TL;DR)

- **AppProject = 배포 RBAC/범위 경계.** "이 프로젝트의 앱은 *어느 repo에서* *어느 클러스터의* *어느 네임스페이스로* 배포할 수 있고, *누가* 조작할 수 있나"를 제약.
- **현재 미적용**: 클러스터에 custom AppProject 없음(`default` 만). **전 8개 Application 이 `project: default`** — 아무 제약 없음(모든 repo·ns·리소스 허용). 이게 TECH-145 로 닫아야 할 갭.
- 도메인별 프로젝트 **`preppers` / `gymboxx`** 2개. 매니페스트 초안은 `argocd/projects/{preppers,gymboxx}-appproject.yaml` 에 있으나 **whitelist 가 `*/*` 로 열려 있어** 그대로 적용하면 안 됨(§3.3).
- **클러스터 스코핑(모델 A)**: 각 클러스터 ArgoCD 는 자기 도메인 프로젝트만. preppers-cluster=`preppers`, eks-prod=`gymboxx`, dev=`preppers`(+ gymboxx-dev 여부 미정).
- **선행 의존**: 결정 E(consumer default ns 소유) / F(prereqs 소유) 가 `destinations` 의 `default` 임시 허용을 좌우.

---

## 2. 현재 상태 (2026-07-20 확인)

```
$ kubectl get appproject -n argocd          → default 만 (14h)
$ kubectl get application -n argocd -o ...   → 8개 전부 project=default
   platform-root / preppers-order-server-dev(+apisix,+prereqs)
   preppers-kds-server-dev(+apisix) / preppers-kds-polling-dev / preppers-kds-redis-dev
```

`project: default` 는 ArgoCD 내장 프로젝트로 **sourceRepos=`*`, destinations=`*`, cluster/namespace resource=`*`** — 즉 어떤 앱이든 어디로든 배포 가능. 멀티도메인/멀티클러스터로 가면 **격리가 없다는 것 자체가 리스크**(예: preppers 앱이 실수로 gymboxx ns 로, 또는 잘못된 repo 소스로).

---

## 3. 설계 — preppers / gymboxx AppProject

### 3.1 왜 도메인별 1개씩인가
- 소스 격리는 **repo 분리가 아니라 AppProject 경계**로 한다(TECH-147 §3 결론). repo 는 `platform-gitops` 단일.
- 디렉토리 스코핑(`argocd/apps/<domain>/`, `apps/<domain>/<service>/`)과 1:1 로 맞춰 경계를 단순화.

### 3.2 권장 스펙 (결정 C 제안 — 초안의 `*/*` 를 좁힘)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: preppers
  namespace: argocd
spec:
  description: preppers 도메인 워크로드 (order/kds/…)
  sourceRepos:
    - git@github.com:suppliesfitness/platform-gitops.git   # 와일드카드 금지, 단일 repo 고정
  destinations:
    - server: https://kubernetes.default.svc               # in-cluster (모델 A)
      namespace: preppers-*
    # ⚠️ 임시 — apisix consumer/prereqs 가 default 에 남아있는 동안만. 결정 E·F 해소 시 제거.
    - server: https://kubernetes.default.svc
      namespace: default
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace          # CreateNamespace=true 로 ns 자동 생성만 허용 (초안 '*'/'*' 축소)
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'                # 소유 ns 내부는 전체 허용(Deployment/Service/CM/SA/ExternalSecret/ApisixRoute/HPA)
  # RBAC 경계(선택, SSO 연동 시): 도메인별 조작 권한 분리
  # roles:
  #   - name: admin
  #     policies: [ "p, proj:preppers:admin, applications, *, preppers/*, allow" ]
  #     groups: [ "<SSO group>" ]
```

`gymboxx` 는 동일 구조에서 `preppers-*` → `gymboxx-*`, description 만 교체.

### 3.3 초안 대비 변경점 (왜 그대로 apply 하면 안 되나)
| 항목 | 초안(현재 파일) | 권장(결정 C) | 이유 |
|---|---|---|---|
| `clusterResourceWhitelist` | `*` / `*` | `''`/`Namespace` | 클러스터 리소스는 ns 생성뿐 → 최소화. `*` 는 경계 무의미 |
| `destinations`(default ns) | 무기한 허용 | **임시**(결정 E·F 해소 시 제거) | default 는 TF/타 도메인 영역 |
| `sourceRepos` | 단일(OK) | 유지 | 와일드카드 금지 |

> ⚠️ cluster 리소스를 `Namespace` 로 좁히기 전, 앱이 실제로 만드는 cluster-scoped 리소스가 그것뿐인지 확인(현재 ApisixRoute/ExternalSecret 등은 모두 namespaced). 미확인 CRD 있으면 whitelist 에 추가.

---

## 4. 클러스터 스코핑 (모델 A)

각 클러스터의 in-cluster ArgoCD 는 **자기 도메인 프로젝트만** 갖는다. 크로스클러스터 없음 → blast radius 격리.

| 클러스터 | ArgoCD | AppProject | bootstrap root |
|---|---|---|---|
| `supplies-eks-dev` | argocd | `preppers`(+gymboxx 여부 미정) | `argocd/apps/preppers` (+gymboxx) |
| `preppers-cluster`(prod) | argocd | **`preppers` 만** | `argocd/apps/preppers` |
| `eks-prod`(prod) | argocd | **`gymboxx` 만** | `argocd/apps/gymboxx` |

→ preppers-cluster ArgoCD 는 gymboxx AppProject 를 애초에 안 만듦(도메인 슬라이스만 부트스트랩). 상세: runbook 작업 5 "클러스터 스코핑 원칙".

---

## 5. 적용 절차 (미적용 → 적용)

무중단. Application 의 `project` 만 바꾸는 건 메타 변경이라 워크로드 재생성 없음.

```bash
CTX=arn:aws:eks:ap-northeast-2:699016088228:cluster/supplies-eks-dev
# 1) 초안 수정: whitelist 축소, destinations 정리 (§3.2)
#    argocd/projects/preppers-appproject.yaml (+ gymboxx)
# 2) root 가 argocd/projects/ 를 관리하도록 확인(recurse) → commit/push → ArgoCD 가 AppProject 생성
kubectl get appproject -n $CTX --context=$CTX     # preppers/gymboxx 생성 확인
# 3) 앱의 project 를 default → preppers 로 교체
#    - workloads-appset.yaml: template.spec.project: preppers
#    - order-server-{prereqs,apisix}.yaml / kds-*.yaml: spec.project: preppers
#    - (platform-root 자체는 default 유지 or 별도 정책)
# 4) commit/push → 각 Application 이 preppers 프로젝트로 재바인딩(Synced 유지 확인)
kubectl get application -n argocd --context=$CTX -o custom-columns=NAME:.metadata.name,PROJECT:.spec.project
```

> ⚠️ 순서 주의: **AppProject 를 먼저 apply**(2) 한 뒤 앱 project 교체(3). 없는 프로젝트를 참조하면 앱이 `Missing`/거부됨.
> 롤백: 앱 project 를 `default` 로 되돌리면 즉시 원복(AppProject 삭제는 그 후).

---

## 6. 열린 결정 / 의존

| # | 항목 | 연계 |
|---|---|---|
| C | preppers/gymboxx AppProject 확정(§3.2 스펙 승인) | 본 이슈 |
| E | `default` ns 의 apisix consumer 소유 → destinations 의 default 임시 허용 존치/제거 | runbook 결정 E |
| F | prereqs(env ConfigMap 등) TF vs GitOps 소유 → default 참조 정리 | runbook 결정 F |
| — | dev 에 gymboxx 수용 여부(멀티도메인 dev) → dev AppProject 목록 | 작업 5 |
| — | SSO/OIDC 연동 시 roles(RBAC) 정의 — 지금은 미연동이라 보류 | 후속 |

---

## 7. 다음 액션

- [ ] §3.2 스펙으로 결정 C 확정(리뷰)
- [ ] `argocd/projects/*.yaml` 초안 수정: ns `argocd`, whitelist 축소, destinations 정리
- [ ] AppProject apply → 앱 `project: default → preppers` 교체(§5) — dev 먼저
- [ ] prod(preppers-cluster/eks-prod) 는 작업 5에서 도메인 슬라이스별 적용
- [ ] 완료 시 Linear TECH-145 Done + runbook 결정 C 갱신
