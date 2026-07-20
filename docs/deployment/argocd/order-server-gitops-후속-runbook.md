# order-server GitOps 후속 Runbook (TECH-147)

> 목적: **파일럿 이후 남은 작업**만 추려 이어서 진행하는 문서.
> 파일럿(스캐폴딩~APISIX 컷오버)은 완료 → [order-server-gitops-파일럿-runbook.md](./order-server-gitops-파일럿-runbook.md) 참고.
> 이 문서는 진행하면서 계속 갱신한다. **중단해도 아래 "현재 상태"만 보면 이어서 가능.**

---

## ⭐ 현재 상태 (여기부터 이어서)

- **✅ 컷오버 완료 (2026-07-20)**: platform-gitops `main` 이 이제 **단일 배포 소스**. 부트스트랩(작업 0)~CI 전환(작업 3)까지 완료:
  - repo credential 등록(`repo-platform-gitops`, 전용 deploy key `~/.ssh/argocd_platform_gitops`) + `root.yaml` bootstrap → order Application 3개 모두 adopt, **Synced/Healthy**.
  - **도메인별 구조로 재설계**: `argocd/apps/<domain>/`, `apps/<domain>/<service>/` (domain = `preppers` | `gymboxx`). root 는 `recurse: true`.
  - 스모크 테스트: pub=200 / 무인증 401 / API key 인증 통과 확인.
  - **독립적 CI/CD (옵션 B)**: 이 repo 의 [`image-bump.yml`](../../.github/workflows/image-bump.yml) 워크플로우로 values bump (workflow_dispatch). no-op 가드 검증 완료. 옛 repo buildspec 은 **develop 에 bump 블록이 원래 없어서 수정 불필요**했음.
- **옛 repo(`preppers-order-server`) 잔여물 — 의도적 보존**:
  - 파일럿 브랜치 `feature/TECH-147/argocd-chart` (bump 블록 + gitops/ 포함) — 죽은 브랜치지만 이력용 보존. 로컬 커밋 `be4539c` push 금지.
  - ArgoCD 옛 credential `repo-preppers-order-server` — 미사용, 정리 대상(선택).
- **✅ 작업 4·6 완료 (2026-07-20)**: kds 온보딩(preppers-dev 공유, 무중단 라우트 컷오버) + **shared ArgoCD 승격**(argocd-alan→argocd, TF, 무중단 — 워크로드 재생성 0). ArgoCD ns 는 이제 **`argocd`**.
- **🔶 작업 5 진행 중 (2026-07-20)**: preppers-cluster 에 ArgoCD **컨트롤플레인 설치 완료**(빈 상태, 부트스트랩 전). preppers prod 워크로드는 아직 `default` ns 서빙 중. platform-iac argocd.tf 는 **커밋/PR 대기**(feature/argocd-apply).
- **✅ 작업 8 완료 (2026-07-20)**: ArgoCD GitHub webhook 을 **IaC(argocd.tf)로 구현** — dev. `/api/webhook` 라우트(APISIX)+ `configs.secret.githubSecret`(random_password) + ApisixUpstream(https). 폴링(3분) → push 즉시 sync.
- **🔶 작업 9 진행 중 (2026-07-20)**: CI 배포 자동화(ArgoCD Image Updater, 모델 C pull). GitOps 애노테이션 초안 + platform-iac(IRSA/helm) 작성 완료, **apply 전**(alan IAM 권한 + deploy key write + chart 검증 대기).
- **dev CI 현황**: order-server=`aecut2io`(dotenv 수정 정상 빌드), kds live. **수동 image-bump.yml 은 태그 오입력 사고 다발** → 자동화(작업 9)로 대체 예정. 수동 시 함정: `image_tag` 는 **전체 태그** `preppers-order-dev-<hash>`(prefix 포함), 최신 정상 태그는 **deploy spec 이 아닌 default ns 의 Running 파드 이미지**로 확인.
- **바로 다음 할 일**: 작업 9 활성화(IAM 권한 해소 → IaC apply → 애노테이션 push) 또는 작업 5 부트스트랩(preppers 스코프 root — values-prod/prereqs/라우트/결정 E·F 선행).

---

## 확정된 값 / 컨텍스트

| 항목 | 값 |
|---|---|
| dev EKS 클러스터 / context | `supplies-eks-dev` (arn: `...:699016088228:cluster/supplies-eks-dev`) |
| ArgoCD 네임스페이스 | `argocd` (2026-07-20 argocd-alan 에서 승격, TF 소유) |
| ArgoCD UI 접속 | `kubectl port-forward svc/argocd-server -n argocd 8081:443` → `https://127.0.0.1:8081` |
| 워크로드 네임스페이스 | `preppers-dev` (기존 `default`) |
| **GitOps repo (단일 소스)** | `suppliesfitness/platform-gitops` (mono-gitops, targetRevision `main`) |
| repo credential | Secret `repo-platform-gitops` (**argocd** ns) — deploy key `~/.ssh/argocd_platform_gitops` (passphrase 없음, GitHub deploy key 등록됨) |
| 옛 repo | `suppliesfitness/preppers-order-server` — 파일럿 브랜치 이력용 보존, 실 CI 는 `develop` |
| APISIX 게이트웨이(내부) | `http://apisix-gateway.apisix.svc.cluster.local` (Host: `dev-pp-api.supp.fitness`) |

**platform-gitops 컨트롤플레인 (도메인별 구조, 2026-07-20 재설계)**
| 리소스 | 파일 | 역할 |
|---|---|---|
| root app-of-apps | `argocd/bootstrap/root.yaml` | 최초 1회 apply → `argocd/apps/` **recurse** 전체 관리 |
| ApplicationSet | `argocd/apps/preppers/workloads-appset.yaml` | 차트 앱 생성(order 활성, **kds 주석=TODO**) |
| prereqs Application | `argocd/apps/preppers/order-server-prereqs.yaml` | order ns 레벨 부속 (path=`apps/preppers/order-server/prereqs`) |
| apisix Application | `argocd/apps/preppers/order-server-apisix.yaml` | order 라우트 (path=`apps/preppers/order-server/apisix`) |
| AppProject | `argocd/projects/{preppers,gymboxx}-appproject.yaml` | TECH-145 대기(현 project=default) |
| CI (values bump) | `.github/workflows/image-bump.yml` | workflow_dispatch 로 `apps/preppers/<service>/values-<env>.yaml` 갱신 |

> 도메인 규칙: `argocd/apps/<domain>/` + `apps/<domain>/<service>/` (domain=`preppers`|`gymboxx`). 새 도메인 = 디렉토리 + AppProject 추가.
> ⚠️ Application `source.path` 는 도메인 경로 포함 필수 — 구조 변경 시 함께 갱신(경로 불일치 → Unknown/ComparisonError).

---

## 열린 결정 (합의 대기 — 진행 전 platform-iac 소유자와 합의 필요)

> 아래는 파일럿에서 **편의상 임시로 당긴 것**이지 확정이 아니다. main/prod 승격 전 반드시 해소.

| # | 결정 | 현재(임시) 상태 | 쟁점 / 근거 |
|---|---|---|---|
| E | **consumer 소유**를 GitOps 로 넣을까 | 둘 다 **수동 kubectl**(소유 가장 약함). `preppers-order-consumer` source=`k8s/dev/apisix-consumer.yaml`, `preppers-backend`는 이 repo에 없음 | 원칙상 k8s 객체=GitOps 영역이나 route 처럼 단순이동 불가: ① `preppers-backend`는 **order 소유 아님**(공유, auth 도메인 추정) → order GitOps 편입은 경계 침범 ② `<ns>_<name>` 규칙상 `preppers-order-consumer`를 preppers-dev 로 옮기면 whitelist(`default_preppers_order_consumer`) 깨짐 → default ns 유지 또는 whitelist 동시 수정 필요. **route 컷오버와 분리된 별도 결정.** |
| F | **prereqs(env ConfigMap 등) 최종 소유** = TF vs GitOps | `default/env`=**terraform** 소유(label `managed-by: terraform`). 파일럿이 `preppers-dev/env`로 **정적 복제**해 ArgoCD 관리(결정 D "임시") | ConfigMap 소유를 TF→GitOps 로 옮기는 **합의 없음**. 임시 복사본이라 TF가 원본 고쳐도 preppers-dev 는 안 따라옴 → **divergence 리스크**. 분석 문서 권장=Option B(하이브리드→prereqs GitOps 유지)지만 *제안이지 합의 아님*. **합의 전까지 이중 소유 금지 / GitOps 소유 확장 중단.** → [platform-iac-gitops-전환-분석.md](./platform-iac-gitops-전환-분석.md) §10 |

---

## 남은 작업

진행 단계: `[x]`=완료 `[ ]`=대기

```
[x] 0. platform-gitops 부트스트랩 (push + repo cred 등록 + root.yaml apply + order adopt 검증)
[x] 1. 옛 repo pilot → platform-gitops 컷오버 (Application 소스 재지정) + 원본 gitops/ 정리
[x] 2. pri/private 유효 토큰 스모크 테스트 (200 확인)
[x] 3. buildspec 전환 — **독립적 CI/CD** (preppers-order-server 기존 유지 + platform-gitops GitHub Actions)
[x] 4. shared ArgoCD 구축 (argocd-alan 개인 → argocd, TF 설치) — prod 전 필수
[ ] 5. main 승격 / prod 스탠드업 (결정 E/F + TECH-145 선행)
[x] 6. kds 온보딩 (ns=preppers-dev 공유 / redis·polling 처리 / 라우트 컷오버 완료)
[ ] 7. 별도 트랙: DB_PASSWORD 로테이션, PREPPERS_ORDER_DB_NAME drift 정합화, dotenv 빌드결함(전달됨)
[x] 8. ArgoCD GitHub webhook (IaC argocd.tf 로 구현 — dev)
[~] 9. CI 배포 자동화 (ArgoCD Image Updater) — GitOps 초안 + IaC 작성, IAM 권한/deploy key write/chart 검증 대기
```

### 0. platform-gitops 부트스트랩 ⬜  ← 지금 여기
```bash
cd /Users/swkim/workspace/supplies/platform-gitops
git add -A && git commit -m "chore: order-server 이관 + 공용차트 + argocd 컨트롤플레인 + kds skeleton"
git push origin main
# ArgoCD 에 platform-gitops repo credential(SSH) 등록 (옛 repo 것과 별개)
# root app-of-apps 부트스트랩
kubectl apply -f argocd/bootstrap/root.yaml --context=supplies-eks-dev
# 검증: ApplicationSet 이 preppers-order-server-dev 생성 → 기존 preppers-dev 리소스 adopt(변경 0)
kubectl get applicationset,application -n argocd-alan --context=supplies-eks-dev
```
> ⚠️ 옛 repo의 pilot Application 3개가 아직 살아있으면 **같은 리소스를 두 Application이 관리하는 충돌** 가능.
>   컷오버(작업 1)에서 옛 Application 제거 ↔ 새 Application 활성화를 원자적으로. 리허설은 옛 것 먼저 삭제 후 새 것 sync.

### 3. buildspec 전환 — 독립적 CI/CD 구축 (옵션 B) ⬜

**목표**: preppers-order-server(빌드)와 platform-gitops(배포)를 **독립적으로 분리**.
- preppers-order-server: 기존 buildspec 유지 (ECR push만)
- platform-gitops: **자체 GitHub Actions** (이미지 변경 감지 → values bump → ArgoCD 배포)

**구조:**
```
preppers-order-server (빌드)
  └─ CodeBuild (buildspec.yml)
     ├─ npm build + docker build
     ├─ ECR push (tag=$IMAGE_TAG-$ENV-$RANDOM)
     └─ kubectl apply k8s/$ENV/deployment.yaml (기존 default 배포, 유지)

platform-gitops (배포)
  └─ GitHub Actions (새로 추가)
     ├─ ECR 이미지 변경 감지 (또는 webhook)
     ├─ sed: values-<env>.yaml image.tag 갱신
     ├─ git commit & push
     └─ ArgoCD 자동 감시 → 배포
```

**장점:**
- ✅ 두 repo 독립적 관리 (결합도 낮음)
- ✅ 배포 로직이 platform-gitops에 중앙화
- ✅ buildspec 수정 불필요 (기존 유지)
- ✅ GitHub Actions는 플랫폼 표준 (CodeBuild 대비 유지보수 쉬움)

---

#### 3-1. GitHub Actions 워크플로우 생성 ✅

**위치**: [`.github/workflows/image-bump.yml`](../../.github/workflows/image-bump.yml) (작성 완료 — 실 구현은 이 파일이 단일 소스)

**동작 (수동 트리거, workflow_dispatch):**
1. Actions 탭 또는 gh CLI 로 실행: `service`(order-server/kds-server) + `environment`(dev/prod) + `image_tag` 입력
2. `yq` 로 `apps/preppers/<service>/values-<env>.yaml` 의 `.image.tag` 갱신
   - ⚠️ sed 정규식 대신 **yq** 사용 — values 의 `tag:` 는 `image:` 아래 중첩이라 `s/image.tag:.*/` 패턴은 매치 안 됨
3. git commit & push (main) — 태그 변경 없으면 push 생략
4. ArgoCD 폴링(~3분)이 감지 → 배포

```bash
# gh CLI 실행 예
gh workflow run image-bump.yml \
  -f service=order-server -f environment=dev -f image_tag=preppers-order-dev-abc12345
```

**안전장치 (구현에 반영됨):**
- `concurrency` 그룹으로 같은 service+env 동시 실행 방지 (push 경합 예방)
- GITHUB_TOKEN push 는 다른 워크플로우를 재트리거하지 않음(GitHub 기본 동작) → 루프 없음, `[skip ci]` 불필요
- values 파일 미존재 시 명시적 실패

**향후 자동화 (선택)**: 서비스 repo 빌드 파이프라인(CodeBuild)이 빌드 끝에
`repository_dispatch` 또는 `gh workflow run` 으로 이 워크플로우를 호출 — 단방향(빌드→배포 트리거) 호출이라
git cross-repo push 방식보다 결합도 낮음. prod 승격 전 검토.
→ **2026-07-20 결정: pull 방식(ArgoCD Image Updater)으로 대체 추진 = 작업 9.** 아래 수동 함정 때문.

> ⚠️ **수동 bump 실전 함정 (2026-07-20 다발)**:
> - `image_tag` 는 **전체 태그**여야 함: `preppers-order-dev-<hash>` (prefix 포함). hash 만(`e9hj83j0`) 넣으면 이미지 `dev:e9hj83j0` 로 조합돼 ECR 에 없음 → ImagePullBackOff. 실제로 `9hj83j0`(오타)·`e9hj83j0`(prefix 누락) 로 세 번 사고.
> - 워크플로우는 **ECR 존재 검증을 안 함** → 없는 태그도 커밋/push 성공, 배포 단계에서야 실패. 롤백 = `git revert` (라이브는 selfHeal 이 옛 파드 유지해 무중단).
> - **최신 정상 태그 확인은 `kubectl get deploy ... -o=...spec.image`(deploy spec) 가 아니라 `kubectl get pod ...`(실제 Running 파드 이미지)로.** default 는 매 빌드 자동배포라 최신이지만, 불량 빌드면 desired 만 최신이고 Running 은 옛 정상 파드일 수 있음(e9hj83j0 사례).

---

#### 3-2. preppers-order-server buildspec 수정 ✅ (수정 불필요로 판명)

**확인 결과 (2026-07-20)**: GitOps bump 블록은 **파일럿 브랜치(`feature/TECH-147/argocd-chart`)에만** 존재.
실 CI 가 쓰는 **`develop` 의 buildspec 에는 원래 없음** → 옵션 B 구조가 이미 성립, 수정할 것 없음.

```
develop (실 CI): ECR push + kubectl apply k8s/dev/ (default 배포) — 그대로
파일럿 브랜치: bump 블록 있으나 죽은 브랜치(ArgoCD 미참조) — 이력용 보존, develop 에 머지 금지
```

> ⚠️ 유일한 규칙: **파일럿 브랜치를 develop 에 머지하지 말 것** (bump 블록이 딸려 들어옴).

---

#### 3-3. 통합 템플릿화 (ApplicationSet 확산) ⬜

현재는 order-server dev만.
향후 kds-server, order-server prod 추가 시:

```yaml
# argocd/apps/preppers/workloads-appset.yaml
generators:
  - list:
      elements:
        - service: order-server
          env: dev
          namespace: preppers-dev
        - service: order-server
          env: prod
          namespace: preppers-prod
        # - service: kds-server
        #   env: dev
        #   namespace: preppers-dev
```

→ GitHub Actions도 dev/prod 모두 지원하도록 확장

---

### 6. kds 온보딩 ✅ (2026-07-20 완료)

**확정된 결정:**
- **ns = preppers-dev 공유**: kds 가 쓰는 prereqs 3종(env ConfigMap/credentials Secret/pod-service-account SA)이 order 것과 **동일물** → 이미 준비돼 있었음. 신규 prereqs 0개.
- **kds-polling = 공용 차트 재사용**: 차트에 `service.enabled` 토글 + `podSecurityContext` 지원 추가(하위호환)로 수용. probe 는 기존 enabled 토글로 전부 off.
- **kds-redis = raw 매니페스트 개별 Application**(`kds-redis.yaml`): 이미지 고정(redis:7-alpine, CI bump 없음)이라 차트 불필요.
- **apisix 라우트 = order 패턴 그대로**(`kds-server-apisix.yaml`): pri 라우트의 SSE timeout(600s)/Lua 헤더주입 원본 유지.

**컷오버 절차 (order 와 동일 패턴, 무중단):**
Phase A 워크로드 3종 preppers-dev 기동/검증(redis PONG + polling cursor 키 생성 확인) →
Phase B 라우트 apply → 겹침 구간 baseline 대조(pub=404/pri=401 동일) → default 라우트 삭제 → 단독 서빙 재검증.
겹침 구간 polling 이중 실행은 각자 자기 ns redis 에 publish 라 간섭 없음.

**남은 것:**
- default ns 의 kds 워크로드 3종(server/polling/redis)은 **롤백용 잠정 유지** — 안정 확인 후 삭제(라우트가 없어 트래픽은 0, polling 만 DB 폴링 지속).
- kds CI 는 order 와 동일한 옵션 B 잠정 상태: CodeBuild 는 default 배포 유지, preppers-dev 반영은 `image-bump.yml`(kds-server/kds-polling 옵션) 수동 실행.
- 롤백: kds repo `deploy/k8s/platform/apisix/kds/dev/` 라우트를 default 에 재적용 → preppers-dev 라우트/Application 삭제.

### 4. shared ArgoCD 승격 (argocd-alan → argocd) ✅ (2026-07-20 dev 완료)

> **실행 결과**: 무중단 성공. 워크로드 재생성 0(파드명/AGE/restart 불변), 게이트웨이 baseline 일치.
>
> **🔑 적용 범위**: 아래 함정 1·2 는 **기존 ArgoCD 를 헐어 옮길 때만**(dev argocd-alan→argocd 같은 마이그레이션) 해당.
> **신규 prod ArgoCD 스탠드업(작업 5)은 destroy 가 없으므로 함정 1·2 불필요** — 깨끗한 클러스터에 helm 설치 + 부트스트랩만.
> 함정 3(공유 state `-target`)은 신규 스탠드업에도 해당(스택 공유 시).
>
> **⚠️ 실전 함정 1 — Application finalizer (워크로드 삭제 위험, *마이그레이션 시만*)**: ApplicationSet 생성 앱에
> `resources-finalizer.argocd.argoproj.io` 가 컨트롤러에 의해 자동 부여됨(템플릿엔 없음, 제거해도 컨트롤러가 재부여).
> 이게 있으면 ns destroy 시 Application 삭제가 **워크로드 cascade prune** 유발 → 라이브 파드 삭제/ns Terminating 교착.
> **선처리**(destroy 전 필수):
> ```bash
> NS=argocd-alan   # 헐 대상 ArgoCD 의 ns
> # 1) 컨트롤러 0 (finalizer 재부여 + cascade prune 둘 다 차단)
> kubectl scale statefulset argocd-application-controller  -n $NS --replicas=0 --context=$CTX
> kubectl scale deployment  argocd-applicationset-controller -n $NS --replicas=0 --context=$CTX
> # 2) finalizer 있는 앱을 동적으로 찾아 제거 (컨트롤러 0이라 유지됨)
> for a in $(kubectl get application -n $NS --context=$CTX \
>       -o jsonpath='{range .items[?(@.metadata.finalizers)]}{.metadata.name}{"\n"}{end}'); do
>   kubectl patch application $a -n $NS --type merge -p '{"metadata":{"finalizers":null}}' --context=$CTX
> done
> # 3) 전 앱 finalizers 빈값 확인 후 진행
> kubectl get application -n $NS --context=$CTX -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.finalizers}{"\n"}{end}'
> ```
> **⚠️ 실전 함정 2 — CRD 소유권 (helm 재설치 실패)**: argo-cd 차트 CRD 3개는 resource-policy=keep 이라
> ns destroy 후에도 남고, 옛 `meta.helm.sh/release-namespace: argocd-alan` 주석 때문에 새 릴리스가
> import 실패(`Error: ... cannot be imported ... must equal "argocd"`). **apply 중 이 에러 나면**:
> ```bash
> kubectl annotate crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io \
>   meta.helm.sh/release-namespace=argocd --overwrite --context=$CTX
> # 그 후 terraform apply 재실행 (helm_release.argocd 만 재시도)
> ```
>
> **⚠️ 함정 3 — 공유 state drift**: `terraform apply` 는 스택 전체 대상 → fluent-bit 등 타 리소스 미적용 drift 가
> 같이 쓸려감. **반드시 `-target` 으로 argocd 리소스만 스코프**(아래 명령). drift 자체는 담당자에게 별도 공유.
> ```bash
> terraform apply -target=kubernetes_namespace.argocd_alan -target=helm_release.argocd_alan \
>                 -target=kubernetes_namespace.argocd -target=helm_release.argocd
> ```
> **UI 접속**: 새 포트포워딩 필요 — `kubectl port-forward svc/argocd-server -n argocd 8081:443` (옛 argocd-alan 대상 터널은 죽음).

#### (참고) 원래 설계 절차 ⬜  ← prod 전 필수

**목표**: 개인 파일럿 컨트롤플레인(`argocd-alan`)을 공용 인스턴스(`argocd`)로 승격. TF(platform-iac) 소유.

> **토폴로지 결정 = 모델 A (클러스터별 in-cluster ArgoCD)** 확정. 각 클러스터가 자기 ArgoCD 로 자기 워크로드만 관리
> (`destination.server: https://kubernetes.default.svc`). 여기 "shared"=**소유(개인→팀)** 축이지 크로스클러스터 허브 아님.
> blast radius 격리(dev 사고가 prod 에 안 닿음) + 재작업 없음이 근거. 허브(모델 B)는 안티패턴(특히 prod 에 허브 배치=전 환경이 prod 종속).
> → **prod 는 작업 5에서 동일 argocd.tf 를 prod 스택(`stacks/eks/<prod-cluster>/k8s/`)에 복제해 별도 ArgoCD 스탠드업.**

**소유/전제**: ArgoCD 인스턴스 = 인프라 리소스 → platform-iac 소유. argocd.tf 는 `feature/argocd-test` 브랜치
(`platform-iac/stacks/eks/supplies-eks-dev/k8s/argocd.tf`)에서 ns `argocd-alan`→`argocd` 로 수정 완료(리소스 주소도 `argocd` 로).

**핵심 원리**:
- ns rename = **Terraform destroy(argocd-alan) + create(argocd)** = 컨트롤플레인 교체(한 apply 안에서 순차 → **두 ArgoCD 동시 관리 충돌 없음**).
- 워크로드(order/kds)는 `preppers-dev`·`default` ns → argocd-alan ns 삭제와 **무관, 계속 서빙**(root rename 때 검증한 orphan 패턴).
- 새 argocd 는 **빈 상태로 시작** → apply 후 platform-gitops **재부트스트랩 필수**(작업 0의 반복, ns 만 argocd).

**절차**:
```bash
# ── [platform-iac] TF apply (당신 실행) ──────────────────────────────
cd platform-iac/stacks/eks/supplies-eks-dev/k8s
terraform plan    # 기대: helm_release.argocd_alan + ns destroy, helm_release.argocd + ns create
terraform apply   # 컨트롤플레인 교체. preppers-dev 워크로드는 무영향(다른 ns)

# ── [검증] 새 argocd 기동 ────────────────────────────────────────────
kubectl get pods -n argocd --context=supplies-eks-dev            # argocd-* Running
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d                     # admin 비번

# ── [platform-gitops] 재부트스트랩 (ns=argocd) ──────────────────────
# 1) repo credential 재등록 (deploy key 재사용, ns 만 argocd)
kubectl create secret generic repo-platform-gitops -n argocd \
  --from-literal=type=git \
  --from-literal=url=git@github.com:suppliesfitness/platform-gitops.git \
  --from-file=sshPrivateKey=/Users/swkim/.ssh/argocd_platform_gitops \
  --dry-run=client -o yaml | kubectl apply -f - --context=supplies-eks-dev
kubectl label secret repo-platform-gitops -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite --context=supplies-eks-dev
# 2) root.yaml 의 namespace 2곳(metadata.namespace + destination.namespace) argocd-alan→argocd 수정 → commit/push
# 3) root apply
kubectl apply -f argocd/bootstrap/root.yaml --context=supplies-eks-dev
# 4) 검증: 7개 앱 adopt Synced/Healthy (워크로드 재생성 0)
kubectl get application -n argocd --context=supplies-eks-dev
```

> ⚠️ **AppProject(argocd/projects/*)의 `namespace: argocd-alan` 도 argocd 로** — root 가 이들을 관리하게 되면 함께 수정.
> ⚠️ root.yaml 외에 argocd/apps/ 매니페스트는 ns 하드코딩 없음(이미 정리) → root.yaml + AppProject 만 손대면 됨.
> **롤백**: argocd.tf revert → apply(argocd-alan 재생성) → 거기로 재부트스트랩. 워크로드는 전 과정 무영향.
> **PR**: 검증 완료 후 platform-iac `feature/argocd-test` → `main` PR.

### 5. main 승격 / prod 스탠드업 🔶 (진행 중 — preppers-cluster 컨트롤플레인 설치 완료)

> **✅ 2026-07-20 진행분**: preppers-cluster 에 **ArgoCD 컨트롤플레인 설치 완료**(빈 상태, 7개 파드 Running).
> - platform-iac: `stacks/eks/preppers-cluster/k8s/argocd.tf` **신규 생성**(모델 A, ns=argocd) + `variables.tf` 에 `argocd_chart_version` 추가.
>   → **⚠️ 아직 커밋/PR 안 함** (feature/argocd-apply working tree). 백엔드는 `init -reconfigure` 필요했음(락 설정 차이, state 위치 동일).
> - `terraform apply -target=kubernetes_namespace.argocd -target=helm_release.argocd` (create-only, fluent-bit drift 회피).
> - **신규 설치라 finalizer/CRD 함정 없음.** preppers prod 워크로드는 아직 `default` ns 에서 그대로 서빙(무관).
> - **남은 것(부트스트랩)**: repo credential 등록 + preppers 스코프 root(`path: argocd/apps/preppers`) apply. 단, 실 워크로드 배포는
>   values-prod / prereqs(preppers-prod ns) / apisix 라우트 / consumer / 결정 E·F 선행 필요 → **다음 단계**.

**⚠️ prod 는 도메인별 클러스터 분리** (2026-07-20 확인):
| env | 클러스터 | 도메인 |
|---|---|---|
| dev | `supplies-eks-dev` | preppers-dev (gymboxx-dev 여부 미정) |
| prod | `preppers-cluster` | preppers-prod |
| prod | `eks-prod` | gymboxx-prod |

**클러스터 스코핑 원칙 (모델 A) — "preppers-cluster 엔 preppers 만"**:
- 각 클러스터 ArgoCD 는 **자기 도메인 슬라이스만** 부트스트랩해야 함. 현재 `platform-root` 는 `path: argocd/apps`(전체 recurse)라 그대로 쓰면 preppers-cluster 가 gymboxx 까지 자기 클러스터(in-cluster)에 배포하려 함 → **틀림**.
- **해법**: preppers-cluster 용 root 는 `path: argocd/apps/preppers` 로 **도메인 스코프**(전체 recurse 아님). 도메인 디렉토리(`argocd/apps/<domain>/`)가 곧 스코핑 경계. gymboxx-prod root 는 `argocd/apps/gymboxx`.
- 즉 클러스터별 bootstrap root 를 분리(`argocd/bootstrap/<cluster>-root.yaml`). in-cluster destination 이라 크로스클러스터 credential 불필요 + blast radius 격리(preppers-cluster ArgoCD 는 gymboxx 클러스터 접근 자체 불가).
- ⚠️ **전체 멀티클러스터 디렉토리 리팩터(clusters/ 재편, dev 의 gymboxx 수용 등)는 지금 결정 보류** — prod 착수 시점에 확정. 지금은 "preppers-cluster=preppers 슬라이스만" 원칙만 고정.

**그 외 선행**:
- `spec.project` 임시 `default` → TECH-145 `preppers`/`gymboxx` AppProject 확정 시 교체(결정 C).
- 결정 E(consumer 소유) / F(prereqs TF vs GitOps) 해소 선행.
- `argocd/apps/preppers/workloads-appset.yaml` 에 prod elements(`env: prod`, `ns: preppers-prod`) 추가 + `apps/preppers/<svc>/values-prod.yaml` 확정.
- prod ArgoCD 는 `preppers-cluster` 스택(`stacks/eks/preppers-cluster/k8s/`)에 argocd.tf 복제해 신규 설치(마이그레이션 아님 → 함정 1·2 불필요).
- (검토) apisix 라우트를 차트 `apisix.enabled` 토글로 편입 — 지금은 raw 유지(Lua/공유 consumer 복잡도 때문).

### 7. 별도 트랙 (보안/정합성) ⬜
- 🔴 live `default/env` 주석의 평문 `DB_PASSWORD` 로테이션 + 주석 정리.
- ⚠️ `PREPPERS_ORDER_DB_NAME` drift(`prpers_order` vs config.tf `preppers_order`) 실 DB명 확인 후 정합화.
- 🔴 **preppers-order-server 빌드 결함 (2026-07-20, 팀 전달됨)**: 이미지 `preppers-order-dev-e9hj83j0` 가
  `Cannot find module 'dotenv/config'` 로 부팅 크래시(CrashLoopBackOff) — **default·preppers-dev 공통**(환경 무관 = 이미지 결함).
  원인: 프로덕션 이미지 node_modules 에 `dotenv` 없음(devDependencies 인데 `npm ci --omit=dev`/prune 로 탈락 추정, 또는 멀티스테이지 누락).
  수정안: dotenv 를 `dependencies` 로 이동, 또는 k8s 는 env 를 ConfigMap/Secret 로 주입하므로 엔트리포인트의 `dotenv/config` 를 로컬 전용 가드/제거.
  → 수정 빌드 `aecut2io` 확인(정상). ⚠️ 이 결함이 남으면 **default 신규 롤아웃도 계속 실패**(작업 9 Image Updater 활성 전 "newest=정상" 전제와 직결).

### 8. ArgoCD GitHub webhook ✅ (2026-07-20 dev 완료 — IaC)

**구현 위치**: platform-iac `stacks/eks/supplies-eks-dev/k8s/argocd.tf` (webhook 을 GitOps 아님 **IaC 로 소유** — ArgoCD 인스턴스 계층이므로).
- `random_password.argocd_webhook` → `helm_release.argocd` 의 `configs.secret.githubSecret` 로 주입(argocd-secret 의 `webhook.github.secret`).
- `ApisixUpstream`(argocd-server, scheme=https — argocd-server 는 secure 모드라 https 필수) + `ApisixRoute`(host `dev-pp-api.supp.fitness`, path `POST /api/webhook`, backend argocd-server:443).
- `output "argocd_webhook_github_secret"` (sensitive) — GitHub webhook Secret 칸에 넣을 값. `terraform output -raw argocd_webhook_github_secret`.
- payload URL = `https://dev-pp-api.supp.fitness/api/webhook` (ALB ACM 443).

**왜 IaC(GitOps 아님)**: 3요소(secret/라우트/GitHub hook) 모두 **ArgoCD 인스턴스 구성**이지 제품 워크로드가 아님. GitOps 로 넣으면 ① 자기참조(자기 sync 가속 장치를 자기가 관리) ② secret 을 git 에 못 둠(SOPS 등 필요). helm chart 가 `configs.secret.githubSecret` 를 네이티브 값으로 노출 → IaC 가 마찰 없음.

**per-repo 동작**: 엔드포인트 1개가 **모든 repo 처리**. ArgoCD 가 payload 의 repoURL+ref 를 자기 Application 들의 `source.repoURL`+`targetRevision` 과 대조해 매칭 앱만 refresh. 여러 repo 에 등록해도 됨. **단 secret 은 전 repo 동일**해야 함(ArgoCD 의 단일 `webhook.github.secret` 로 HMAC 검증 → 불일치 repo 는 401). ssh/https URL 형태 무관(정규화 매칭). 인스턴스별(dev vs preppers-cluster)로는 payload URL 이 달라 각각 등록.

> preppers-cluster(prod) webhook 은 작업 5 실배포 시 동일 패턴으로 argocd.tf 에 추가.

### 9. CI 배포 자동화 — ArgoCD Image Updater 🔶 (2026-07-20 착수, 미활성)

**동기**: 옵션 B(수동 `image-bump.yml`)의 "image→git 다리"가 **수동**이라 컷오버 후 새 빌드가 live(preppers-dev)에 자동 반영 안 됨. default(레거시 CI 자동배포)만 최신이고 preppers-dev 는 옛 태그에 정체 → divergence. 수동 bump 는 태그 오입력 사고 다발(작업 3-1 함정 박스).

**모델 C (pull)**: Image Updater 가 ECR 폴링 → 최신 태그를 git(`values-<env>.yaml`)에 write-back → ArgoCD 배포. **"build 는 빌드만, gitops 가 관찰·반영"** 실현. build↔deploy 결합 0. (참고: ArgoCD 는 git 만 관찰하지 ECR 을 안 봄 → 이 다리가 없으면 자동 아님.)

**소유 계층**: ArgoCD 인스턴스와 동일 = **IaC(platform-iac)**. GitOps repo 는 대상/전략 애노테이션만.

**작성 완료 (미apply·미활성)**:
- **[platform-gitops]** `argocd/apps/preppers/workloads-appset.yaml` — 서비스별 Image Updater 애노테이션. 각 element 에 `imageTagPrefix` 추가, `newest-build` 전략, `git` write-back → `values-<env>.yaml`. **컨트롤러 미설치라 무동작.**
- **[platform-iac]** `stacks/iam/eks/supplies-eks-dev/argocd-image-updater.tf`(IRSA 역할 + ECR read 정책 + attachment) + `outputs.tf`(`argocd_image_updater_role_arn`); `stacks/eks/supplies-eks-dev/k8s/argocd-image-updater.tf`(helm_release: IRSA 주입 + ECR registry + authScripts + aws-cli initContainer) + `variables.tf`. **k8s 스택 `validate` 통과**, IAM 스택은 `init -reconfigure` 필요(락 설정 차이, state 위치 동일 — 작업 5와 동일).

**⚠️ 함정/주의**:
- **단일 ECR repo `dev` 를 전 서비스가 공유**(태그 접두사로만 구분) → **allow-tags 정규식이 서비스 격리의 유일 수단**. order=`preppers-order-dev-`, kds-server=`preppers-kds-server-dev-dev-`, kds-polling=`preppers-kds-polling-dev-dev-`. 느슨하면 order 가 kds/prod/consumer 태그를 집음.
- **newest-build 는 정상/불량 이미지 구분 못 함** → 불량 빌드도 최신이면 자동 배포(라이브는 옛 파드 유지=무중단이나 Degraded 재발). **안전망 = 빌드 파이프라인이 정상 이미지만 push**(작업 7 dotenv 결함이 선결).
- **chart value 키 + aws-cli 주입 검증**: 기본 image-updater 이미지에 aws-cli 없음 → initContainer 로 공유 볼륨에 설치 후 PATH 노출. `helm show values argo/argocd-image-updater --version <ver>` 로 `config.registries`/`authScripts`/`initContainers`/`volumes`/`extraEnv` 스키마 대조. 변수 default 버전(`0.12.1`)도 확인.

**블로커/전제**:
- 🔴 **`alan` 유저에 IAM 생성 권한 없음**(`iam:CreatePolicy` AccessDenied) → 관리자가 그룹에 관리형 정책 부여(스택 리소스 2개로 스코프) **또는 관리자가 IAM 스택 apply**. 개인 유저의 IAM 생성은 원칙상 지양.
- `repo-platform-gitops` deploy key 에 **GitHub write 권한** 부여(git write-back 용, 기존 read 키 재사용).

**활성화 순서**: ① IAM 스택 `init -reconfigure` + apply(role 생성) → ② k8s 스택 `apply -target=helm_release.argocd_image_updater`(fluent-bit drift 회피) → ③ 파드 Healthy·ECR 인증/registry ping 로그 확인 → ④ platform-gitops 애노테이션 push → order=`aecut2io`·kds 최신 자동 반영 → ⑤ dev 안정 후 prod(preppers-cluster) 확대. **수동 `image-bump.yml` 은 prod/수동 오버라이드용으로 유지.**

---

## 롤백 (APISIX 컷오버 되돌리기)
```bash
# default 라우트 재적용 → preppers-dev 라우트 삭제
kubectl apply -f k8s/dev/apisix-route-pub.yaml -f k8s/dev/apisix-route-pri.yaml -f k8s/dev/apisix-route-api.yaml --context=supplies-eks-dev
kubectl delete apisixroute preppers-order-server-public-dev preppers-order-server-api-dev preppers-order-server-private-dev -n preppers-dev --context=supplies-eks-dev
```
> Application 을 이미 apply 했다면 먼저 `kubectl delete application preppers-order-server-dev-apisix -n argocd-alan`(prune 로 라우트 제거) 후 default 재적용.

---

## 변경 로그
- 2026-07-20 (6): **작업 8 완료(webhook, IaC) + 작업 9 착수(CI 자동화, Image Updater) + dev CI 인시던트.**
  ① webhook: platform-iac argocd.tf 에 이미 구현됨 확인(secret/ApisixUpstream/ApisixRoute/output). IaC 소유 근거 정리(인스턴스 계층·자기참조 회피·secret in git 마찰). per-repo 동작·secret 동일 규칙 문서화.
  ② CI gap 발견: 수동 image-bump 라 컷오버 후 preppers-dev 가 옛 태그 정체(default 만 최신). **수동 bump 사고 다발**(`9hj83j0` 오타·`e9hj83j0` prefix 누락 → ImagePullBackOff, git revert 로 복구, 무중단). 최신 정상 태그는 Running 파드로 확인(deploy spec 아님).
  ③ **dotenv 빌드 결함**: `e9hj83j0` 가 `dotenv/config` 누락으로 CrashLoop(default·preppers-dev 공통) → preppers-order-server 팀 전달(작업 7). 최신 정상 빌드 `aecut2io` 로 수렴.
  ④ 작업 9: 모델 C(Image Updater, pull) 채택. GitOps 애노테이션 초안(workloads-appset.yaml) + platform-iac(IRSA/helm) 작성(k8s validate 통과). 블로커=alan IAM 권한/deploy key write/chart 검증. 단일 ECR repo·newest-build 불량빌드 함정 기록.
- 2026-07-20 (5): **작업 5 착수** — preppers-cluster 에 ArgoCD 컨트롤플레인 신규 설치(모델 A, argocd.tf 신규, `-target` create-only, 7파드 Running). 부트스트랩·prod 워크로드는 다음 단계. webhook 현황 정리(작업 8): 옛 argocd-alan webhook 은 승격으로 소멸, 현재 미설정(폴링으로 충분), stale output 은 full apply 시 정리.
- 2026-07-19: 후속 runbook 생성. 파일럿 완료(APISIX 컷오버 포함) 이후 남은 작업 5개 정리.
- 2026-07-20 (4): **작업 4 shared ArgoCD 승격 완료.** argocd-alan→argocd (TF `-target` apply, 무중단 — 워크로드 재생성 0). 실전 함정 2개 해결: ① Application finalizer(컨트롤러 자동 부여) → 컨트롤러 0 스케일 + finalizer 제거로 cascade prune 차단 ② CRD keep 정책 + 옛 release-namespace 주석 → CRD annotate 후 apply 재시도. fluent-bit drift 는 `-target` 으로 우회(담당자 공유 필요). repo cred/root.yaml ns=argocd 로 재부트스트랩 → 8앱 재adopt.
- 2026-07-20 (3): **작업 6 kds 온보딩 완료.** ns=preppers-dev 공유(prereqs 동일물 재사용), polling=차트 재사용(service.enabled/podSecurityContext 추가), redis=raw Application, 라우트 무중단 컷오버(baseline 대조 방식). ArgoCD 네임스페이스 하드코딩 제거(root.yaml 단일 소스화 — shared ArgoCD 이전 대비). default kds 워크로드는 롤백용 잠정 유지.
- 2026-07-20 (2): **root rename** `preppers-root` → `platform-root` (역할=전 도메인 관리, 이름 정합화). finalizer 없음 → 삭제해도 자식 orphan 유지 → 새 root 가 tracking-id 갱신하며 무중단 재adopt. UI 접속 이슈 해결(OpenLens 낡은 터널 — port-forward 재연결로 해결).
- 2026-07-20: **작업 0~3 완료.** ① 부트스트랩: git push + deploy key(`argocd_platform_gitops`) 등록 + root.yaml apply → order 3개 Application adopt(Synced/Healthy). 초기 credential 삽질 기록: passphrase 있는 키 불가, `argocd_alan.pub` 은 타 repo 에 이미 등록되어 "key is already in use" → 전용 키 신규 생성. ② **도메인별 구조 재설계**(preppers/gymboxx) — Application `source.path` 갱신 누락으로 ComparisonError 발생 후 수정. ③ 스모크 테스트: pub 200 / 무인증 401 / API key 인증 통과(400=인증 OK, 요청 형식 이슈). ④ **CI 옵션 B 확정**(cross-repo push 폐기): `image-bump.yml` 워크플로우 생성+검증. yq 재포맷이 no-op 가드를 뚫는 버그 발견 → 비교 후 sed 교체+yq 검증으로 수정. develop buildspec 은 bump 블록이 원래 없어 수정 불필요. 파일럿 브랜치는 이력용 보존(develop 머지 금지).
