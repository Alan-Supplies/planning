## 테스트 코드
1. 테스트 코드는 /test/{도메인} 폴더에 작성
2. 테스트 플랜은 코드로 구현하지 않고 목차로 작성한다.
3. 테스트 가독성은 매우 중요하다.
4. 테스트에 필요한 날짜는 UTC+9:00 으로 진행한다.
5. 검증해야할 object의 property가 다수 일경우 toMatchObject 또는 대응하는 것으로 비교한다.
6. 테스트 코드 작성후 성공할 때까지 반복한다.
7. e2e테스트 실행 시 `required_permissions: ["all"]` 필수 (DB 연결 + 프로세스 종료 권한)
8. 참고할 기존 테스트 패턴:
  - KDS DB 사용: `test/customer-order/setup.ts`의 `createTestAppWithKds`
  - 시간대 처리: `CONVERT_TZ(column, '+00:00', '+09:00')`
  - afterAll: 데이터 정리 실패 시 console.warn 출력
9. 같은 쿼리의 API호출이면 테스트 케이스를 나누지 않는다.
10. 특별히 중요한 요소가 아니면 object 비교는 toMatchObject 또는 대응하는 것으로 비교한다.
### TDD 요청 시
1. TDD방식을 요청할 시 테스트를 먼저 작성, 이후 코드 구현 전에 적용할 지 물어본후 수정한다.
2. 테스트는 하나씩 진행하며 STUB 파일 생성하면서 진행한다. 
