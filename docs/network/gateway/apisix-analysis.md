## 기능
### plugin
- jwt_auth
  ALB 가능
- request_id
  ALB 가능
- ctx
  헤더 평탄화 필요한가?
  APISIX lua script는 유지보수가 좋지 못하다.
  사례:
  1. jwt base64 해석중 한글 해독 오류
    결과는 apisix오류가 아닌 {} 반환
    에러 디버깅 불가능
    -> 다른 base64 사용으로 해결
  2. jwt_auth의 hideCredentials: false 설정시 사용 불가
    해석한 토큰을 다시 넘기지 않기 위한 옵션
    문제는 ctx의 pre-function 이전에 작동해서 ctx에서 토큰 인식 불가
    {} 반환으로 gateway 오류 없음 디버깅 불가
