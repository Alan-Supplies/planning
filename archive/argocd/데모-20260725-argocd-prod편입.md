# ArgoCD GitOps 데모 (2026-07-25, ~15분)

> 청중: 같은 팀 개발자 (기술 상세 O)
> 포커스: **prod 편입** (dev는 배경으로 짧게). 발표자 노트 + 라이브로 보여줄 명령 포함.
> 소스: [order-server-gitops-후속-runbook.md](./order-server-gitops-후속-runbook.md) · [gitops-prod-스탠드업-runbook.md](./gitops-prod-스탠드업-runbook.md)

---

## 0. 오프닝 한 장 (1분)

**한 줄 요약**: 5개 서비스(order/auth-api/backoffice/pos/kiosk)를 GitOps(ArgoCD)로 옮기는 작업. dev는 완전히 끝나고 CI까지 자동화됐고, 지금은 그 검증된 패턴을 **prod 클러스터에 복제**하는 단계.

타임라인 (구두로 훑기):

```
7/19  order-server 파일럿 시작
7/20  dev 컷오버 + CI 옵션B + kds 온보딩 + shared ArgoCD 승격(argocd-alan→argocd)
7/21  ArgoCD Image Updater(CI 완전자동화) 활성화 + webhook + preppers-cluster ArgoCD 설치
7/23  클러스터-first 디렉토리 재편 + order-server prod 편입 준비
7/23  auth-api/backoffice/pos/kiosk-server prod 편입 준비  ← 지금 여기, 최신 커밋
```

---

## 1. 왜 GitOps인가 (1분, 배경만 스치듯)

- 기존: 서비스 repo의 CodeBuild가 `kubectl apply`로 직접 배포 → 배포 이력이 git에 없고, 클러스터 상태가 "선언"이 아니라 "명령의 결과".
- 목표: **git이 단일 진실 소스**. 클러스터 상태 = git 상태. ArgoCD가 둘의 diff를 감시·수렴.
- 이 repo(`platform-gitops`)가 그 단일 소스. 서비스 repo는 빌드만, 배포는 여기.

---

## 2. 아키텍처 모델 (2분)

**모델 A 확정**: 클러스터별 in-cluster ArgoCD (허브 아님).

- 각 클러스터가 자기 ArgoCD로 자기 워크로드만 관리 (`destination.server: https://kubernetes.default.svc`, 크로스클러스터 아님).
- 근거: blast radius 격리 (dev 사고가 prod에 안 닿음). 허브 모델(B)은 안티패턴 — 특히 허브를 prod에 두면 전 환경이 prod에 종속.

**디렉토리 = 클러스터-first** (7/21 확정, 7/23 실행):

```
charts/preppers-service/                 # 공유 헬름 차트 (클러스터 무관)
apps/preppers/<svc>/values*.yaml         # 공유 값 (base + values-<env>)
argocd/bootstrap/
  supplies-eks-dev-root.yaml             # name=platform-root, path=argocd/clusters/supplies-eks-dev
  preppers-cluster-root.yaml             # 〃                    path=argocd/clusters/preppers-cluster
argocd/clusters/
  supplies-eks-dev/   ← dev 가 읽음 (재편 완료)
  preppers-cluster/   ← prod, 이번 작업 대상
  eks-prod/           ← gymboxx (아직 dormant)
```

> **왜 도메인-first가 아니라 클러스터-first인가**: root↔클러스터가 1:1이어야 "이 root가 뭘 배포하는지"가 폴더 하나로 명확해짐. 클러스터 소속은 파일에 안 적혀있고 **부트스트랩 시 `--context`로 결정**된다 — 그래서 클러스터별 폴더 분리가 유일한 안전장치.

**Before/After — 실제로 있었던 재편 (2026-07-23)**:

```
# 도메인-first (7/20 최초 설계, ~7/23까지)
argocd/
  bootstrap/
    root.yaml                          # root 1개 — namespace=argocd-alan, path=argocd/apps (recurse 전체)
  apps/
    preppers/
      workloads-appset.yaml            # elements 에 dev/prod 를 같이 넣을 뻔했던 지점 (틀린 접근으로 판명)
      order-server-apisix.yaml
      order-server-prereqs.yaml
  projects/
    preppers-appproject.yaml
    gymboxx-appproject.yaml

# 클러스터-first (7/21 결정, 7/23 실행 — 지금)
argocd/
  bootstrap/
    supplies-eks-dev-root.yaml         # root, path=argocd/clusters/supplies-eks-dev
    preppers-cluster-root.yaml         # root, path=argocd/clusters/preppers-cluster
    eks-prod-root.yaml                 # (예정) path=argocd/clusters/eks-prod
  clusters/
    supplies-eks-dev/
      workloads-appset.yaml            # env=dev element 만
      order-server-apisix.yaml
      kds-server-apisix.yaml  auth-api-apisix.yaml  ...
      preppers-appproject.yaml         # AppProject 도 클러스터 폴더 안 (sync-wave -1)
    preppers-cluster/
      workloads-appset.yaml            # env=prod element 만 (별도 파일!)
      preppers-appproject.yaml
    eks-prod/
      gymboxx-appproject.yaml          # gymboxx, 아직 dormant
```

> **한 appset에 dev+prod element를 같이 넣으면 왜 틀린가**: destination이 in-cluster(자기 자신)라, 그 appset이 심어진 클러스터가 dev/prod 상관없이 **양쪽 element를 전부 자기한테 배포하려** 든다. 그래서 env 구분은 appset 안 데이터가 아니라 **"어느 클러스터 root가 이 파일을 보느냐"(=폴더 위치)**로 해야 한다. `charts/`·`apps/<domain>/<svc>/values*.yaml`(공유 값)은 이 재편과 무관하게 그대로 — 재편 대상은 `argocd/` 안의 **컨트롤플레인 정의**뿐.

**환경 지도**:

| env | 클러스터 | 도메인 | ArgoCD | 게이트웨이 |
|---|---|---|---|---|
| dev | `supplies-eks-dev` | preppers-dev | ✅ 완료 | APISIX / `dev-pp-api.supp.fitness` |
| prod | `preppers-cluster` | preppers-prod | 설치됨(부트스트랩 전) | APISIX / `prod-pp-api.supp.fitness` |
| prod | `eks-prod` | gymboxx-prod | 미착수 | 미확인 |

---

## 3. dev 여정 (2분, 빠르게 훑기 — 상세는 생략)

1. **파일럿 (order-server)**: 옛 repo → platform-gitops 컷오버, Application이 기존 리소스를 **adopt**(재생성 없이 인수).
2. **CI 독립화**: 처음엔 수동 `image-bump.yml` (workflow_dispatch) → 태그 오입력 사고 다발 → **ArgoCD Image Updater(pull 모델)**로 전환. ECR 폴링 → git write-back → ArgoCD sync. "빌드는 빌드만, GitOps가 관찰·반영."
3. **kds 온보딩**: order와 동일 ns(preppers-dev) 공유, redis는 raw manifest, polling은 공용 차트 재사용.
4. **shared ArgoCD 승격**: 개인 인스턴스(`argocd-alan`) → 팀 소유(`argocd`, TF 관리). 워크로드 재생성 0으로 무중단.
5. **auth-api/backoffice/pos/kiosk-server 온보딩**: 같은 패턴 반복 적용 — 워크로드뿐 아니라 **APISIX 라우트까지 GitOps로 이관**(`apps/preppers/<svc>/apisix/apisix-route-{pub,pri}.yaml`). dev는 라우트도 스코프 안, prod(섹션 4)는 라우트가 스코프 밖 — 이 차이를 명확히 짚을 것.

> 데모 포인트 하나만: *"컷오버가 항상 무중단이었다"* — Application이 기존 리소스를 재생성 없이 adopt하는 패턴을 5개 서비스에 반복 적용해서 매번 파드 재시작 없이 넘어갔다.

**라우트 이관에서 실제로 본 것 (auth-api 예시)** — [apisix-route-pri.yaml](../../apps/preppers/auth-api/apisix/apisix-route-pri.yaml):

```yaml
# auth-api private 라우트 — 라이브(preppers-auth-api-private-dev) 그대로 이전.
# ⚠️ Lua 스크립트가 order/kds 와 다름(주입 헤더 종류·대소문자 차이) — 복붙 아님, 라이브 실측 그대로.
# consumer-restriction 없음(공유 consumer preppers-backend 만 사용, order 처럼 개별 화이트리스트 불필요).
```

> **왜 이게 데모에서 짚을 가치가 있나**: 5개 서비스 라우트가 겉보기엔 "APISIX route + JWT + Lua 헤더주입"으로 똑같아 보이지만, 서비스마다 **Lua 스크립트가 실제로 다름** — 헤더 이름 대소문자, base64 패딩 보정 유무, `store_ids` 타입 체크 유무 등. 그래서 공용 템플릿으로 뽑지 않고 **서비스별 라이브 실측을 그대로 파일화**했다(주석에 매번 "라이브 그대로 이전" + 차이점 명시). 원칙: 겉모양이 같아 보여도 실측 없이 복붙하지 않는다.
> **consumer 패턴도 서비스마다 다름**: order는 `consumer-restriction` 플러그인으로 개별 whitelist(`default_preppers_order_consumer`, 결정 E와 연결)를 걸지만, auth-api/backoffice/pos/kiosk는 공유 consumer(`preppers-backend`)만 쓰고 개별 제한이 없음 — 그래서 라우트 이관 난이도가 order보다 낮았음.

**서비스별 Lua 헤더주입 차이 한눈에** (전부 JWT payload → 헤더 주입 패턴은 같지만 디테일이 다름):

| 서비스 | 주입 헤더 | 특이사항 |
|---|---|---|
| order-server | `X-User-Id`/`X-key`/`X-Branch-unique-id`/`X-Store-id`/`X-Kiosk-number`/`X-Employee-*`/`X-Employee-store-ids` | `store_ids`를 **`type()`으로 테이블 체크** 후 `table.concat(...,",")` — 정석 구현 |
| kiosk-server | order와 동일 헤더 풀세트 | order와 거의 동일(대소문자까지 일치) |
| backoffice-server | order와 동일 헤더 풀세트 | `store_ids`가 **타입 체크 없이 그냥 `tostring()`** — 실제 값이 Lua 테이블이면 `"table: 0x..."` 같은 문자열이 찍히는 라이브 버그를 **그대로 이관**(고치지 않음: 컷오버 스코프는 "이전"이지 "수정"이 아님) |
| auth-api | `X-User-Id`/`X-key`/`X-Branch-unique-id`/`X-kiosk-number`/`X-store-id` 만 (Employee 계열 없음) | 가장 단순 — 대소문자도 `X-kiosk-number`/`X-store-id`로 다른 서비스와 다름(소문자) |
| pos-server | `X-Store-id`/`X-Store-name`/`X-POS-number` (완전히 다른 헤더 세트) | payload 디코드 전에 **URL-safe base64 → 표준 base64 변환 + 패딩 복원**(`-`→`+`, `_`→`/`, 길이%4 보정)까지 직접 함 — 유일하게 이 보정 로직이 있음 |

> 이 표 자체가 데모 메시지: *"패턴 반복처럼 보여도 서비스마다 실측 확인 없이는 못 옮긴다"* — 그리고 컷오버 원칙은 **버그까지 포함해서 라이브를 그대로 복제**하는 것(버그 수정은 별도 트랙).

---

## 4. 🎯 prod 편입 (메인, 7~8분)

### 4.1 prod의 특수성

- prod는 **도메인별 클러스터 분리**: preppers 서비스는 `preppers-cluster`, gymboxx는 `eks-prod`. dev처럼 한 클러스터에 다 때려박지 않음.
- `preppers-cluster`는 이미 auth/backoffice/kiosk/pos/order/kds가 **`default` 네임스페이스**에서 라이브로 돌고 있음 (레거시 CodeBuild 배포).

### 4.2 namespace 결정 — 라이브 디버깅 스토리 (좋은 데모 포인트)

- 원래 가정: dev처럼 `preppers-prod`로 옮겨야 한다 — 근거로 든 게 "OpenSearch가 `default` ns를 전제로 한다"는 이야기였음.
- **실측**: 그 결합은 실제로 fluent-bit 설정의 grep 한 줄뿐이었고, 인덱스·대시보드는 ns-agnostic → 전제가 debunk됨.
- **2026-07-23 회의 결론**: 그래도 `default` 유지 (변경 최소화, 통합 클러스터 이관 시점까지 hold). → [prod-namespace-전략-분석.md §D](./prod-namespace-전략-분석.md)
- **의미**: prod는 ns 컷오버 없이 **라이브 워크로드를 in-place로 GitOps가 인수**하는 방식으로 스코프가 단순해짐. consumer(결정 E)/prereqs(결정 F)도 `default` 그대로라 이번 스코프에서 사이드스텝됨.

### 4.3 order-server prod standup (선행 사례)

- `argocd/clusters/preppers-cluster/workloads-appset.yaml` 생성, `values-prod.yaml`을 **라이브 실측**에 맞춤.
- **핵심 검증 기법**: `kubectl diff`로 dry-run — 라이브 대비 변경분이 **metadata 라벨 추가뿐**임을 확인 후에만 진행. 파드 롤아웃 0.
- sync는 처음에 **manual** (automated 아님) — 안전하게 diff 확인하고 수동 Sync 먼저, 검증되면 automated 승격.

### 4.4 auth-api/backoffice/pos/kiosk-server 편입 (최신 커밋, ebd83bf)

같은 패턴을 4개 서비스에 반복 — 근데 서비스마다 **미묘한 함정**이 있었음. 이게 오늘 데모의 핵심 디테일.

**함정 ①: immutable selector (auth-api)**

```yaml
# apps/preppers/auth-api/values-prod.yaml
workloadName: preppers-auth-api-prod
fullnameOverride: preppers-auth-api-prod
containerName: preppers-auth-api-prod
```
> base(`values.yaml`)의 workloadName이 `-dev` 고정 → prod 라이브는 `-prod` 접미사 셀렉터를 씀. 재정의 안 하면 **Deployment selector가 immutable이라 apply 자체가 실패**. dry-run으로 미리 잡아낸 케이스.

**함정 ②: Helm 맵 병합 (auth-api / backoffice / kiosk)**

```yaml
resources:
  limits:
    memory: 4Gi
    cpu: null      # ← 이거 없으면 사고남
  requests:
    memory: 1Gi
    cpu: null
```
> 라이브 실측엔 cpu가 아예 없음(memory만). 근데 **Helm의 맵 병합은 리스트와 달리 key 단위 병합**이라, `cpu`를 명시적으로 안 비우면 차트 기본값(100m/500m)이 슬쩍 들어와버림 → "no-op이어야 하는데 사실은 리소스가 바뀌는" 조용한 회귀. `cpu: null`로 명시해야 진짜 no-op.

**함정 ③: 서비스별 diff (pos-server)**

> pos-server는 dev와 값 자체가 다름 — `maxUnavailable` 0(dev는 50%), 리소스 250m/1Gi(dev는 200m/512Mi). "패턴은 같지만 값은 서비스마다 라이브 실측을 따로 봐야 한다"는 걸 보여주는 사례.

**appset 확장** (`argocd/clusters/preppers-cluster/workloads-appset.yaml`):

```yaml
elements:
  - service: order-server
    env: prod
    namespace: default
  - service: auth-api
    env: prod
    namespace: default
  - service: backoffice-server
    env: prod
    namespace: default
  - service: pos-server
    env: prod
    namespace: default
  - service: kiosk-server
    env: prod
    namespace: default
```

> 라우트/consumer는 **이번 스코프 밖** — order-server와 동일하게 라이브 APISIX 라우트 그대로 둠. 워크로드(Deployment/Service)만 GitOps로 인수. "한 번에 다 옮기지 않는다"는 원칙 재확인.

**검증**: `kubectl diff` (dry-run) — 4개 서비스 전부 순수 no-op (라벨 추가뿐, selector/cpu 누수 없음, 파드 롤아웃 없음).

---

## 5. (선택, 시간 남으면) 라이브로 보여줄 것

```bash
# 아직 부트스트랩 전이므로 "이 상태"를 보여주는 용도
kubectl get pods -n argocd --context=preppers-cluster        # ArgoCD 컨트롤플레인 존재, 앱은 아직 없음
kubectl get deploy -n default --context=preppers-cluster | grep -E 'order|auth|backoffice|pos|kiosk'  # 라이브 워크로드

# 코드 레벨로 diff 원리 설명 (실제 실행은 부트스트랩 후)
git show ebd83bf -- apps/preppers/auth-api/values-prod.yaml
```

---

## 6. 남은 일 / 다음 단계 (1분)

```
[ ] PR(feature/prod-remaining-services) → main 머지
[ ] preppers-cluster 부트스트랩 (repo credential 등록 + root apply)
[ ] 5개 서비스 수동 Sync (diff=라벨뿐 재확인) → in-place 인수
[ ] 검증 후 appset automated(prune/selfHeal) 승격
[ ] prod webhook + Image Updater 복제 (dev와 동일 패턴, IRSA 재사용)
[ ] eks-prod (gymboxx-prod) — 별도 도메인, 아직 미착수
```

---

## 7. 예상 질문 대비

- **"왜 prod는 automated sync를 바로 안 켜요?"** → 라이브 인수라 diff가 예상과 다르면(=라벨 외 뭔가 바뀌면) 자동으로 밀어붙이면 위험. 수동 Sync로 확인 후 승격하는 게 원칙.
- **"CPU null 안 넣으면 진짜 무슨 일이 나요?"** → 조용히 리소스 limit이 차트 기본값으로 바뀜. no-op인 줄 알고 sync했는데 실제로는 리소스 변경 → 최악의 경우 스케줄링 실패나 OOM 임계값 변화. dry-run diff를 습관화하는 이유.
- **"dev랑 prod랑 왜 클러스터가 아예 분리돼있어요?"** → 도메인별 클러스터 분리는 조직/운영 경계 문제(preppers-cluster vs eks-prod)라 이 작업 스코프 밖의 기존 결정. 모델 A는 그 위에서 "각 클러스터가 자기 것만 본다"는 원칙만 추가.
- **"라우트도 다 옮기는 거예요?"** → 아니요, 이번 스코프는 워크로드(Deployment/Service)만. APISIX 라우트·consumer는 라이브 그대로 — 변경 최소화 원칙.
