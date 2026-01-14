---
name: 프로젝트 정리 및 GitHub 업로드
overview: 철자 교정(planing -> planning), Git 초기화 및 GitHub(Alan-Supplies/planning) 저장소 업로드를 진행합니다.
todos:
  - id: git-init-remote
    content: Git 초기화 및 리모트 설정
    status: completed
  - id: git-initial-commit
    content: 초기 파일 커밋 (규칙 기반 메시지)
    status: completed
  - id: git-push-to-github
    content: GitHub(Alan-Supplies/planning)으로 푸시
    status: completed
---

# 프로젝트 정리 및 GitHub 업로드 플래닝

## 1. 철자 교정 및 정리
- 현재 작업 디렉토리 이름 `planing`을 `planning`으로 변경 제안
- 문서 내 오타 확인 및 수정

## 2. Git 설정 (Repo 규칙 준수)
- 저장소 초기화: `git init`
- 브랜치 전략: `{type}/{issue-number}/{title}` 형식 준수
  - 초기 업로드용 브랜치: `feature/SUP-1/init-project`
- 리모트 추가: `https://github.com/Alan-Supplies/planning.git`

## 3. 커밋 및 푸시
- 커밋 메시지 규칙 준수: `{type}: {issue-number} {변경 내용 요약}`
  - 예: `feature: SUP-1 초기 프로젝트 구성 및 통계 개선 플랜 추가`
- `git_write` 및 `network` 권한을 사용하여 푸시 진행

## 주의 사항
- 샌드박스를 해제하고 작업을 진행해야 합니다 (`all` 권한 필요).
- GitHub에 `planning`이라는 이름의 저장소가 미리 생성되어 있어야 합니다.