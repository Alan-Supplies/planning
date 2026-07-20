# order-server GitOps 파일럿 Runbook (TECH-147 §6.1)

> 목적: order-server 를 ArgoCD(Helm 공유 차트)로 배포하는 **파일럿을 수동으로** 진행.
> 이 문서는 진행하면서 계속 갱신한다. **중단해도 아래 "현재 상태"만 보면 이어서 가능.**
> 설계 근거: [환경별구조-TECH-147.md](./환경별구조-TECH-147.md) · 스캐폴딩: `gitops/`

---

## ⭐ 현재 상태 (여기부터 이어서)

- **완료**: 파일럿 전 단계(0~5). **두 Application(app + prereqs) 모두 Synced/Healthy 달성** 🎉.
- **완료(2026-07-17)**: **APISIX 실트래픽 컷오버** — order 라우트 3개를 default → preppers-dev 로 무중단 이동. 실 dev(`dev-pp-api.supp.fitness`)가 이제 preppers-dev 를 서빙. (아래 "APISIX 컷오버" 섹션)
- **결정 완료**: A=이 repo / B=ESO / C=임시 `default` / D=prereqs 이 repo GitOps 임시.
- **다음 할 일**: ① **apisix 라우트 GitOps 이관 마무리** (매니페스트/Application 커밋됨 — push + `preppers-order-server-dev-apisix` Application apply 대기) ② pri/private 유효 토큰 스모크 테스트 ③ **후속 트랙** — prereqs → platform-iac 이관, main 승격/ApplicationSet(§6.2), DB_PASSWORD 로테이션, DB명 drift.

> ✅ **2026-07-16 파일럿 완료.** 두 Application Synced/Healthy 확인(대시보드 포함).
> repo credential = SSH deploy key(`repo-preppers-order-server`, argocd-alan) 등록.
> 클러스터 조사 결과(2단계 근거):
> - ESO 설치됨 + `ClusterSecretStore/aws-secrets-manager`(cluster-scoped) 정상 → preppers-dev 에서 그대로 참조.
> - default 의 env/ExternalSecret 은 **platform-iac Terraform** 이 소유(`config.tf`, `external-secrets.tf`).
>   → 원래 조직 경계는 TF 지만, **테스트 단계라 일단 이 repo GitOps 로 진행 후 검증되면 이관**하기로 결정.
> - Pod Identity association 0개 + 신뢰정책에 OIDC 없음 → AWS 접근은 **노드 role**. 같은 nodepool 이라 재현됨(IAM 변경 불필요).
> - order-server 는 `jwt-secret` 미사용 → prereqs 에서 제외.
> - 🔴 **보안(별도 트랙)**: live `default/env` configmap 주석에 평문 `DB_PASSWORD` 노출 → 로테이션 + 주석 정리 권장.
> - ⚠️ **drift(별도 트랙)**: live `PREPPERS_ORDER_DB_NAME=prpers_order`(오타 의심) vs config.tf `preppers_order`. 파일럿은 live 값 유지.

진행 단계: `[x]`=완료 `[ ]`=대기
```
[x] 0. 스캐폴딩 + 로컬 렌더
[x] 1. TODO 값 확정 (ECR repo/tag)
[x] 2. prereqs(ns/SA/env/ExternalSecret x2) 매니페스트 작성 + dry-run 검증(5/5)
[x] 3. 파일럿 브랜치 push 완료
[x] 4. Application(app + prereqs) 적용 (repo cred=SSH deploy key, project=default 임시)
[x] 5. 동기화 확인 — 두 Application Synced/Healthy ✅
```

---

## 열린 결정 (정해야 다음 진행)

| # | 결정 | 옵션 | 결론 |
|---|---|---|---|
| A | GitOps repo 위치 | 별도 `preppers-gitops` / **이 repo로 테스트** | ✅ **이 repo** (검증 후 승격) |
| B | Secret 이전 방식 | 수동 복제 / SealedSecrets / **External Secrets** | ✅ **External Secrets (ESO)** |
| C | `spec.project` | `preppers`(TECH-145 대기) / 임시 `default` | ✅ **임시 `default`** (preppers AppProject 미존재. TECH-145 확정 시 교체) |
| D | ns 레벨 prereqs 위치 | platform-iac(TF) / **이 repo GitOps 임시** | ✅ **이 repo GitOps** (테스트, 검증 후 platform-iac 이관) |

---

## 네임스페이스 전략 / 향후 이관 (⚠️ 놓치기 쉬움 — 반드시 참고)

**왜 preppers-dev 에 prereqs 를 따로 두나?**
ConfigMap/Secret 은 **namespace-scoped** — 파드는 자기 ns 안의 것만 참조함. 기존 `env`/`credentials`/
`firebase-credentials`/SA 는 `default` ns 에 있어 `preppers-dev` 파드가 못 씀. 그래서 preppers-dev 에 실체가 필요.
(Secret 은 복붙이 아니라 ESO 가 AWS SM 단일 원천에서 각 ns 로 sync → 값은 한 곳, 실체는 ns 마다.)

**만약 default 에 배포한다면?** 이미 있으므로 prereqs 불필요. 단 설계(§6.2)는 **default 탈출 → `preppers-dev`/
`preppers-prod` 분리**가 목표. 즉 default 재사용은 목표와 배치되고, prereqs 는 "버리는 것"이 아니라 **영구 필요**
(추후 소유권만 이 repo → platform-iac TF 로 이관).

**네임스페이스는 어디서 바뀌나? (단일 소스)**
- 앱(차트): `Application.spec.destination.namespace` 한 곳. 템플릿은 `.Release.Namespace` 사용, ns 하드코딩 없음.
- prereqs: 매니페스트에서 `metadata.namespace` **의도적으로 생략** → ArgoCD 가 `destination.namespace` 주입.
  → ns 변경/추가는 **두 Application 의 `destination.namespace` 만** 고치면 됨(매니페스트 손 안 댐).
  ⚠️ 단, prereqs 를 ArgoCD 안 거치고 직접 `kubectl apply` 하면 현재 컨텍스트 ns 로 감 → 반드시 `-n` 지정.
- 최종 형태 **ApplicationSet(§6.2)**: `{ env: dev, ns: preppers-dev }` 리스트 한 줄로 환경/ns 추가·변경.

**향후 이관 트랙 (이 파일럿 이후, 별도 진행)**
1. prereqs(env/SA/ExternalSecret) → **platform-iac Terraform** 으로 이관(조직 관리 경계 복귀).
   ⚠️ 단, 이 방향은 "인프라를 어디서 소유하나(TF vs GitOps)" 결정에 종속됨 →
   분석: [platform-iac-gitops-전환-분석.md](./platform-iac-gitops-전환-분석.md) (권장 = 하이브리드 → prereqs 는 GitOps 유지 가능).
2. 실 워크로드 `default` → `preppers-dev` 이관 (TECH-145 AppProject 경계 + §6.2 확산).
3. 🔴 별도 트랙: live `default/env` 주석의 평문 `DB_PASSWORD` 로테이션 + 주석 정리.
4. ⚠️ 별도 트랙: `PREPPERS_ORDER_DB_NAME` drift(`prpers_order` vs `preppers_order`) 실 DB명 확인 후 정합화.

---

## Application 을 왜 둘로 나눴나 (app / prereqs)

| Application | 소스 타입 | 소유 | path |
|---|---|---|---|
| `preppers-order-server-dev` | **Helm 차트** (helm template) | 앱(이 repo→승격) | `gitops/charts/preppers-service` + valueFiles |
| `preppers-order-server-dev-prereqs` | **raw 매니페스트** (directory) | ns 인프라(→platform-iac 이관) | `gitops/apps/order-server/prereqs` |

- **소스 타입이 다름**: 1개 Application = 1개 소스(도구). 차트 렌더링과 생짜 매니페스트를 한 path 로 섞기 어려움.
- **소유권/생명주기 경계**: prereqs 는 나중에 platform-iac 로 이관 → 나눠두면 **prereqs Application 만 삭제**하면 앱 무영향.
  prune/RBAC 정책도 분리 가능, 앱 롤백/재싱크가 secret 인프라에 영향 안 줌.
- **트레이드오프**: 두 Application 간 sync **순서 보장 없음**(앱 파드가 prereqs 대기 후 수렴). 대안(차트에 인프라 템플릿 포함 / multi-source)은 소유권 경계를 흐려 파일럿엔 부적합.

---

## 이미지 태그 자동화 (CI → git bump → ArgoCD)

**문제**: GitOps 는 git 에 적힌 tag 만 배포 → 새 빌드마다 누군가 git 의 `values-dev.yaml` tag 를 갱신해야 함.
(웹훅은 "ArgoCD 를 빨리 깨우는 알림"일 뿐, tag 를 써넣지는 못함.)

**CI/CD 체인**: `push develop`(또는 workflow_dispatch) → GH Actions(`deploy.yml`) → CodeBuild 트리거 →
`buildspec.yml`(빌드+ECR push+`kubectl apply` default). 실제 배포는 CodeBuild.

**적용한 자동화 (파일럿, default 배포와 병행)**:
- `buildspec.yml` `post_build` 끝에 dev 전용 bump 블록 추가:
  이미지 push 후 `git checkout <GITOPS_BRANCH>` → `sed` 로 `values-dev.yaml` `image.tag=$TAG` → commit`[skip ci]` → push.
  → ArgoCD(targetRevision=그 브랜치)가 preppers-dev 에 새 태그 배포. **기존 `kubectl apply`(default)는 유지**.
- `GITOPS_BRANCH` 미설정 시 `feature/TECH-147/argocd-chart` fallback.
- `deploy.yml` push 트리거에 `paths-ignore: [gitops/**, docs/**]` → bump 커밋이 재빌드 유발 안 함(루프 방지).

**루프**: `deploy.yml` 은 `develop` push 에만 트리거 → 파일럿(feature 브랜치)엔 루프 없음.
develop 으로 옮길 때는 `[skip ci]` + `paths-ignore` 로 방지(이미 반영).

**⚠️ 전제/확인 필요**:
- `GITHUB_TOKEN`(secretsmanager `codebuild/gh_token`)에 **repo write(push) 권한** 필요.
- 파일럿 테스트 방법: feature 브랜치에서 `deploy.yml` **workflow_dispatch** 실행 → 빌드 → bump → ArgoCD 배포 관찰.
- bump 시 tag 라인의 주석은 sed 로 제거됨(무해).

---

## 확정된 값 / 컨텍스트 (채우면서 진행)

| 항목 | 값 | 비고 |
|---|---|---|
| dev EKS 클러스터 | `supplies-eks-dev` | arn:aws:eks:ap-northeast-2:699016088228:cluster/supplies-eks-dev |
| dev 클러스터 kube-context | `supplies-eks-dev` | `kubectl config get-contexts` 로 확인 |
| GitOps repo | `suppliesfitness/preppers-order-server` | 파일럿은 이 repo (path=`gitops/...`) |
| 파일럿 브랜치 | `feature/TECH-147/argocd-chart` | 검증 후 main |
| ArgoCD 네임스페이스 | `argocd-alan` | 컨트롤플레인 |
| 워크로드 네임스페이스 | `preppers-dev` | 신규 (기존은 `default`) |
| ECR repo 이름 | `dev` | 환경별 단일 repo. CodeBuild `ECR_REPO_NAME`. 서비스는 태그 접두사로 구분 |
| AWS account | `699016088228` | ap-northeast-2 |
| dev image.tag | `preppers-order-dev-0im1wuil` | 형식=`$IMAGE_TAG-$TARGET_ENV-$RANDOM`(불변). 현재 dev 배포본 |

---

## 단계별 절차

> kubectl 은 전역 규칙: `kubectl <verb> <resource> --context=<name>` (context 맨 뒤).

### 0. 로컬 렌더 (안전, dry-run) — ✅ 완료
```bash
cd gitops
helm template preppers-order-server-dev charts/preppers-service \
  -f apps/order-server/values.yaml -f apps/order-server/values-dev.yaml \
  --namespace preppers-dev | less
```

### 1. TODO 값 3개 확정 — ⬜
`gitops/apps/order-server/` 안 placeholder 교체:
- `values.yaml` → `image.repository` (ECR repo 이름)
- `values-dev.yaml` → `image.tag` (배포할 dev 태그)
- `values-prod.yaml` → `replicaCount` (기존 `PODS_NUM`, dev 파일럿엔 불필요)

```bash
# ECR 최신 태그 확인
aws ecr describe-images --repository-name <ECR_REPO_NAME> --region ap-northeast-2 \
  --query 'sort_by(imageDetails,&imagePushedAt)[-5:].imageTags' --output table
```

### 2. prereqs (ns/SA/env/ExternalSecret) 매니페스트 — ✅ 작성 완료 / 🔲 dry-run 검증
차트가 참조하므로 `preppers-dev` 에 존재해야 함: ConfigMap `env`, Secret `credentials`,
Secret `firebase-credentials`, SA `pod-service-account`. 결정 D = **이 repo GitOps 로 임시 관리**.

**작성된 파일** (`gitops/apps/order-server/prereqs/`):
- `configmap-env.yaml` — live default/env 복제 (21키)
- `serviceaccount.yaml` — `pod-service-account` (+role-arn 주석, 현재 inert)
- `externalsecret-credentials.yaml` — AWS SM `preppers/dev/common-credentials`
- `externalsecret-firebase-credentials.yaml` — AWS SM `firebase/preppers-kds-dev`
- (+ `gitops/argocd/applications/preppers-order-server-dev-prereqs.yaml` — 2번째 Application, directory 소스)

**2-검증. client dry-run** (클러스터 변경 없음, ns 미존재여도 됨, CRD 스키마까지 검증):
```bash
kubectl apply --dry-run=client -f gitops/apps/order-server/prereqs/ --context=supplies-eks-dev
kubectl apply --dry-run=client -f gitops/argocd/applications/preppers-order-server-dev-prereqs.yaml --context=supplies-eks-dev
```

> **평문 Secret 값은 절대 repo 에 커밋 금지** — ExternalSecret 은 "참조"만 커밋(준수함).
> env(ConfigMap)는 비밀 아님 → 임시로 값 커밋. 검증 후 platform-iac `config.tf` 로 이관.

### 3. 브랜치 push (이 repo 파일럿) — ⬜
결정 A = 이 repo 사용. `gitops/` + `docs/deployment` 를 파일럿 브랜치에 커밋/push.
```bash
git add gitops docs/deployment
git commit -m "feat(gitops): order-server ArgoCD 파일럿 (prereqs+app) (TECH-147)"
git push -u origin feature/TECH-147/argocd-chart
```
> ArgoCD 가 이 repo(private)에 접근할 repo credential 이 등록돼 있어야 함 — 없으면 등록 필요.

### 3-1. ArgoCD repo credential 등록 ⬜

**목표**: ArgoCD(클러스터 내 argocd-alan)가 GitHub의 파일럿 브랜치에 SSH로 접근하도록 인증 설정.

**용어 정리**:
- **Deploy key**: 특정 GitHub 저장소에만 접근 권한을 갖는 SSH 공개키 (전체 개인키 노출 위험 없음)
- **SSH 키 쌍**: `private key`(로컬 보관, 절대 공개금지) + `public key`(GitHub 등록, 공개OK)
- **Passphrase 없음**: 자동화 도구(ArgoCD)가 passphrase 입력 없이 사용 가능하도록

**절차**:

1️⃣ **SSH 키 쌍 생성** (로컬):
```bash
# passphrase 없는 ed25519 키 생성
ssh-keygen -t ed25519 -f ~/.ssh/argocd_repo -N "" -C "argocd-repo-credential"
# 결과: ~/.ssh/argocd_repo (private), ~/.ssh/argocd_repo.pub (public)
```

2️⃣ **GitHub에 public key 등록**:
```
GitHub → [저장소] → Settings → Deploy keys → Add deploy key
  Title: argocd-credential
  Key: ~/.ssh/argocd_repo.pub 의 전체 내용 복사
  ☑️ Allow write access (체크)
  → Add key
```

3️⃣ **ArgoCD에 credential 등록** (아래 중 택일):

**방법 A: kubectl Secret 직접 생성** (kubeconfig 접근 가능한 곳에서):
```bash
kubectl create secret generic repo-<REPO_NAME> \
  -n argocd-alan \
  --from-literal=type=git \
  --from-literal=url=git@github.com:suppliesfitness/<REPO>.git \
  --from-file=sshPrivateKey=~/.ssh/argocd_repo \
  --dry-run=client -o yaml | kubectl apply -f - --context=supplies-eks-dev

# Label 추가 (ArgoCD가 이 Secret을 repo credential로 인식하도록)
kubectl label secret repo-<REPO_NAME> -n argocd-alan \
  argocd.argoproj.io/secret-type=repository --overwrite \
  --context=supplies-eks-dev
```

**방법 B: argocd CLI** (ArgoCD server 접근 가능 시):
```bash
# 먼저 ArgoCD server에 로그인
argocd login localhost:8081 --username admin --password <PASSWORD> --insecure

# repo 등록
argocd repo add git@github.com:suppliesfitness/<REPO>.git \
  --ssh-private-key-path ~/.ssh/argocd_repo
```

**⚠️ 주의사항**:
- private key(`~/.ssh/argocd_repo`)는 절대 git에 커밋금지 (`.gitignore` 확인)
- public key만 GitHub에 등록 — 이것은 공개 가능
- SSH 키는 passphrase 없어야 함 (자동화용)
- 같은 public key를 여러 저장소에 등록 가능 (deploy key 재사용)

### 4. AppProject / Application 적용 (app + prereqs) — ⬜
> **결정 C**: `spec.project` = `preppers`. AppProject `preppers` 없으면 두 Application 모두 sync 실패 →
> 임시로 두 파일의 `project: preppers` 를 `default` 로 바꿔 적용하거나, AppProject 를 먼저 생성.
```bash
# (project preppers 존재 확인)
kubectl get appproject -n argocd-alan --context=supplies-eks-dev
# prereqs 먼저(권장), 그 다음 app
kubectl apply -f gitops/argocd/applications/preppers-order-server-dev-prereqs.yaml --context=supplies-eks-dev
kubectl apply -f gitops/argocd/applications/preppers-order-server-dev.yaml --context=supplies-eks-dev
```

### 5. 동기화 확인 — ⬜
```bash
kubectl get application -n argocd-alan --context=supplies-eks-dev | grep preppers-order
kubectl get externalsecret,secret,configmap,sa -n preppers-dev --context=supplies-eks-dev
kubectl get pods -n preppers-dev --context=supplies-eks-dev
# 성공 기준: 두 Application Synced/Healthy + Secret(credentials/firebase-credentials) SecretSynced
#           + Pod Running + /pub/v1/order/healthz 통과
```

---

## APISIX 컷오버 (default → preppers-dev, 실트래픽 이동)

**목표**: 실 dev(`dev-pp-api.supp.fitness`)의 order 라우트를 default 서비스 → preppers-dev 서비스로 무중단 전환.

**핵심 제약**:
- `ApisixRoute` backend(`serviceName`)는 **같은 ns 의 Service 만** 참조 → 라우트를 preppers-dev 로 옮겨야 preppers-dev 서비스로 감(v2 API 에 backend namespace 필드 없음). ingress-controller 는 ns 필터 없이 전 ns watch → preppers-dev 라우트도 인식됨.
- 같은 host+path 를 두 ns 에 동시 두면 충돌 가능 → 전환은 **새 라우트 apply → 검증 → default 삭제** 순(겹침 구간엔 양쪽 다 정상 200 서빙이라 무해, 다운타임 0).
- **consumer(`preppers-backend`, `preppers-order-consumer`)는 default 유지**. 컨트롤러가 consumer 를 `<ns>_<name>` 으로 APISIX 에 등록(글로벌 객체) → 옮기면 이름이 바뀌어 `consumer-restriction` whitelist(`default_preppers_order_consumer`) / jwt-auth 참조가 깨짐. **라우트만 이동, consumer 는 그대로.**
- buildspec 은 `k8s/$ENV/deployment.yaml` 만 apply(라우트 미포함) → 삭제한 default 라우트가 CI 로 되살아나지 않음. default Deployment 는 롤백용으로 유지.

**대상 라우트** (`gitops/apps/order-server/apisix/`, namespace 생략 → destination.namespace 주입):
| 파일 | 라우트 이름 | path | 인증 |
|---|---|---|---|
| apisix-route-pub.yaml | preppers-order-server-public-dev | `/pub/v1/order/*` | 없음 |
| apisix-route-pri.yaml | preppers-order-server-api-dev | `/pri/v1/order/*` | jwt-auth + Lua 헤더주입 |
| apisix-route-api.yaml | preppers-order-server-private-dev | `/pri/v1/order/customer-orders` | keyAuth + consumer-restriction |

**절차(실행 완료 2026-07-17, kubectl 수동)**:
```bash
CTX=supplies-eks-dev; GW=http://apisix-gateway.apisix.svc.cluster.local; H='Host: dev-pp-api.supp.fitness'
# 사전점검: preppers-dev 파드 healthz OK, endpoints 2개 / baseline: pub=200 pri=401 private=401
# Phase1(pub 리허설): 새 라우트 apply → default 삭제 → 200 확인
kubectl apply -n preppers-dev -f gitops/apps/order-server/apisix/apisix-route-pub.yaml --context=$CTX
kubectl delete apisixroute preppers-order-server-public-dev -n default --context=$CTX
# Phase2(pri+private): 동일
kubectl apply -n preppers-dev -f gitops/apps/order-server/apisix/apisix-route-pri.yaml -f gitops/apps/order-server/apisix/apisix-route-api.yaml --context=$CTX
kubectl delete apisixroute preppers-order-server-api-dev preppers-order-server-private-dev -n default --context=$CTX
# 검증(게이트웨이 경유): pub=200, pri=401(jwt), private=401(keyAuth) — baseline 과 동일
```

**결과**: 3개 라우트 preppers-dev 이동, default 제거. pub 200 / pri·private 401(인증 플러그인 활성) 확인.
**남은 것**: ① 매니페스트+Application(`preppers-order-server-dev-apisix.yaml`) push + apply(ArgoCD adopt) ② 유효 토큰으로 pri/private 200 스모크 테스트.

**롤백**: default 라우트 재적용 → preppers-dev 라우트 삭제.
```bash
kubectl apply -f k8s/dev/apisix-route-pub.yaml -f k8s/dev/apisix-route-pri.yaml -f k8s/dev/apisix-route-api.yaml --context=supplies-eks-dev
kubectl delete apisixroute preppers-order-server-public-dev preppers-order-server-api-dev preppers-order-server-private-dev -n preppers-dev --context=supplies-eks-dev
```

## 롤백 / 정리
```bash
# Application 삭제 (prune 로 생성 리소스 함께 제거됨). ExternalSecret 은 deletionPolicy=Retain 이라 Secret 은 남음.
kubectl delete application preppers-order-server-dev preppers-order-server-dev-prereqs \
  -n argocd-alan --context=supplies-eks-dev
```
기존 push 배포(CodeBuild + `k8s/*.yaml`)는 그대로 살아있으므로, 파일럿 실패해도 운영 영향 없음.

---

## 변경 로그
- 2026-07-15: runbook 생성. 스캐폴딩(`gitops/`) 완료, 파일럿 Application 초안 작성.
- 2026-07-15: 결정 A(이 repo)·B(External Secrets) 확정. Application 을 이 repo/브랜치 기준으로 수정,
  단계 2(ESO)·3(브랜치 push) 재작성. **1단계(ECR repo/tag) 진입 직전에서 중단.**
- 2026-07-16: **1단계 완료.** ECR repo 가 환경별 단일 repo(`dev`)임을 확인(서비스는 태그 접두사로 구분),
  `values.yaml` `image.repository`=`.../dev`, `values-dev.yaml` `image.tag`=`preppers-order-dev-0im1wuil` 확정.
  YAML 따옴표 스타일 통일(숫자 오인 문자열→더블쿼트). `helm template` 렌더로 image 검증. context=`supplies-eks-dev` 기입.
- 2026-07-16: **2단계 매니페스트 작성.** 클러스터 조사(ESO 설치·ClusterSecretStore·Pod Identity·platform-iac 소유 확인).
  결정 D(prereqs = 이 repo GitOps 임시) 추가. `gitops/apps/order-server/prereqs/` 4개 + 2번째 Application 작성.
  발견: 🔴 live env 주석에 평문 DB_PASSWORD 노출(로테이션 권장), ⚠️ PREPPERS_ORDER_DB_NAME drift(prpers_order). 둘 다 별도 트랙.
  다음: prereqs dry-run 검증 → 3단계 push.
- 2026-07-16: **파일럿 완료(2~5단계).** prereqs namespace-agnostic 전환(ns=destination.namespace 단일 소스),
  dry-run 5/5 통과, 브랜치 push. SSH deploy key 로 repo credential(`repo-preppers-order-server`) 등록.
  결정 C=임시 `default`(preppers AppProject 미존재). 두 Application 적용 → **모두 Synced/Healthy** 확인.
  문서화: 네임스페이스 전략 / 향후 이관 트랙 / Application 2분할 이유 섹션 추가.
- 2026-07-17: **APISIX 실트래픽 컷오버(무중단).** order 라우트 3개(pub/pri/private)를 default → preppers-dev 로 이동
  (새 라우트 apply→검증→default 삭제 순, 다운타임 0). consumer 는 default 유지(글로벌 `<ns>_<name>` 규칙 때문).
  매니페스트 `gitops/apps/order-server/apisix/` 3개 + Application `preppers-order-server-dev-apisix.yaml` 작성(커밋, push/apply 대기).
  검증: pub=200 / pri=401(jwt) / private=401(keyAuth) baseline 과 동일. "APISIX 컷오버" 섹션 추가.
