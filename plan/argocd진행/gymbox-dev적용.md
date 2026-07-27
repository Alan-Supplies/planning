# 짐박스 개발 서버 적용

## 목표

`platform-gitops`에서 gymboxx app-server의 개발 서버 배포 구성을 반영한다.

- 작업 브랜치: `feature/gymboxx-dev-onboarding-app-server`
- 대상 환경: gymboxx dev

## 현재 상태

- Slack token Secret 처리에 예상보다 시간이 소요되었다.
- 관련 `platform-gitops` 변경은 PR을 제출했다.
- `platform-iac`에서 `argocd-image-updater`를 작업하고 있다.
- `platform-gitops`에 Image Updater 애노테이션을 설정하는 중이다.

## 진행 순서

1. `platform-gitops` PR의 검토 결과를 확인하고 필요한 내용을 보완한다.
2. `platform-iac`의 `argocd-image-updater` 구성을 마무리한다.
3. `platform-gitops`의 Image Updater 애노테이션 설정을 완료한다.
4. 개발 클러스터에 적용한 뒤 ArgoCD가 `Synced/Healthy`인지 확인한다.
5. 이미지 자동 갱신과 개발 서버의 기본 동작을 검증한다.

## 완료 조건

- 필요한 변경이 `platform-gitops`에 반영되어 있다.
- gymboxx app-server dev Application이 `Synced/Healthy` 상태다.
- 개발 서버의 기본 요청이 정상 동작한다.
