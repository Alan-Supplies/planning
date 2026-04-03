### data-migration
- [ ] 기존 매출정보
- [ ] 프레퍼스 키오스크 주문 payments 만들기
- [ ] 환불 싱크
- [ ] customer-order method -> platform

- 기존 정보 지우기
  platform='preppers' and method != 'KIOSK'

---
## 삭제
1. 4/1 이전 payments 날리기 
2. 4/1 이전 customer-orders 날리기 method != 'KIOSK'
3. order.id 없는 payments 날리기
--

4/1 이후
-----
1. 이관된 포스
  payments.description != null
2. 이관된(중복) 키오스크
  method = "" and platform = 'PREPPERS'
3. 실제 키오스크
4. 실제 포스
## 이관
1. 기존 프레퍼스 CUstomerOrder -> payments
  정상 주문의 payments 생성하지 않도록 기준점 잘 잡아야 한다.
  sql로 진행 - 기준 점 잡기 어려우면 코드
  범위 확실하게 공유할 것
2. 셀버스, 포스, 배달
  scripts로 진행
  1. customer-order 생성
  2. payments 생성
