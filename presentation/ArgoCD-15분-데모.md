# ArgoCD 작업 공유 — 15분 데모

> 목표: ArgoCD 자체를 길게 설명하기보다, **실제 주문/KDS 워크로드를 GitOps로 전환하면서 무엇을 만들었고 어떻게 동작하는지** 보여준다.
>
> 핵심 메시지: **배포 상태를 Git에 선언하면 ArgoCD가 클러스터를 그 상태로 계속 맞춘다.**

## 0. 데모에서 말할 현재 상태

### 완료

- 중앙 GitOps 저장소(`platform-gitops`)와 Helm 공유 차트 구성
- `ApplicationSet` 기반으로 주문 서버와 KDS 계열 앱 생성
- dev의 order-server와 KDS를 `preppers-dev` 네임스페이스에 배포
- APISIX 라우트를 무중단으로 전환하고 스모크 테스트
- 개인용 `argocd-alan`을 공용 `argocd`로 승격하면서 기존 워크로드 8개 재수용
- GitHub webhook을 IaC로 구성
- prod용 `preppers-cluster`에 ArgoCD 컨트롤 플레인 설치(7개 파드 Running)

### 진행 중 또는 미적용

- `AppProject` 격리: 설계 완료, 아직 앱은 `default` 프로젝트 사용
- ArgoCD Image Updater: 설계와 매니페스트 작성 완료, IAM 권한 문제로 미활성
- prod: ArgoCD 설치까지만 완료, GitOps 부트스트랩과 실제 워크로드 전환은 남음

이 구분은 발표 시작 때 먼저 말한다. 미완료 기능을 실제 동작하는 것처럼 보여주지 않는다.

---

## 1. 15분 진행표

| 시간 | 내용 | 화면 |
|---:|---|---|
| 0:00–1:00 | 문제와 목표 | 이 문서 또는 간단한 구조도 |
| 1:00–3:00 | GitOps 구조 설명 | `platform-gitops` 디렉토리 |
| 3:00–6:00 | ArgoCD 현재 상태 | ArgoCD UI의 앱 목록/트리 |
| 6:00–10:00 | Git 변경 → 자동 동기화 데모 | values 파일, Git, ArgoCD UI |
| 10:00–12:00 | self-heal 또는 diff 설명 | UI Diff / History |
| 12:00–14:00 | 실제 적용 범위와 얻은 것 | order/KDS 앱, APISIX 경로 |
| 14:00–15:00 | 한계와 다음 단계 | 미완료 3항목 |

질문 시간이 별도로 없다면 설명을 13분에 끝내고 2분을 질문에 남긴다.

---

## 2. 시작 멘트 — 1분

> “이번 작업의 목표는 배포 명령을 자동화하는 것만이 아니라, Git에 적힌 배포 상태를 기준으로 클러스터가 계속 수렴하도록 만드는 것이었습니다.
>
> 기존에는 빌드 파이프라인이 이미지를 만들고 클러스터에 직접 적용했습니다. 지금 구조에서는 빌드는 이미지를 만들고, 배포 설정은 GitOps 저장소에 남기며, ArgoCD가 그 변경을 가져가 적용합니다.
>
> 오늘은 구조를 짧게 설명하고, Git의 변경이 실제 클러스터 상태에 반영되는 흐름을 보여드리겠습니다.”

구조를 한 줄로 그린다.

```text
Application repo ──build──> ECR
                            │
                            ▼
GitOps repo ──webhook/poll──> ArgoCD ──reconcile──> EKS
   (원하는 상태)                              (실제 상태)
```

설명 포인트:

- ArgoCD가 보는 기준은 ECR 자체가 아니라 **GitOps 저장소**다.
- webhook은 Git 변경을 빨리 알릴 뿐, 이미지 태그를 Git에 써 주는 기능은 아니다.
- 이미지와 Git 사이 자동 연결은 Image Updater가 담당할 예정이며 현재는 미활성이다.

---

## 3. 저장소 구조 설명 — 2분

`platform-gitops` 저장소에서 다음 세 곳만 보여준다.

```text
charts/preppers-service/                 # 공통 Helm 차트
apps/preppers/<service>/values*.yaml     # 서비스/환경별 차이
argocd/apps/preppers/workloads-appset.yaml
```

말할 내용:

> “주문 서버와 KDS 계열 서비스는 Deployment, Service 같은 기본 형태가 비슷합니다. 그래서 서비스마다 YAML 전체를 복사하지 않고 공통 Helm 차트 하나를 만들었습니다.
>
> 서비스별 차이와 dev/prod 차이는 values 파일에 두고, ApplicationSet이 서비스 목록을 읽어 ArgoCD Application을 생성합니다. 새 서비스를 추가할 때 전체 Application YAML을 복사하는 대신 서비스 정보와 values만 추가하는 구조입니다.”

가능하면 `workloads-appset.yaml`에서 아래 세 부분만 가리킨다.

1. 서비스 목록(`elements`)
2. 앱 이름/namespace 템플릿
3. 공통 values + 환경 values 레이어링

---

## 4. 현재 상태 데모 — 3분

### UI에서 보여줄 순서

1. 전체 앱 목록
2. `platform-root`
3. `preppers-order-server-dev`
4. KDS 앱 중 하나

말할 내용:

> “root Application이 하위 Application들을 Git에서 읽어 관리하는 구조입니다. 현재 dev에서는 order-server와 KDS 계열을 포함해 8개 Application이 공용 ArgoCD에 수용되어 있습니다.”

`Synced`와 `Healthy`의 차이를 짧게 설명한다.

- `Synced`: Git에 선언된 리소스와 클러스터 리소스가 일치
- `Healthy`: 실제 리소스가 정상 동작 가능한 상태

> “Synced인데 Healthy가 아닐 수도 있습니다. 예를 들어 Git의 Deployment는 정상 적용됐지만 새 이미지가 CrashLoop라면 배포 상태 일치는 했어도 서비스는 정상 상태가 아닙니다.”

실제 앱 트리에서 다음 흐름을 가리킨다.

```text
Application → Deployment → ReplicaSet → Pod
            ├→ Service
            └→ 기타 Config/Route 리소스
```

### CLI 백업 명령

UI가 느릴 때만 사용한다.

```bash
kubectl get application -n argocd --context=supplies-eks-dev
kubectl get pods -n preppers-dev --context=supplies-eks-dev
kubectl get deploy,svc -n preppers-dev --context=supplies-eks-dev
```

---

## 5. 핵심 데모: Git 변경 → 동기화 — 4분

### 가장 안전한 시나리오

서비스 영향이 작은 dev 리소스 하나를 고른다. 이미지 태그 변경보다 **Deployment annotation 또는 무해한 환경 표시값**을 권장한다. 실제 서비스 설정을 바꾸기 어렵다면 변경은 커밋하지 않고 ArgoCD의 Diff/History로 같은 흐름을 설명한다.

데모 전에 대상 파일과 롤백 커밋을 정해 둔다.

```bash
git status --short
git pull --ff-only
```

변경 후:

```bash
git diff -- <대상-values-파일>
git add <대상-values-파일>
git commit -m "chore(demo): verify ArgoCD sync"
git push
```

화면에서 관찰:

1. Git push
2. webhook 또는 polling으로 ArgoCD refresh
3. `OutOfSync`
4. automated sync
5. `Synced / Healthy`
6. History에서 새 revision 확인

말할 내용:

> “지금 제가 클러스터에 직접 `kubectl apply`를 하지 않았습니다. Git에서 원하는 상태를 바꿨고, ArgoCD가 차이를 감지해 클러스터를 맞췄습니다. 누가 무엇을 언제 배포했는지도 Git 커밋과 ArgoCD History에 같이 남습니다.”

### 시간이 지연될 때

웹훅 반영이 바로 오지 않으면 30초 이상 기다리지 않는다.

```bash
argocd app get <APP_NAME> --refresh
```

그래도 안 되면 이미 준비한 History와 Diff를 보여주며 설명을 계속한다.

### 데모 변경 원복

발표 직후 새 revert 커밋으로 되돌린다. 이력이 남으므로 `reset --hard`나 강제 push는 사용하지 않는다.

```bash
git revert <DEMO_COMMIT_SHA>
git push
```

---

## 6. self-heal 설명 — 2분

운영 리소스를 실제로 손대는 live drift 데모는 발표 환경에서 위험하다. 다음 중 하나를 선택한다.

### A안 — 권장: UI Diff로 설명

기존 Sync History 또는 Diff 화면을 보여준다.

> “누군가 클러스터를 직접 수정해 Git과 달라지면 ArgoCD가 drift를 표시합니다. dev 정책에서는 self-heal을 켜 두어 Git 상태로 다시 맞출 수 있습니다. 즉 수동 변경이 다음 배포까지 숨어 있지 않습니다.”

### B안 — 사전 승인된 dev 전용 리소스

반드시 데모 전용 Deployment에서만 replicas를 바꾼다. HPA가 붙은 서비스에는 사용하지 않는다.

```bash
kubectl scale deployment/<DEMO_DEPLOYMENT> \
  --replicas=<다른-값> \
  -n preppers-dev \
  --context=supplies-eks-dev
```

ArgoCD가 `OutOfSync`를 감지하고 선언된 replica 수로 복구하는 것을 보여준다.

> 주의: 실제 order/KDS 워크로드, HPA 대상, APISIX route, Secret, ExternalSecret에는 이 데모를 하지 않는다.

---

## 7. 작업하면서 얻은 결과 — 2분

> “기능 확인을 넘어서 실제 order-server와 KDS를 dev에서 GitOps로 수용했고, APISIX 라우트도 무중단으로 새 네임스페이스에 전환했습니다.
>
> 개인 테스트용 ArgoCD를 공용 인스턴스로 승격할 때도 기존 워크로드를 재생성하지 않고 8개 앱을 다시 수용했습니다. 이 과정에서 Application finalizer와 ArgoCD CRD의 Helm 소유권 같은 실제 운영 함정도 확인해 런북으로 남겼습니다.
>
> 인프라의 소유 경계는 전부 ArgoCD로 옮기는 방식이 아니라, VPC·EKS·IAM과 ArgoCD 자체 설치는 Terraform이 맡고, 그 위 애플리케이션과 Kubernetes 리소스는 GitOps가 맡는 하이브리드 구조로 정리했습니다.”

핵심 성과를 세 문장으로 요약한다.

1. 배포 상태의 기준을 Git으로 만들었다.
2. 공통 차트와 ApplicationSet으로 서비스 확장 비용을 줄였다.
3. drift 감지, 이력, 롤백 경로를 운영 흐름에 넣었다.

---

## 8. 한계와 다음 단계 — 1분

> “아직 세 가지가 남아 있습니다.
>
> 첫째, 현재 앱들이 `default` AppProject를 사용해 배포 범위 제한이 약합니다. `preppers`와 `gymboxx` 프로젝트로 repo, cluster, namespace 권한을 좁히는 설계는 끝났고 적용이 남았습니다.
>
> 둘째, Image Updater는 매니페스트와 IAM 구성을 작성했지만 IAM 생성 권한과 Git write 권한 때문에 아직 활성화하지 않았습니다. 따라서 오늘 데모에서는 이미지 자동 선택까지 완료됐다고 설명하지 않겠습니다.
>
> 셋째, prod 클러스터에는 ArgoCD 컨트롤 플레인만 설치했습니다. 클러스터별로 자기 도메인만 관리하도록 root를 분리한 뒤 순차 전환할 예정입니다.”

마지막 문장:

> “정리하면, dev의 실제 워크로드에서 Git을 기준으로 배포 상태가 수렴하는 기반은 만들었고, 이제 권한 경계와 이미지 자동화, prod 확산을 안전하게 닫는 단계입니다.”

---

## 9. 아침 준비 체크리스트

### 발표 30분 전

- [ ] VPN/AWS 인증과 `kubectl` context 확인
- [ ] `kubectl config current-context` 확인 후 context를 명령마다 명시
- [ ] ArgoCD UI 로그인 및 port-forward 재연결
- [ ] 전체 앱이 `Synced / Healthy`인지 확인
- [ ] 데모 대상 앱 하나와 변경할 파일 하나 확정
- [ ] 대상 앱에 HPA가 없는지 확인
- [ ] Git working tree가 깨끗한지 확인
- [ ] demo commit과 revert 절차 메모
- [ ] UI 장애 대비 CLI 결과 또는 스크린샷 준비
- [ ] 알림, 메신저, 비밀번호 표시 창 닫기

### 발표 직전 확인 명령

```bash
kubectl get application -n argocd --context=supplies-eks-dev
kubectl get pods -n preppers-dev --context=supplies-eks-dev
git status --short
```

### 절대 화면에 노출하지 않을 것

- ArgoCD 초기 admin password
- GitHub deploy key와 webhook secret
- AWS access key, Secret/ConfigMap의 민감 값
- `terraform output -raw`로 출력한 sensitive 값
- 실제 DB password가 포함될 수 있는 과거 annotation

---

## 10. 예상 질문과 짧은 답

### “기존 CI/CD와 무엇이 다른가요?”

기존에는 CI가 빌드 후 클러스터를 직접 변경했습니다. GitOps에서는 배포 상태를 Git에 기록하고 ArgoCD가 pull 방식으로 적용하므로, 배포 이력과 실제 상태의 기준이 Git으로 모입니다.

### “webhook이 없으면 배포가 안 되나요?”

아닙니다. ArgoCD가 주기적으로 Git을 확인합니다. webhook은 변경 감지를 빠르게 하는 가속 장치입니다.

### “새 이미지가 ECR에 올라가면 자동 배포되나요?”

현재는 Git의 이미지 태그가 바뀌어야 배포됩니다. Image Updater로 ECR의 정상 태그를 선택해 Git에 write-back하는 구성을 준비했지만 아직 미활성입니다.

### “왜 Helm을 선택했나요?”

대상 서비스들이 구조적으로 비슷해서 공통 차트 한 벌과 서비스/환경별 values로 중복을 가장 많이 줄일 수 있었기 때문입니다.

### “Terraform은 없애나요?”

아닙니다. VPC, EKS, IAM과 ArgoCD 자체 설치 같은 클라우드/부트스트랩 계층은 Terraform에 두고, 그 위 Kubernetes 워크로드를 ArgoCD가 관리하는 경계를 권장합니다.

### “ArgoCD가 잘못된 배포도 자동으로 해버리지 않나요?”

가능합니다. ArgoCD는 선언된 상태를 정확히 적용할 뿐 이미지가 정상인지 판단하지 않습니다. 그래서 빌드 검증, dev 선적용, health check, AppProject 권한 제한과 승인 정책이 함께 필요합니다.

### “롤백은 어떻게 하나요?”

Git에서 이전 설정으로 revert하면 ArgoCD가 그 상태로 다시 수렴합니다. ArgoCD History에서 배포 revision도 확인할 수 있습니다.
