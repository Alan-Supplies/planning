# ArgoCD 환경별 구조 설계 (TECH-147)

> **관련 이슈**: [TECH-147 ARGOCD 환경별 구조 잡기](https://linear.app/suppliesfitness/issue/TECH-147/argocd-환경별-구조-잡기)
> (상위 기획: [TECH-144 적용 계획](./적용계획.md) · 상위: [TECH-126](https://linear.app/suppliesfitness/issue/TECH-126/argocd-진행))
> **성격**: 설계 확정 문서 (적용계획 §4-A의 1번 — *다른 설계의 전제*)
> **담당**: alan · **작성**: 2026-07-14 · **범위**: Preppers 8개 워크로드의 EKS GitOps 매니페스트 구조

---

## 1. 결정 요약 (TL;DR)

| 항목 | 결정 |
|---|---|
| **템플릿 방식** | **Helm 공유 차트 1개** (`preppers-service`) + 서비스/환경별 values 레이어링 |
| **Repo 전략** | 앱 소스와 분리된 **단일 중앙 GitOps config repo** (`preppers-gitops`) |
| **환경 차이** | 파일 계층 `values.yaml`(공통) → `values-<env>.yaml`(환경) → 앱별 override 로 분리 |
| **앱 등록** | 파일럿은 수동 `Application` 1개 → 확산 시 **ApplicationSet**로 자동 생성 |
| **CI 연동** | CI는 이미지 빌드/푸시까지만. **이미지 태그를 GitOps repo values에 커밋** → ArgoCD가 동기화 (push→pull 경계) |

**한 줄 근거**: 대상 8개(백엔드 5 + 클라이언트 3)가 `Deployment + Service + Ingress + HPA`로 거의 동형이라, **템플릿 1벌 + values N벌**로 표현하는 Helm 공유 차트가 중복을 최소화한다.

---

## 2. 결정 근거 — Helm vs Kustomize

같은 8개 서비스를 두 방식으로 표현했을 때의 비교.

| 기준 | Helm 공유 차트 ✅ | Kustomize base+overlays |
|---|---|---|
| 동형 서비스 N개 표현 | **템플릿 1개 + values N개** (최고 DRY) | 서비스마다 base 필요 → 중복(공유 base+component로 완화 가능하나 복잡) |
| 환경 차이(dev/prod) | valueFiles 레이어링으로 간결 | overlay 패치로 명확 |
| CI 이미지 태그 주입 | `image.tag` values 1줄 교체 (**Image Updater 연동 쉬움**) | overlay의 `images:` 태그 교체 |
| Git diff/리뷰 | 렌더 결과가 diff에 직접 안 보임(단점) | 순수 YAML이라 diff 명확(장점) |
| 러닝커브 | 템플릿 문법 학습 필요 | 낮음 |
| ArgoCD 지원 | 네이티브 | 네이티브 |

**결론**: diff 가독성은 Kustomize가 낫지만, **8개 동형 서비스의 중복 제거 + CI 태그 주입 편의**가 이번 롤아웃에서 더 큰 가치. `argocd app diff` / ArgoCD UI의 렌더 후 diff로 Helm의 가독성 단점을 보완한다.

---

## 3. Repo 전략 — 단일 중앙 GitOps repo

- 앱 소스코드 repo(`preppers-*-server` 등)와 **분리된 전용 config repo** `preppers-gitops` 1개를 둔다.
  - GitOps SSoT는 "배포 상태"이며, 앱 코드와 라이프사이클(리뷰·롤백·권한)이 다르다.
  - 현재 POC repo `Alan-Supplies/argocd-example-apps`는 예제 검증용 → 정식 repo로 승격/신규 생성. **[결정 필요]** repo 소유 org/이름.
- **왜 서비스별 repo가 아닌 단일 repo인가**: 8개 서비스가 하나의 공유 차트를 참조하므로, 차트 변경을 한 곳에서 관리·리뷰하는 편이 낫다. 서비스별 접근 격리는 repo 분리가 아니라 **AppProject RBAC 경계**(TECH-145)로 해결한다.

---

## 4. 디렉토리 구조

```text
preppers-gitops/
├── charts/
│   └── preppers-service/              # ★ 공유 차트 1개 (모든 서버/클라이언트 공용)
│       ├── Chart.yaml
│       ├── values.yaml                # 차트 기본값(모든 필드의 안전한 default)
│       └── templates/
│           ├── _helpers.tpl           # 이름/라벨 헬퍼
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml           # ingress.enabled 토글
│           ├── hpa.yaml               # autoscaling.enabled 토글
│           └── configmap.yaml         # env/config (Secret은 §7 참고)
│
├── apps/                              # 워크로드별 값 (환경 = 파일 접미사)
│   ├── auth-server/
│   │   ├── values.yaml                # 서비스 공통(이미지 repo, 포트, 리소스 등)
│   │   ├── values-dev.yaml            # dev override (replicas·domain·태그 등)
│   │   └── values-prod.yaml           # prod override
│   ├── order-server/
│   │   ├── values.yaml
│   │   ├── values-dev.yaml
│   │   └── values-prod.yaml
│   ├── kds-server/     { values.yaml, values-dev.yaml, values-prod.yaml }
│   ├── pos-server/     { …동일… }
│   ├── kiosk-server/   { …동일… }
│   ├── kds/            { …동일… }   # 클라이언트 (§8 클라이언트 주의 참고)
│   ├── pos/            { …동일… }
│   └── kiosk/          { …동일… }
│
├── argocd/
│   ├── projects/                      # AppProject (TECH-145에서 상세)
│   │   └── preppers.yaml
│   └── applicationsets/               # 확산 단계에서 사용
│       ├── backend.yaml               # 서버 5종 × 환경 자동 생성
│       └── clients.yaml               # 클라이언트 3종 × 환경
│
└── README.md
```

- **환경(dev/prod)은 디렉토리가 아니라 values 파일 접미사**로 표현 → 서비스 하나당 폴더 1개로 유지, 환경 추가는 파일 1개 추가.
- 워크로드 이름은 기존 파이프라인 규칙 `{domain}-{server/client}` 계승 (예: `preppers-order-server-prod`는 ArgoCD Application 이름으로 매핑).

---

## 5. 공유 차트 설계 (`preppers-service`)

### 5.1 values 레이어링 (우선순위: 아래로 갈수록 우선)

1. `charts/preppers-service/values.yaml` — 차트 기본값(전 서비스 안전 default)
2. `apps/<svc>/values.yaml` — 서비스 고유값(이미지 repo, containerPort, 헬스체크 경로 등)
3. `apps/<svc>/values-<env>.yaml` — 환경 override(replicas, 도메인, 이미지 태그, 리소스)

### 5.2 차트 기본값 예시 (`charts/preppers-service/values.yaml`)

```yaml
image:
  repository: ""        # 앱 values에서 필수 지정
  tag: "latest"         # 환경 values / CI가 override
  pullPolicy: IfNotPresent

replicaCount: 1
containerPort: 8080

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: alb
  host: ""
  annotations: {}

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 70

resources:
  requests: { cpu: 100m, memory: 256Mi }
  limits:   { cpu: 500m, memory: 512Mi }

env: []                 # [{name, value}] 또는 configMapKeyRef
envFrom: []             # configMap/secret 참조
```

### 5.3 서비스 고유값 예시 (`apps/auth-server/values.yaml`)

```yaml
image:
  repository: <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/preppers-auth-server
containerPort: 8080
service:
  port: 80
ingress:
  enabled: true
  className: alb
```

### 5.4 환경 override 예시 (`apps/auth-server/values-prod.yaml`)

```yaml
image:
  tag: "1.42.0"          # ← CI가 릴리스 시 이 줄을 커밋 (§7)
replicaCount: 3
autoscaling:
  enabled: true
ingress:
  host: auth.preppers.co.kr
resources:
  requests: { cpu: 250m, memory: 512Mi }
```

`values-dev.yaml`은 `tag: <dev-sha>`, `replicaCount: 1`, `ingress.host: auth.dev.preppers...`, `autoscaling.enabled: false` 처럼 가볍게.

---

## 6. ArgoCD 연동

### 6.1 파일럿(4-B): 수동 Application 1개

적용계획대로 `AUTH_SERVER`를 dev에 먼저. valueFiles로 §5의 3계층을 조합.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: preppers-auth-server-dev
  namespace: argocd-alan
spec:
  project: preppers
  source:
    repoURL: git@github.com:<org>/preppers-gitops.git
    targetRevision: main
    path: charts/preppers-service
    helm:
      valueFiles:
        - ../../apps/auth-server/values.yaml
        - ../../apps/auth-server/values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: preppers-dev
  syncPolicy:            # 정책 상세는 TECH-146 (dev는 automated 예정)
    automated: { prune: true, selfHeal: true }
```

> valueFiles의 `../../` 상대경로는 동일 repo 내라 ArgoCD가 허용. 제약 이슈 시 **multi-source(`$values` ref)** 패턴으로 대체 가능 — 후속 검증.

### 6.2 확산(4-C): ApplicationSet로 자동 생성

서비스×환경 조합을 매번 손으로 쓰지 않도록 list generator 사용. (적용계획 §3.3대로 dev 검증 후 도입)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: preppers-backend
  namespace: argocd-alan
spec:
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - { svc: auth-server }
                - { svc: order-server }
                - { svc: kds-server }
                - { svc: pos-server }
                - { svc: kiosk-server }
          - list:
              elements:
                - { env: dev,  cluster: https://kubernetes.default.svc, ns: preppers-dev }
                # prod는 TECH-146 정책 확정 후 추가
  template:
    metadata:
      name: 'preppers-{{svc}}-{{env}}'
    spec:
      project: preppers
      source:
        repoURL: git@github.com:<org>/preppers-gitops.git
        targetRevision: main
        path: charts/preppers-service
        helm:
          valueFiles:
            - '../../apps/{{svc}}/values.yaml'
            - '../../apps/{{svc}}/values-{{env}}.yaml'
      destination: { server: '{{cluster}}', namespace: '{{ns}}' }
      syncPolicy:
        automated: { prune: true, selfHeal: true }
```

- **네임스페이스 분리**: 현재 `argocd-alan`에 앱까지 섞여 있음(`평가.md` 지적). 워크로드는 `preppers-dev` / `preppers-prod` 네임스페이스로 분리하고, `argocd-*`는 컨트롤플레인 전용으로 정리.
- AppProject `preppers`의 소스 repo·대상 네임스페이스·클러스터 허용 범위(RBAC 경계)는 **TECH-145**에서 확정.

---

## 7. CI 연동 — push→pull 경계

GitOps 전환의 핵심은 "CI가 클러스터를 직접 만지지 않는다"이다.

```text
[앱 repo] 코드 push
   └─ CI(CodeBuild): 이미지 빌드 → ECR push (태그 = git sha 또는 semver)
        └─ CI가 preppers-gitops의 apps/<svc>/values-<env>.yaml 의 image.tag 를 커밋/push
             └─ (웹훅, TECH-127) ArgoCD refresh → 클러스터 sync   ← 여기부터 pull
```

- dev: 커밋 태그(sha) 자동 반영. prod: 릴리스 태그를 **PR/승인 후** values-prod.yaml에 반영(보수적, TECH-146과 연계).
- 태그 자동 갱신은 초기엔 CI 스크립트로, 이후 **ArgoCD Image Updater** 도입 검토.

---

## 8. 미해결 / 주의 사항

| # | 항목 | 연계 |
|---|---|---|
| 1 | **클라이언트(KDS/POS/KIOSK) 배포 형태** — 컨테이너(nginx)면 공유 차트 재사용 OK, S3/CloudFront 정적 배포면 별도 처리(공유 차트 부적합) → 확인 필요 | TECH-147 |
| 2 | GitOps repo 정식 이름/소유 org (`preppers-gitops` 신규 vs 예제 repo 승격) | TECH-144 |
| 3 | Secret 관리 방식 — configMap은 차트로, Secret은 **SealedSecrets/External Secrets** 등 별도 결정 필요(평문 커밋 금지) | 후속 |
| 4 | valueFiles 상대경로(`../../`) 제약 시 multi-source 패턴 전환 | 파일럿 검증 |
| 5 | `preppers-cluster` 역할 확정 후 대상 클러스터/네임스페이스 목록 확정 | TECH-144 #1 |

---

## 9. 다음 액션

- [ ] 이 구조로 `preppers-gitops` repo 스캐폴딩 (charts/preppers-service + apps/auth-server)
- [ ] 파일럿(4-B): `preppers-auth-server-dev` Application 수동 적용 → 성공 기준(적용계획 §6) 검증
- [ ] 클라이언트 배포 형태 확인(§8 #1) — 필요 시 클라이언트용 차트 분리 검토
- [ ] TECH-145(AppProject)·TECH-146(배포 정책)에 본 구조 전달
- [ ] 완료 시 `docs/일정관리/cycle1-todo.md` 체크 + Linear TECH-147 상태 갱신
```
