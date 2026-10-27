# membership ↔ membership_order 관계 검토

2026-10-23 · 근거: gymboxx-lib main 엔티티, app-server main 코드, dev DB(2026-10-16 조회). 운영 DB 는 아직 확인하지 않았다.

## 결론

`membership_order N : 1 membership` 관계는 맞다. 문제는 주문이 계약 조건을 들고 있지 않아 회원의 권리와 일부 금액 계산이 상품 행을 실시간으로 따라가고, 한 행이 결제 기간·계약·운동복을 함께 떠안는 점이다.

## 1. 계약 조건이 주문에 스냅샷되지 않는다

출입 판정(`pass/modules/user/user.service.ts` `validateOrderAccess`)은 상품의 `gym`·`isAllBranchAccessible`·`oneDayAccessLimit`·`membership_gym_access` 를 읽고, 주문에서는 `expireAt` 만 쓴다.
PASS 환불은 사용일을 그 지점의 현재 SINGLE_SUBSCRIPTION `sellingPrice` 로 계산하고, 지점 변경 수수료도 상품의 현재 `sellingPrice`·`presalePrice` 를 쓴다.
가격은 HQ 가 새 상품 행으로 버전을 나누지만, 접근 지점·입장 횟수는 바꾸면 기존 회원 전원에게 소급된다 — 의도된 정책인지 확인이 필요하다.

## 2. 지점이 주문이 아니라 상품에 붙어 있다

`membership_order` 에 `gym_id` 가 없어, 지점 변경은 대상 지점에서 `type`·`oneDayAccessLimit`·`availableDays` 가 같은 상품을 찾아 새 주문을 INSERT 한다(`user.service.ts` `transferMembershipOrderGym`).
그래서 상품이 지점 수만큼 복제되고, 같은 스펙 상품이 없는 지점으로는 옮길 수 없다(404).

## 3. 결제 기간과 계약이 한 행에 섞여 있다

구독 갱신은 달마다 새 행을 INSERT 한다(배치 `renewUserOrder`, dev 에서 한 회원 최대 115행).
`parent_membership_order_id` 는 업그레이드·지점 변경에서만 채우고 갱신에서는 비우며, 읽는 곳도 FK·인덱스도 없다. 계약 묶음 키는 복사돼 내려가는 `subscription_started_at` 이 사실상 대신한다.

## 4. status 하나에 성격이 다른 상태가 섞여 있다

컬럼 주석(`ACTIVE, INACTIVE, HOLD, CHANGED, REFUNDED`)과 실제 enum(`NOT_STARTED, ACTIVE, INACTIVE, UNSUBSCRIBE, DOWNGRADED, REFUNDED, EXPIRED, REFUND_REQUESTED`)이 다르다.
생애주기·갱신 의사·환불이 한 컬럼에 있고, 정지는 `UNSUBSCRIBE + hold_at` 으로 표현한다(dev 에 `INACTIVE` 인데 `hold_at` 이 남은 행 50건). 운동복은 갱신 의사를 `sportswear_renewal_status` 로 따로 둔다.

## 5. 활성 주문 1개를 보장하는 장치가 없다

앱 구매 경로의 중복 검사가 주석 처리돼 있고(`purchaseUserMembership` 의 `checkUserHasMultipleMembership`), DB 제약도 없다.
출입 판정의 `getUserOrder`(`pass/modules/user/user.dao.ts`)는 `ORDER BY` 가 없어 활성 행이 둘이면 어느 행이 잡힐지 정해지지 않는다. dev 에서 겹치는 회원은 0명이며 운영은 확인이 필요하다.

## 6. amount·available_days 가 이중 출처다

`amount` 에는 경로마다 다른 값(상품가+운동복+락커, 업그레이드 차액, 지점 변경 수수료, 선물 0)이 들어가고, 환불은 이 값 대신 `payment_history.membership_amount` 를 쓴다(dev 2,213건 중 1,397건이 판매가와 다름).
주문의 `available_days` 는 HQ 의 주문별 override 인데 앱 서버는 시작 시 만료일 계산에만 쓰고 가격·환불·선물·지점 변경은 상품 값을 써서, override 된 주문은 계산마다 일수가 달라진다(dev 30건).

## 7. 운동복이 멤버십 주문 안에 있다

운동복은 따로 결제·정지·갱신되는 상품인데 `sportswear_id`·`sportswear_merchant_uid`·`sportswear_start_at`·`sportswear_renewal_status` 로 주문 행에 들어 있다. 같은 부가상품인 락커는 `locker_order` 로 분리돼 있다.

## 8. 스키마 정합성

- `membership_order` 는 `utf8mb3`, `membership` 은 `utf8mb4` 다.
- `payment_history.membership_order_id`, `presale_membership_order.membership_order_id` 에 FK 가 없다.
- `merchant_uid` 가 UNIQUE 가 아니고, dev 에 빈 문자열 8건·문자열 `'<null>'` 3건·같은 값 14회 사용이 있다.
- 엔티티 이름 `OrderEntity` 와 테이블 이름 `membership_order` 가 다르다.

## 손댄다면

기존 컬럼은 두고 옆에 추가한다.

1. 출입 판정 쿼리에 `ORDER BY id DESC` 를 넣고, 운영에서 활성 주문이 겹치는 회원을 조회한다.
2. 주문에 계약 조건 스냅샷(`gym_id`, `one_day_access_limit`, `is_all_branch_accessible`, `membership_type`)을 추가하고 읽는 쪽을 옮긴다 — 1·2 절이 함께 풀린다.
3. 갱신에서도 `parent_membership_order_id` 를 채우고 인덱스를 단다.
4. `status` 컬럼 주석을 실제 enum 에 맞춘다.

운동복 분리와 `amount` 의미 정리는 범위가 커서 별건으로 판단한다.
