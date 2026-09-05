# 옵션 매핑 수정 계획 (`option` vs `options`)

## 용어

현재 옵션 테이블이 2개 사용 중이고 이름이 유사하므로 문서에서는 아래 용어를 사용한다.

- `option`: 프레퍼스 표준 옵션. `food_option`으로 부른다.
- `options`: 기존 레거시 배달 플랫폼 옵션 매칭 테이블. `platform_option`으로 부른다.
- `platform`: PREPPERS가 아닌 모든 배달 플랫폼을 통합해서 관리한다.

## 수정 대상과 책임

- `preppers-kds-serverless`: 영수증을 파싱하고, 배달 플랫폼 옵션의 원본 `name`을 order-server로 전달한다.
- `preppers-order-server`: 주문 저장 전에 옵션 매핑을 최종 확정하고 `customer_order_food_option`에 저장한다.

매핑 책임은 `preppers-order-server`에 둔다. `option_id`, `name`, 미매핑 처리, nullable 저장 규칙은 주문 저장 도메인 규칙이므로 DB 저장 직전에 한 곳에서 판단한다.

## 현재 상태

1. 옵션 저장 로직은 `preppers-order-server`에 있다.
2. 현재 `customer_order_food_option.option_id`에는 `platform_option.id`가 들어간다.
3. `platform == PREPPERS` 기준 분기가 실제 DTO/enum 값과 일치하는 것은 확인했다.
4. 기존 데이터 마이그레이션은 하지 않는다. 기존 데이터가 깨져도 이번 작업 범위에서는 허용한다.

## 저장 규칙

1. `customer_order_food_option.option_id`에는 항상 `food_option.id`만 저장한다.
2. 배달 플랫폼 옵션 매핑 실패 시 `option_id`는 `null`로 저장한다.
3. `customer_order_food_option.name` 컬럼을 추가해 옵션 이름 스냅샷을 저장한다.
4. 매핑 성공 시 `name`에는 `food_option_detail.name`을 저장한다. 기준은 `country_code = KOR`이다.
5. 매핑 실패 시 `name`에는 원본 배달 옵션명을 저장한다.
6. 미매핑 옵션도 주문 생성은 실패시키지 않고 그대로 표시한다.

## 매핑 흐름

### PREPPERS 주문

1. 클라이언트가 `food_option.id`를 전달한다.
2. `customer_order_food_option.option_id = food_option.id`로 저장한다.
3. `food_option_detail(country_code = KOR)`에서 이름을 조회해 `customer_order_food_option.name`에 저장한다.

### 배달 플랫폼 주문

1. `preppers-kds-serverless`가 영수증에서 옵션 원본 `name`을 추출해 전달한다.
2. `preppers-order-server`가 옵션명을 정규화해 `platform_option.name`과 조회한다.
3. 매칭 성공 시 `platform_option.option_id`를 `food_option.id`로 사용한다.
4. 매칭 성공 시 `food_option_detail(country_code = KOR)`에서 food option name을 조회해 `customer_order_food_option.name`에 저장한다.
5. 매칭 실패 시 `customer_order_food_option.option_id = null`, `customer_order_food_option.name = 원본 배달 옵션명`으로 저장한다.

## 정규화 규칙

정규화는 조회 시에만 사용하고 DB에는 정규화 값을 저장하지 않는다.

- 공백 제거
- 대소문자 무시

`platform_option.name`은 플랫폼 공통 unique로 관리한다. 같은 이름이 다른 `food_option`을 가리키는 경우는 없다고 본다.

## 반영 범위

1. `preppers-order-server`
   - `customer_order_food_option.option_id` nullable 반영
   - `customer_order_food_option.name` 컬럼 추가
   - `platform == PREPPERS` / `platform != PREPPERS` 옵션 저장 분기 수정
   - 배달 플랫폼 옵션명 정규화 조회
   - 미매핑 옵션 저장 처리
2. `preppers-kds-serverless`
   - 영수증 옵션 원본 `name`을 order-server로 전달
   - serverless 내부에서 매핑을 최종 확정하지 않음

## 테스트 케이스

1. PREPPERS 주문: `food_option.id`가 그대로 저장되고 `name`은 KOR food option name으로 저장된다.
2. 배달 플랫폼 주문 매핑 성공: 원본 옵션명이 `platform_option.name`에 매칭되고 `food_option.id` / KOR food option name이 저장된다.
3. 배달 플랫폼 주문 매핑 실패: `option_id = null`, `name = 원본 배달 옵션명`으로 저장되고 주문 생성은 성공한다.
4. 정규화 매칭: 공백과 대소문자가 달라도 같은 `platform_option.name`으로 조회된다.
5. `platform_option.name` unique 제약이 유지된다.

