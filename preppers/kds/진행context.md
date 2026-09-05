다음은 현재까지 합의한 프레퍼스 KDS 설계 컨텍스트입니다.
이 컨텍스트를 기준으로 [SSE 설계]를 이어서 논의하고 싶습니다.

[프로젝트 배경]
- 프레퍼스 KDS(주방 디스플레이 시스템) 개발
- 목표: 주문이 들어오거나 변경되었을 때 주방이 최대한 빨리 인지할 수 있게 한다
- 완전 즉시 반응까지는 필수는 아니지만, 실시간에 가까운 UX를 목표로 한다
- 현재 매장 수: 41개
- 이벤트/실시간 전달은 매장별로 분리되어야 한다

[핵심 아키텍처 원칙]
- 주문 관련 원장은 MySQL 단일 저장소로 운영
- Firestore는 사용하지 않음
- KDS_SERVER는 별도 서버로 둠
- ORDER_SERVER와 KDS_SERVER는 의존성을 분리
- KDS_SERVER는 BFF 성격을 유지
- AUTH는 JWT 발급만 담당
- 인증은 APISIX에서 수행
- KDS_SERVER는 비즈니스 처리 담당

[현재 실시간 전달 방향]
- binary log 방식은 사용하지 않음
- webhook은 ORDER_SERVER -> KDS_SERVER 역방향 흐름이 생겨서 사용하지 않음
- MQ/Kafka는 현재 단계에서는 도입하지 않음
- 기존 outbox event polling 방식도 검토했으나, 현재는 단순화를 위해 제외하는 방향
- KDS는 과거 이벤트 순서 보장이 필요하지 않음
- 재접속 시 조건에 부합하는 주문 전체를 다시 조회하는 전략

[현재 publish 전략]
- kds_order_outbox는 1차 구현에서 제외
- kds_orders.updated_at 기준 polling 사용
- polling 전용 pod 1개를 따로 둠
- polling pod가 kds_orders에서 updated_at 변경분을 조회
- 변경된 row들의 store_id를 수집
- store_id 기준으로 Redis Pub/Sub publish
- 각 KDS_SERVER pod는 Redis subscribe
- 각 pod는 자기 SSE 연결 중 해당 store_id 연결에만 전달

[Redis 관련]
- 현재 클러스터에는 Redis 없음
- KDS_SERVER용 Redis를 새로 설치해야 함
- Redis는 신호 전달용 Pub/Sub로만 사용
- Redis를 정답 저장소로 사용하지 않음
- source of truth는 MySQL
- Redis 설치/배포도 일정에 포함 필요

[KDS 조회 모델]
- kds_orders는 주문 원장이 아니라 KDS 화면 표시용 조회 모델
- 주문당 1 row
- 과거 상태 보관은 필요 없음
- 과거 상태는 action log 정도면 충분
- 메뉴/옵션 정보는 JSON snapshot으로 저장
- polling 기준으로 updated_at 사용

[주요 kds_orders 필드 방향]
- id
- storeId
- orderId
- orderNumber
- orderedAt
- platform
- serviceType
- device
- currentPosition
- status
- needsCutlery
- isUrgent
- hasCancelRequest
- requestedServiceType 또는 serviceTypeChange
- isOnHold
- hasOrderChangeRequest
- request
- foods JSON
- updatedAt

[상태/포지션 모델]
- currentPosition은 현재 KDS에서 주문이 표시되는 포지션
- position은 매장별 구성에 따라 다름
- 예시 1: PLATING -> PICKUP
- 예시 2: PLATING -> SEARING -> DRINK -> FINISHING -> PICKUP
- 포지션 전이는 백엔드가 매장별 flow 기준으로 계산
- 프론트는 다음 포지션을 직접 계산하지 않음
- COMPLETED는 status API에서 직접 받지 않음
- COMPLETED는 PICKUP 포지션 complete 결과로만 생성

[status / flag 정책]
- status는 KDS 주문의 진행/종료 상태
- status 후보:
  - ACTIVE
  - HOLD
  - CANCELED
  - COMPLETED
- URGENT는 ACTIVE 기반의 강조/우선순위 속성이므로 status에 넣지 않음
- isUrgent flag로 분리
- hasOrderChangeRequest, hasCancelRequest 같은 요청성 표시도 flag로 분리
- status 변경과 flag 변경 API는 구분

[현재 API 방향]
- 조회
  GET /kds/orders
  GET /kds/orders/{orderId}

- 포지션 처리
  PATCH /kds/orders/{orderId}/position/{position}/complete
  PATCH /kds/orders/{orderId}/position/{position}/revert

- 상태 변경
  PATCH /kds/orders/{orderId}/status/{status}
  단, COMPLETED는 직접 받지 않음

- flag 변경
  PATCH /kds/orders/{orderId}/flags

이제 SSE 설계를 진행해야 합니다.