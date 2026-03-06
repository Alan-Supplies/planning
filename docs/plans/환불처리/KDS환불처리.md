### 정책
취소 승인이 혼란이 올 수 있다.
KDS에거 취소 승인 또는 확정은 payment에 관여하지 않는다.

취소 요청은
1. kiosk인경우
  payment.status = pending
2. 그외
  payment.status = success

취소 요청은 서로 다른 층위의 두가지가 있다.
실제 환불 상태 payment.status
kds화면 상에서 상태 firestore.is_cancel_requested
payment.status가 pending, success 관련없이 is_cancel_requested 상태는 변경 가능하다.

pending 취소시 is_cancel_requested도 취소하는가?