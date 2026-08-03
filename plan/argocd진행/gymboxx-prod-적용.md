
# gymboxx prod 온보딩 체크리스트 (eks_prod)

> [gymboxx-dev-온보딩-체크리스트.md](./gymboxx-dev-온보딩-체크리스트.md)와 동일 패턴을 prod에 적용.
> 방식: 라이브 `default` 워크로드를 **in-place 인수**(컷오버 아님). 파일럿 서비스 1개로 패턴 검증 후 확산.
> dev와의 차이: prod는 서비스당 2~4 레플리카 HA 구성, 리소스 limits/requests 명시, ECR repo가 `.../prod`.

```
CTX=arn:aws:eks:ap-northeast-2:699016088228:cluster/eks_prod
```

> **최신 진행 현황 (2026-08-03)**: 기반 구성은 완료됐고 **검증 배포만 남았다**. prod를 바로 진행하지 않고,
> dev에서 레포별 build와 이미지 pulling 분리 PR을 머지한 뒤 서비스별 `automated: auto`를 하나씩 검증한다.
> dev 검증이 완료되면 같은 방식으로 prod를 서비스별 확산한다.
>
> **아래 2026-07-29 기록은 당시 사전 조사 기준의 이력이다.** 사전 조사 + 파일럿 실측·매니페스트 작성
> **완료**(이 리포 쪽에서 할 수 있는 건 여기까지).
> 파일럿 서비스로 **`hq-server-prod`** 선정(사용자 판단: "socket은 여러 서버 적용된다, hq는 오류가 명확하다" —
> 문제 발생 시 감지가 쉬운 서비스를 우선). `apps/gymboxx/hq-server/values-prod.yaml` +
> [gymboxx-prod-시크릿-관리.md](./gymboxx-prod-시크릿-관리.md) 커밋·push 완료.
>
> **다음 크리티컬 패스는 이 리포가 아니라 platform-iac 작업이다** (dev 때와 동일 구조): ① `eks_prod`에
> ArgoCD 설치(Terraform, `stacks/eks/eks_prod/k8s/argocd.tf` 신규 작성 — 현재 없음 확인함, `eks_dev`의
> `argocd.tf` 참고) → ② repo credential 등록 → ③ root apply → ④ SM `gymboxx/prod/service-credentials` +
> TF ExternalSecret(§시크릿 문서 §6) → ⑤ `argocd/clusters/eks-prod/workloads-appset.yaml` 작성(아직 없음,
> hq-server 1개 element로 시작) + `gymboxx-appproject.yaml`의 dormant 주석 해제 → ⑥ diff no-op 검증 → 수동 sync.
> **①이 안 끝나면 그 뒤로 아무것도 못 한다** (dev와 동일 순서 의존). 사용자가 platform-iac는 별도 세션에서
> 진행하기로 함(2026-07-29) — 이어서 할 때 여기부터 시작.

## 사전 조사
- [x] **클러스터 식별** — `eks_prod`. IAM 접근 이미 가능(별도 조치 불필요, dev와 달리 처음부터 됨).
- [x] **ArgoCD 설치 여부** — `argocd` 네임스페이스 없음 → **미설치, 그린필드** (dev와 동일 상황).
  기존 초안 `argocd/clusters/eks-prod/gymboxx-appproject.yaml` 존재(TECH-145 대기, dormant 명시돼 있었음).
- [x] **라이브 워크로드 조사** — `default` ns에 gymboxx 서버 10개 확인(전부 2~4 레플리카 HA, dev의 dev1/dev2 분리와
  달리 app-server는 단일 `app-server-prod`, 4레플리카):
  `admin-server-prod`(2), `app-server-prod`(4), `community-server-prod`(2), `hq-server-prod`(2),
  `kiosk-server-prod`(2), `pass-server-prod`(2), `public-server-prod`(2), `socket-server-prod`(1),
  `trainer-server-prod`(2), `web-client-server-prod`(2).
  범위 밖(클라이언트 앱/무관 인프라): `gymboxx-branch-admin-client-prod`, `gymboxx-hq-client-prod`,
  `gymboxx-hq-client-new-prod`, `ingress-aws-load-balancer-controller`.
- [x] **파일럿 선정** — `hq-server-prod`.
- [x] **파일럿 실측** — 아래 "파일럿 실측 노트" 참고. 상세:
  - selector: 레거시 단일 라벨 `app: hq-server-prod` (dev와 동일 패턴).
  - envFrom 공용 리소스(`env` ConfigMap, `credentials` Secret) 이미 존재 확인, 신규 생성 불필요.
    `credentials`는 prod도 TF 소유 ExternalSecret(`READY=True/SecretSynced`) 확인.
  - `pod-service-account` ServiceAccount 기존 존재 확인.
  - 노드 용량: `label=prod` 노드 5개, allocatable 58 pods/node, 샘플 노드 하나 20/58 사용 중 — **여유 충분**
    (dev의 `dev2` 노드 포화 문제 재발 가능성 낮음).
  - 외부 라우팅: `eks-ingress`(공유 ALB, host 여러 개)에 `/hq` prefix → `hq-server-prod` Service 직결 확인.
    (참고: `eks-ingress-internal`의 `hq.supp.fitness`/`hq-new.supp.fitness`는 hq-server가 아니라
    `gymboxx-hq-client-*-prod` 클라이언트로 라우팅 — 무관.)
  - **⚠️ 평문 시크릿 2개 발견** — `ADMIN_PASSWORD=<redacted>`, `SLACK_TOKEN=xoxb-...`(dev의 hq-server와 **완전히 동일한 값**,
    우연인지 의도적 재사용인지는 불명 — prod 전용 SM 시크릿을 새로 만들며 그대로 반영, dev 키 재사용은 하지 않음
    — 환경 간 시크릿 공유는 하지 않는다는 원칙 유지).
  - resources: **dev와 달리 실측값 있음** — `requests: {cpu: 100m, memory: 1000Mi}`, `limits: {cpu: 500m, memory: 4000Mi}`.
  - replicas: 2 (차트 기본값 1 → `replicaCount: 2` override 필요).

## A. 부트스트랩 — 미착수
- [ ] **ArgoCD 설치** (platform-iac Terraform, dev와 동일 모델). eks_prod에 ALB Ingress Controller가
  이미 떠 있음(`ingress-aws-load-balancer-controller`, 2/2) — dev처럼 webhook 라우트는 후속으로 미룰지 검토.
- [ ] **repo credential 등록**
- [ ] **root apply**
- [ ] **AppProject 활성화** — 기존 초안 `argocd/clusters/eks-prod/gymboxx-appproject.yaml`의 "dormant" 주석 제거.

## B. in-place 인수 (hq-server-prod 파일럿) — 미착수
- [ ] **매니페스트 작성** — `apps/gymboxx/hq-server/values-prod.yaml` (공용 `values.yaml`은 dev와 공유,
  `image.repository`만 prod용으로 override — 공용 파일 자체는 안 건드림, dev 회귀 없음).
- [ ] **appset 작성** — `argocd/clusters/eks-prod/workloads-appset.yaml` (hq-server 1개 element만 우선).
- [ ] **시크릿 선행 작업** — SM `gymboxx/prod/service-credentials` 생성(`ADMIN_PASSWORD`, `SLACK_TOKEN_HQ`) +
  TF ExternalSecret. 순서 의존은 dev와 동일(Secret 부재 시 새 파드 `CreateContainerConfigError`).
- [ ] **diff = no-op 검증** (라벨/시크릿 전환 외 변경 없는지)
- [ ] **수동 sync** — ⚠️ prod는 레플리카 2개라 `maxUnavailable: 50%`면 롤링 중 1개씩만 교체됨(dev의 단일 레플리카와
  달리 무중단 롤링이 자연스럽게 됨 — 오히려 dev보다 안전할 수 있음, 다만 실제 sync 시 확인 필요).
- [ ] **스모크 테스트** — `/hq` prefix 외부 경로 확인.

## C. 확산 — 미착수 (파일럿 검증 후 나머지 9개)

## D. 2026-08-03 검증 배포 순서

- [ ] dev의 레포별 build와 이미지 pulling 분리 PR 머지 및 서비스별 `automated: auto` 검증 완료
- [ ] prod 첫 서비스에 `automated: auto` 적용
- [ ] `Synced/Healthy`, Pod 상태, 이미지 갱신·pulling과 운영 동작 확인
- [ ] 이상이 없을 때 다음 prod 서비스로 하나씩 확산

## 파일럿 실측 노트 (2026-07-29, `kubectl get deploy hq-server-prod -n default --context=eks_prod`)
| 항목 | 실측값 |
|---|---|
| image | `699016088228.dkr.ecr.ap-northeast-2.amazonaws.com/prod:hq-server-prod-txzl5hbk` |
| replicas | 2 |
| selector | `app: hq-server-prod` (레거시 단일 라벨) |
| nodeSelector | `label: prod` |
| strategy | `maxSurge: 1, maxUnavailable: 50%` |
| resources | `requests: {cpu: 100m, memory: 1000Mi}`, `limits: {cpu: 500m, memory: 4000Mi}` |
| serviceAccountName | `pod-service-account` (기존 존재) |
| envFrom | `configMapRef: env`, `secretRef: credentials` (ns 공용, 기존 존재) |
| env (평문, 이관 대상) | `ADMIN_PASSWORD=<redacted>`, `SLACK_TOKEN=xoxb-...`(해시 `a9993e36`/`904d8d99` — dev hq-server와 동일값) |
| env (평문 아님) | `ADMIN_ID=gymboxx`, `JWT_EXPIRE_IN=365d`, `TZ=Asia/Seoul` |
| ingress | `eks-ingress` 공유 ALB에 `/hq` prefix로 직결 |
| Service | ClusterIP, port 80 → targetPort 8085 |

## 변경 로그
- 2026-07-29: 체크리스트 생성. eks_prod 접근/ArgoCD 미설치/라이브 워크로드 10개 확인.
  파일럿 `hq-server-prod` 선정 및 실측 완료. 매니페스트 작성은 다음 단계.
