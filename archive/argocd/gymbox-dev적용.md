# 짐박스 개발 서버 적용

> 상태: **추가 검증 진행 중** (2026-08-03)

## 목표

`platform-gitops`에서 gymboxx app-server의 개발 서버 배포 구성을 반영한다.

- 작업 브랜치: `feature/gymboxx-dev-onboarding-app-server`
- 대상 환경: gymboxx dev

## 현재 상태

- 2026-07-29의 Image Updater 기반 적용과 초기 검증은 완료됐다.
- `platform-iac` PR #34와 `platform-gitops` PR #13·#14가 모두 반영됐다.
- Image Updater가 애노테이션이 적용된 Application을 인식하는 것을 확인했다.
- 최신 이미지 태그의 Git write-back을 확인했다.
- ArgoCD Application이 `Synced/Healthy` 상태임을 확인했다.
- 7개 서비스의 `values-dev.yaml` 이미지 태그가 live 상태와 달랐던 것은 공용 라이브러리 업데이트에 따른 정상 재빌드 결과였다.
- 현재는 검증 배포만 남았다. prod보다 dev를 먼저 검증한다.
- 레포별 build와 이미지 pulling을 분리한 PR을 먼저 머지해야 한다.
- PR 머지 후 서비스별로 `automated: auto`를 하나씩 적용하고, 검증이 끝난 뒤 다음 서비스로 진행한다.

## 진행 순서

1. [x] `platform-iac` PR #34와 `platform-gitops` PR #13·#14를 반영한다.
2. [x] Image Updater 로그에서 애노테이션이 적용된 Application을 인식하는지 확인한다.
3. [x] 최신 이미지 태그가 `values-dev.yaml`에 Git write-back되는지 확인한다.
4. [x] ArgoCD Sync 후 Application이 `Synced/Healthy`인지 확인한다.

## 추가 검증 순서

1. [ ] 레포별 build와 이미지 pulling 분리 PR의 대상과 머지 가능 상태를 확인한다.
2. [ ] 준비된 레포의 분리 PR을 머지한다.
3. [ ] 영향이 작은 dev 서비스 하나에 `automated: auto`를 적용한다.
4. [ ] `Synced/Healthy`, Pod 상태와 이미지 갱신·pulling을 확인한다.
5. [ ] 이상이 없을 때 다음 dev 서비스로 하나씩 확산한다.
6. [ ] dev 전체 검증 결과와 prod 전환 조건을 기록한다.

## 배포 경로 원칙

- ArgoCD Image Updater는 ECR의 최신 이미지와 현재 live 이미지를 비교해 갱신 필요 여부를 판단한다.
- 다른 경로에서 배포하면 Git에 기록된 원하는 상태와 live 상태 사이에 드리프트가 발생하고, Image Updater의 판단 기준도 흔들린다.
- 따라서 배포 경로를 ArgoCD로 단일화하고, 다른 경로의 직접 배포는 제거하거나 중단해야 한다.

## 완료 조건

- 필요한 변경이 `platform-gitops`에 반영되어 있다.
- gymboxx app-server dev Application이 `Synced/Healthy` 상태다.
- 이미지 자동 갱신의 Git write-back이 검증되어 있다.
- 레포별 build와 이미지 pulling 분리 PR이 반영되어 있다.
- dev 서비스별 `automated: auto` 검증이 완료되어 있다.
