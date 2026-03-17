## Jira
1. Jira 이슈 검색 가중치
  1. Assign: Alan-Supplies
  2. 업무영역: 프레퍼스, Preppers
  3. 제외: 짐박스, Gymboxx
2. Jira 설정
  프로젝트: SUP (Product)
  이슈 타입: Task (기능 개발), Bug (버그 수정)
3. Jira 이슈 생성시 제목에 아래처럼 접두사를 붙인다.
  [Preppers] {제목}
4. 비정규 업무 이슈는 현재 스트린트의 비정규 업무의 서브태스크로 만든다.

### MCP 도구 호출 시
 - 파라미터 이름: camelCase 사용 (boardId, sprintId, issueKey 등)
 - Jira 이슈 검색: jira_search_issues + JQL 사용
 - 스프린트 이슈 검색 JQL 예시: project = SUP AND sprint in openSprints() AND summary ~ '키워드'
