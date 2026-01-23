## KDS 주문내역
1. 환불 상태 표시 안함
2. 결제 취소 삭제

## 주문 모달
1. 취소 제거 - pickup position

## admin
- 결제 목록은 없고 결제 내역만 조회
  주문번호 모를 경우?
### 결제 내역
- 필드: 상태, 주문 일시, 주문 번호, 플랫폼(device: platform), 식사 위치, 결제 상품, 결제 금액
  상태: 결제, 환불진행중, 환불
- action
  - 환불하기
    환불 모달 생성
  - 환불취소
    컨펌모달
  - 환불강제완료
    컨펌모달
- 조회 API
  GET /customer-orders/{id}
  params: storeId, orderNumber
- 환불 API 
  POST /customer-orders/{id}/refund
  params: status