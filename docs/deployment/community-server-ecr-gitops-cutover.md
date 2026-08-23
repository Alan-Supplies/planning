# community-server: CodeBuild/CodePipeline → GitHub Actions + ArgoCD GitOps 전환 기록

2026-08-23 ~ 08-24 진행. `gymboxx-community-server`를 다른 gymboxx NestJS 서비스들과 동일한
표준(GitHub Actions `ci.yml` → 전용 ECR 리포 → ArgoCD Image Updater write-back → ArgoCD 자동 sync)으로
옮기면서 겪은 문제와 조치를 시간 순으로 정리한다. 인프라 일반 구조는 [image-build-ci.md](image-build-ci.md),
[ci-flow.md](ci-flow.md) 참고 — 이 문서는 그 구조를 community-server에 실제로 적용하며 나온
이슈/의사결정 로그다.

## 최종 상태 요약

| 환경 | 클러스터 | ArgoCD Application | namespace | ECR 리포 | 태그 접두사 |
|---|---|---|---|---|---|
| dev | `dev-eks` | `gymboxx-community-api` | `gymboxx` | `gymboxx/community/api` | `dev-` |
| prod | `eks_prod` | `gymboxx-community-server-prod` | `default`(기존 라이브 인수) | `gymboxx/community/api` (dev와 공유) | `prod-` |

- 태그 포맷: `{env}-{YYYYMMDD}-{HHMMSS, KST}-{git sha8}` (재사용 워크플로우 `suppliesfitness/.github/nestjs-docker-ecr-build.yml@v1`가 생성)
- Image Updater `allow-tags`: dev/prod 모두 `^{env}-\d{8}-\d{6}-[a-f0-9]{8}$`, `update-strategy: alphabetical` (타임스탬프가 앞에 있어 알파벳 정렬 = 시간 정렬)
- API 경로(dev, ALB host-header): `api.gymboxx.dev.supp.fitness/community/*` (레거시 alias `dev1.supp.fitness`도 같은 target group으로 라우팅), healthcheck `/hc`

## 타임라인

### 1. develop 배포 파이프라인 테스트 중 발견한 문제들

- 빈 커밋(`--allow-empty`)으로 `develop`에 push해도 CI가 안 도는 현상 확인.
  원인: `ci.yml`의 `paths-ignore` 필터가 **변경 파일이 0개인 커밋**을 "전부 제외 경로에 해당"으로
  vacuous하게 판단해 워크플로우 자체를 건너뜀. `workflow_dispatch`로 수동 트리거하거나 실제 파일을
  건드려야 함.
- `develop`에서 `workflow_dispatch`로 실제 트리거 → 빌드 성공 → ECR push 성공 →
  ArgoCD Image Updater가 `platform-gitops`에 write-back까지 정상 확인 (dev 경로는 이미 건강했음).

### 2. `dev1` 레거시 인프라 조사

- `community-server-dev1` CodePipeline(2025-04 생성, `SUPERSEDED`)과 CodeBuild 프로젝트
  `community-server-dev`가 남아있었으나, 소스인 `eks_dev` 클러스터는 이미 폐기(platform-gitops
  `#84`)되어 DNS도 안 잡힘 — 사실상 죽은 인프라.
- `platform-gitops`의 `apps/gymboxx/community-server/values-dev.yaml`(dev1용 설정)도 이를
  참조하는 Application이 없어 미참조 상태로 방치돼 있었음.
- 결론: **dev1이라는 별도 환경은 이미 없다.** ALB에는 `dev1.supp.fitness` 호스트가 레거시 alias로
  남아있지만 지금은 `develop` 기반 배포와 동일한 target group으로 라우팅됨.
- CodePipeline `community-server-dev1` + CodeBuild `community-server-dev` 삭제 CLI를 준비했으나
  **아직 실행 안 함** (아래 "남은 작업" 참고).

### 3. main(prod) CI PR 검토 — PR #79 문제 발견

[gymboxx-community-server#79](https://github.com/suppliesfitness/gymboxx-community-server/pull/79)
(`chore/ci/ecr-path-community-api`, main 대상)를 검토한 결과:

- `#76`(main용 `ci.yml` 최초 추가)이 `#79`보다 먼저 병합되어 `#79`가 **conflicting** 상태.
- `#79`의 내용 자체도 `#80`(develop에서 이미 고친 오타) 이전 상태 — 존재하지 않는
  `dev-gymboxx-community-server-gha-role`을 참조.
- 즉 **main의 `ci.yml`이 이미 병합돼 있었는데(그것도 오타 포함 상태로) push 트리거가 살아있었음.**
  main에 push가 발생하면 CI가 role assume 단계에서 실패하는 상태였다.

조치: `#79`는 사유 코멘트 남기고 close, 대신
[gymboxx-community-server#81](https://github.com/suppliesfitness/gymboxx-community-server/pull/81)을
새로 올려 `ecr_repository: gymboxx/community-server → gymboxx/community/api`,
`gha_role_arn: ...-community-server-gha-role → ...-community-api-gha-role`로 정정.

### 4. 머지 전 검증 — ECR 리포/태그/Role 일치 확인

`#81` 머지 전에 실제로 동작할지 사전 검증:

- `ecr_repository`(`gymboxx/community/api`) ↔ platform-gitops Application의 `image-list` 어노테이션 일치.
- 재사용 워크플로우(`nestjs-docker-ecr-build.yml@v1`)의 태그 생성 로직을 직접 열어
  `{env_name}-$(date +%Y%m%d-%H%M%S)-${GITHUB_SHA::8}` 확인 → `allow-tags` 정규식과 일치.
- `dev-gymboxx-community-api-gha-role`의 OIDC trust policy에 `refs/heads/develop`,
  `refs/heads/main` **둘 다** 허용돼 있음 확인.
- 첨부 IAM 정책(`dev-gymboxx-community-api-gha-push-policy`)의 push 권한이 정확히
  `arn:...:repository/gymboxx/community/api` 리포 하나로 스코프돼 있음 확인.

### 5. prod 쪽 배포 dependency 문제 발견 — platform-gitops #90

`#81`을 머지해도, **`eks_prod`의 ArgoCD Image Updater가 여전히 legacy 공유 리포(`.../prod`)를
보는 `gymboxx-workloads` appset 소속**이라 새 리포에 push된 `prod-*` 이미지가 반영되지 않는
문제를 발견. (dev는 이미 `dev-eks`에서 전용 리포를 보는 standalone Application으로 분리돼 있었음.)

조치: [platform-gitops#90](https://github.com/suppliesfitness/platform-gitops/pull/90)을 작성 —

- `argocd/clusters/eks-prod/workloads-appset.yaml`에서 `community-server` element 제거
  (다른 7개 gymboxx 서비스와 동일하게 standalone Application으로 이관, `preserveResourcesOnDeletion: true`라
  라이브 리소스 무중단 유지)
- 신규 `argocd/clusters/eks-prod/gymboxx-community-server-prod-app.yaml` 추가 —
  `image-list: gymboxx/community/api`, `allow-tags: ^prod-\d{8}-\d{6}-[a-f0-9]{8}$`
- `apps/gymboxx/community-server/values-prod.yaml`의 `image.repository`를 전용 리포로,
  `image.tag`는 `PENDING-FIRST-PUSH-DO-NOT-MERGE` placeholder로 (다른 서비스들도 쓰는
  관례 — `syncPolicy.automated.prune: true`라 존재하지 않는 태그로 머지하면 sync 시
  ImagePullBackOff)
- **머지 순서를 PR 본문에 명시**: `#81` 머지 → main push로 첫 `prod-*` 태그 확보 →
  placeholder 교체 → 이 PR 머지. draft로 올려 순서를 강제.

### 6. `#81` 머지 → 레거시 `community-server-prod` CodePipeline이 같이 발동

`#81`을 main에 머지하자 GitHub Actions CI는 성공했지만, **레거시 CodePipeline
`community-server-prod`도 같은 push에 반응해 실행되고 실패**했다.

- 원인: 이 파이프라인의 최상위 `triggers`(`main` push git trigger)가 여전히 살아있었음
  (Source 액션의 `DetectChanges: false`는 별개 필드 — 실제 트리거는 `triggers` 섹션).
  `#76`에서 이미 `buildspec.yml`을 삭제했기 때문에, `#76` 머지 때도(2026-08-21) 동일하게
  실패했었고 이번 `#81` 머지로 재현.
- 조치: `aws codepipeline disable-stage-transition --pipeline-name community-server-prod
  --stage-name Source --transition-type Inbound`로 **Source 스테이지 진입을 차단** —
  트리거는 발동하지만 Build까지 못 가고 막힌다. 파이프라인/CodeBuild 프로젝트 자체는
  삭제하지 않음(되돌리려면 `enable-stage-transition`).

### 7. `#81`의 실제 첫 push로 `#90` placeholder 교체 → 머지 → prod 배포 성공

- `#81` 머지로 생성된 실제 첫 이미지: `prod-20260824-005002-4ed9c53d`
  (커밋 sha `4ed9c53`와 sha8 일치 확인)
- 이 값으로 `platform-gitops#90`의 placeholder를 교체, PR 머지.
- 결과 확인:
  - `kubectl get application gymboxx-community-server-prod -n argocd --context eks_prod`
    → `Synced` / `Healthy`
  - 라이브 Deployment 이미지가 새 리포/태그로 정확히 교체됨
  - 기존 in-place 인수(Deployment/Service `community-server-prod`, namespace `default`)라
    재생성 없이 무중단 전환

### 8. 전체 루프 재검증 — `workflow_dispatch`로 재빌드 테스트

`gh workflow run ci.yml --ref=main` (+ `gh run watch`)로 다시 트리거해 **CI 재실행이
prod 배포까지 자동으로 이어지는지** 검증:

1. CI 성공 → 새 태그 `prod-20260824-011138-4ed9c53d` push
2. Image Updater가 감지해 platform-gitops에 write-back 커밋(`7d86fe6`,
   "build: automatic update of gymboxx-community-server-prod")
3. ArgoCD가 `automated: {prune: true, selfHeal: false}`로 자동 sync — revision이
   write-back 커밋과 일치
4. 새 파드 2개 `Running`, 이전 파드 `Terminating` — 무중단 롤링 확인

**CI → ECR → Image Updater → GitOps write-back → ArgoCD auto-sync, 전체 파이프라인이
prod에서 실제로 검증 완료.**

## 남은 작업 (아직 정리 안 됨)

- [ ] `community-server-dev1` CodePipeline + CodeBuild 프로젝트 `community-server-dev` 삭제
      (`eks_dev` 폐기로 이미 죽은 인프라, 아직 실행 안 함)
- [ ] `community-server-prod` CodePipeline은 지금 **정지만** 했고 삭제는 안 함 — 완전
      정리(파이프라인 + CodeBuild 프로젝트 `community-server-prod` 삭제) 여부 결정 필요
- [ ] `platform-gitops`의 미참조 `apps/gymboxx/community-server/values-dev.yaml`
      (dev1용 leftover) — 8개 gymboxx 서비스 전부에 동일하게 남아있는 문제라 community-server만
      따로 정리하지 않고 별건으로 일괄 처리 예정(원래 코멘트에 그렇게 기록돼 있음)

## 관련 PR

- [gymboxx-community-server#81](https://github.com/suppliesfitness/gymboxx-community-server/pull/81) — main `ci.yml` ECR 리포/GHA Role 오타 수정 (merged)
- [gymboxx-community-server#79](https://github.com/suppliesfitness/gymboxx-community-server/pull/79) — stale, closed (superseded by #81)
- [platform-gitops#90](https://github.com/suppliesfitness/platform-gitops/pull/90) — prod ArgoCD Image Updater cutover (merged)
