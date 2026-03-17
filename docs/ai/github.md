## Github
1. 베이스 브랜치는 'develop'
2. 푸시 요구 할 때
  require-permission: ['all']
  커밋 메시지는 브랜치 이름 기반
  branch: {type}/{issue-number}/{title}
  message: {type}: {issue-number} {변경 내용 요약}
  example:
  feature/SUP-1886/dual-write 일 경우 커밋메시지는
  feature: SUP-1886 dual-write 기능 추가
3. PR형식
  - 샌드박스 사용하지 않음
  - title: {gitmoji}{issue-number} {변경 내용 요약}
  - info main일 경우 title: Release {gitmoji}{issue-number} {변경 내용 요약}
