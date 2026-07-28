# 짐박스 개발 서버 적용

## 목표

`platform-gitops`에서 gymboxx app-server의 개발 서버 배포 구성을 반영한다.

- 작업 브랜치: `feature/gymboxx-dev-onboarding-app-server`
- 대상 환경: gymboxx dev

## 현재 상태

- Slack token Secret 처리에 예상보다 시간이 소요되었다.
- 관련 `platform-gitops` 변경은 PR #14를 제출했다.
- `platform-iac`의 `argocd-image-updater` 구성은 PR #34를 제출했다.
- `platform-gitops` PR #13과 #14가 충돌하지 않고, 함께 반영되면 10개 서비스가 공통 애노테이션을 상속하는 것을 확인했다.
- 7개 서비스의 `values-dev.yaml` 이미지 태그가 live 상태와 달라 적용을 잠시 중단했다. 오늘 공용 라이브러리 업데이트에 따른 정상 재빌드 결과인지 확인해야 한다.

## 진행 순서

1. ECR 이미지 생성 시각과 빌드 이력을 공용 라이브러리 업데이트 시점과 비교한다.
2. 7개 서비스의 이미지 태그 차이가 정상 재빌드 결과인지 확인한다.
3. `platform-iac`와 `platform-gitops` PR의 검토 결과를 확인하고 필요한 내용을 보완한다.
4. 개발 클러스터에 적용한 뒤 ArgoCD가 `Synced/Healthy`인지 확인한다.
5. 이미지 자동 갱신과 개발 서버의 기본 동작을 검증한다.

## 배포 경로 원칙

- ArgoCD Image Updater는 ECR의 최신 이미지와 현재 live 이미지를 비교해 갱신 필요 여부를 판단한다.
- 다른 경로에서 배포하면 Git에 기록된 원하는 상태와 live 상태 사이에 드리프트가 발생하고, Image Updater의 판단 기준도 흔들린다.
- 따라서 배포 경로를 ArgoCD로 단일화하고, 다른 경로의 직접 배포는 제거하거나 중단해야 한다.

## 완료 조건

- 필요한 변경이 `platform-gitops`에 반영되어 있다.
- gymboxx app-server dev Application이 `Synced/Healthy` 상태다.
- 개발 서버의 기본 요청이 정상 동작한다.
