다음은 현재까지 합의한 KDS 아키텍처와 일정 컨텍스트입니다.
이 컨텍스트를 기준으로 전체 일정 중 특정 단계의 세부 설계/구현/검토를 이어서 논의하고 싶습니다.
답변 시에는 먼저 해당 단계의 목표, 결정해야 할 것, 산출물, 리스크를 정리해 주세요.

[프로젝트 배경]
- 프레퍼스 KDS(주방 디스플레이 시스템) 개발
- 목표: 주문이 들어오면 주방이 최대한 빨리 인지할 수 있게 한다
- 단, 완전 즉시 반응까지는 필수는 아님
- 현재 매장 수: 41개
- 이벤트/실시간 전달은 매장별로 분리되어야 함

[핵심 아키텍처 원칙]
- 주문 관련 저장소는 MySQL 단일 저장소로 운영
- Firestore는 사용하지 않음
- KDS_SERVER는 별도 서버로 둠
- ORDER_SERVER와 KDS_SERVER는 의존성을 분리
- KDS_SERVER는 BFF 성격을 유지
- AUTH는 JWT 발급만 담당
- 인증은 APISIX에서 수행
- KDS_SERVER는 비즈니스 처리 담당

[실시간 전달 구조]
- binary log 방식은 사용하지 않기로 함
- webhook은 ORDER_SERVER -> KDS_SERVER 역방향 흐름이 생겨서 사용하지 않기로 함
- MQ/Kafka는 현재 단계에서는 도입하지 않기로 함
- 대신 outbox event polling 방식 사용
- polling 전용 pod 1개를 따로 둠
- polling pod가 outbox를 읽고 Redis Pub/Sub로 다른 KDS_SERVER pod들에 신호 전달
- 각 KDS_SERVER pod는 Redis subscribe 후 해당 매장 SSE 연결에만 전달
- Redis는 우선 KDS_SERVER 전용으로 둠

[Redis 관련]
- 현재 클러스터에는 Redis 없음
- KDS_SERVER용 Redis를 새로 설치
- Redis는 신호 전달용(pub/sub)으로만 사용
- Redis를 정답 저장소로 사용하지 않음
- 진실의 원천(source of truth)은 MySQL
- Redis 설치도 일정에 포함 필요

[도메인 모델 / 테이블 방향]
1. KDS 조회 모델 테이블
- KDS는 주문 단위로 동작
- order_item 단위 처리는 제한적
- 조회 모델에는 주문 정보 + 주문 처리 상태가 같이 들어감
- 단순 order_status 라는 이름은 의미가 너무 좁다고 판단
- 현재 후보/논의 포인트:
  - kds_orders
  - 또는 KDS 주문 조회 모델에 맞는 이름
- 이 테이블이 KDS의 현재 화면 기준 데이터가 됨

2. 액션 기록 테이블
- 단순 이벤트 원장보다는 “액션으로 상태를 바꾸는 흐름”이 핵심
- 로그/기록 테이블은 event보다 action log 의미가 더 맞음
- 후보:
  - order_action_logs
  - 또는 kds_order_action_logs

3. Outbox 테이블
- outbox_events는 이름이 모호해서 더 도메인 친화적으로 바꾸려 함
- 현재 추천 이름:
  - kds_order_outbox

[주문 처리 원칙]
- KDS 액션은 주문 상태를 변경하는 것이 핵심
- 로그는 부수 기록
- 액션별 실행은 한 device에서만 가능하다고 가정
- 중복 요청/멱등성은 현재 우선순위에서 제외
- 동시성/중복 방지는 운영에서 문제 발생 시 후속 대응 가능
- 다만 이 판단은 “문제가 없어서 제외”가 아니라 “현재 가정 하에서 후순위로 미룬 것”임

[API / 처리 흐름]
- KDS는 상태 변경 API를 호출
- 서버는 액션 검증 후 조회 모델 상태를 변경
- action log를 기록
- outbox row를 생성
- polling pod가 outbox를 읽음
- Redis Pub/Sub로 KDS_SERVER pod들에 store_id 기준 전달
- 각 pod는 자기 SSE 연결 중 해당 store_id 연결에만 전달
- KDS 클라이언트는 SSE로 변경 알림을 받고 필요 시 조회 API로 재조회

[SSE 관련]
- SSE는 처음 적용
- 그래서 본 구현 전에 SSE 테스트 구현을 먼저 올려 검증하려고 함
- 확인 포인트:
  - 연결 유지
  - 재연결
  - APISIX 뒤 동작
  - 클라이언트 수신 방식
  - 매장별 전달

[현재 아키텍처 판단 요약]
- Firestore를 쓰면 구현은 쉬워 보이지만, 같은 도메인을 두 저장소로 운영하는 부담이 더 크다고 판단
- 그래서 MySQL 일원화를 유지
- 대신 구현 복잡도가 올라가므로 outbox polling + Redis Pub/Sub 방식으로 절충
- BFF는 유지하고 ORDER_SERVER 직접 SSE는 하지 않기로 함

[현재 일정 초안]
- 주문 처리 설계
- KDS 주문 조회 모델 설계
- KDS 주문 조회 모델 DB 설계
- SSE 설계
- SSE 테스트 구현
- kds_order_outbox 설계
- KDS Redis 설계
- KDS Redis 설치/배포
- KDS 토큰 발급
- KDS 토큰 APISIX 적용 확인
- 주문 처리 로그 DB 설계
- 조회 모델 상태변경 API
- 액션 로그 및 outbox 기록 구현
- kds_order_outbox polling 서버 구현
- Redis Pub/Sub 연동 구현
- 통합 테스트
- 배포
- 운영 로그 점검
- 모니터링

[새 채팅에서 원하는 방식]
- 전체 아키텍처를 다시 뒤엎기보다, 위 컨텍스트를 전제로 특정 단계만 깊게 논의하고 싶음
- 논의할 때는 항상 아래 형식으로 정리해 주면 좋겠음:
  1) 이 단계의 목표
  2) 결정해야 할 사항
  3) 추천안
  4) 구현 포인트
  5) 리스크
  6) 산출물 예시

이제 위 컨텍스트를 기준으로
[주문 처리 설계] 를 시작하려고 합니다.

### 액션 목록
- 조리 단계
    1. 플레이팅 완료
    2. 시어링 완료
    3. 음료 완료
    4. 마무리 완료
    5. 픽업 완료
- 주문 상태
    1. 주문 취소
    2. 보류
    3. 긴급
    4. 호출

현재 조리시작 액션은 없고 주문이 들어오면 조리를 시작하는 것으로 간주하고 있습니다.
