# ADR-0001: CodePipeline 제거, CodeBuild 네이티브 트리거로 전환

| | |
|---|---|
| 상태 | 제안됨 — 합의 대기 |
| 작성일 | 2026-08-10 |
| 작성자 | alan |
| 결정자 | *(합의 후 기재)* |
| 근거·절차 | [ci-파이프라인-일원화-codepipeline-제거.md](../deployment/ci-파이프라인-일원화-codepipeline-제거.md) — 실측 전문, 함정 7건, 전환 런북 |

## 배경

GitOps 인수로 배포 주체가 CI에서 ArgoCD로 넘어갔다. 각 서비스 `buildspec.yml`의 `kubectl apply`는 제거됐고,
배포 경로는 `ECR push → Image Updater → values 갱신 → ArgoCD sync`가 됐다.

배포 단계가 빠진 뒤 CodePipeline에 무엇이 남았는지 실측했다(2026-08-10). gymboxx prod 10개 전수 조사 결과
**전부 `Source` → `Build` 2스테이지이고 `Deploy`·승인 스테이지가 0개**다. 남은 역할은 세 가지뿐이다.

| CodePipeline이 하는 일 | CodeBuild 단독 대체 |
|---|---|
| GitHub push 감지 | 네이티브 webhook |
| CodeBuild 실행 | 자기 자신 |
| `TARGET_ENV`/`PODS_NUM` 주입 | 프로젝트 환경변수 |

"필요 없어졌다"가 아니라 **이미 필요 없었는데 배포 단계가 빠지면서 드러났다**가 정확하다.

## 결정

**GitOps로 인수된 서비스의 CodePipeline을 삭제하고, CodeBuild 프로젝트에 webhook을 직접 붙인다.**

| # | 세부 결정 | 근거 |
|---|---|---|
| 1 | webhook 필터는 `EVENT:PUSH` + `HEAD_REF` 앵커까지. `FILE_PATH`는 쓰지 않는다 | 앱 repo에 문서-only 커밋 0건(40커밋×3 repo). 실익 없이 AWS 100파일 제약만 떠안는다 |
| 2 | 환경변수는 CodeBuild 프로젝트로 단일화. `TARGET_ENV`를 **파이프라인 삭제 전에** 이관 | 순서를 어기면 배포가 조용히 멈춘다(전제 3) |
| 3 | `PODS_NUM`은 이관하지 않고 폐기 | buildspec이 참조하지 않는다. 레플리카는 `values-<env>.yaml`의 `replicaCount` 소유 |
| 4 | `concurrentBuildLimit: 1`을 건다 | `SUPERSEDED`의 대체는 아니다. 실패 방향을 고르는 조치 — [§5-4](../deployment/ci-파이프라인-일원화-codepipeline-제거.md) |
| 5 | 서비스 단위로 prod부터 적용. dev는 전제 4 해소 후 | prod는 브랜치가 `main` 하나뿐이라 dev1/dev2 문제가 없다 |

## 범위

| | 대상 |
|---|---|
| 적용 | GitOps 인수 완료 + buildspec 정리 완료 서비스 |
| 제외 | `web-client-server`(GitOps 대상 아님) · `socket-server` prod(buildspec에 `kubectl` 잔존) · lambda/client/batch 계열 약 70개(전제 불성립) |
| 무관 | buildspec의 빌드 로직 · Terraform 편입(별건) |

## 대안

| | A. CodePipeline 유지 | **B. CodeBuild webhook (채택)** | C. GH Actions → `start-build` |
|---|---|---|---|
| 서비스당 리소스 | 2개 | 1개 | 2개 + 워크플로 |
| 환경변수 소유 | 2곳 분산 | 한 곳 | 2곳 |
| 앱 repo 변경 | 불필요 | 불필요 | 워크플로 파일 필요 |
| AWS 자격증명 | 불필요 | 불필요(기존 CodeConnection) | OIDC/IAM 신규 |
| 사내 선례 | 다수(현행) | 3건 가동 중 | preppers dev 현행 |

- **A 기각** — 기능을 더해주지 않으면서 환경변수를 두 곳에 쪼갠다. 그 분산이 이미 사고 원인이 됐다.
- **C 기각** — repo마다 워크플로와 자격증명 경로가 필요하다. B는 앱 repo를 건드리지 않는다.
  단 preppers dev가 C로 돌고 있어 **C의 흡수는 별도 결정으로 남긴다.**

## 전제 조건

하나라도 깨지면 해당 서비스에 적용하지 않는다.

1. `buildspec.yml`에서 `kubectl apply` 제거 완료(해당 브랜치)
2. ArgoCD 인수 완료(`Synced/Healthy`) + Image Updater write-back 실증
3. `TARGET_ENV`가 프로젝트 환경변수로 이관됨 — **파이프라인 삭제보다 선행**
4. (dev) dev1/dev2의 CodeBuild 프로젝트 공유 구조 해소

## 결과

**얻는 것**

- 서비스당 관리 지점 2개 → 1개. "이 서비스는 어떻게 배포되나"의 답이 프로젝트 1개 + git 1곳으로 수렴한다.
- 환경변수 출처 추적이 끝난다.
- 롤백이 CI에서 독립한다(GitOps 전환의 효과가 구조로 굳는다).

**감수하는 것**

- 파이프라인 실행 이력 UI 상실. 커밋↔빌드 대조는 `resolvedSourceVersion` 조회로 대체된다 — 더 불편하다.
- CodePipeline식 직렬화(대기 후 실행)가 없다. 순서 역전이든 push 유실이든 **알림이 울리지 않는다.**
- webhook은 프로젝트당 1개. 브랜치별 환경 분기가 필요하면 프로젝트를 늘려야 한다.
- 트리거 설정이 프로젝트 속성으로 들어간다. 콘솔 수기 관리에서는 변경 추적이 어려워진다 — IaC 필요성이 커진다.
- CI 쪽 승인 게이트 선택지를 닫는다. 승인은 ArgoCD 수동 sync와 PR 리뷰로 일원화된다.

## 재검토 조건

- CI에 다단계(테스트→빌드→스캔→승인)가 필요해지면 재검토. 단 후보는 CodePipeline이 아니라 batch build 또는 GH Actions.
- 태그 스킴을 `{빌드시각}-{sha8}` + `alphabetical`로 개편하면 결정 4를 완화할 수 있다 → 후속 ADR로 대체.
- 전제 1~2가 깨진 서비스가 발견되면 그 서비스는 즉시 대상에서 뺀다.
