# 주문 영수증 처리 리팩터링 방향

## 목적

`OrderService.processReceipt`는 현재 영수증 수신 이후의 핵심 처리 흐름을 담당한다. 동작 자체는 명확하지만, 함수 하나에 상태 전이, DB 저장, 도메인 판단, 외부 연동, Slack 알림, 예외 정책이 함께 모여 있어 향후 변경 비용이 커질 수 있다.

이 문서는 현재 구현을 비판하기보다, 프레퍼스 주문/영수증 도메인의 운영 리스크를 줄이기 위한 리팩터링 방향을 정리한다.

## 현재 구조 요약

대상 함수: `src/module/order/order.service.ts`의 `processReceipt`

현재 함수는 대략 다음 일을 한 번에 수행한다.

- `order_receipt` 상태를 `PROCESSING`, `SKIPPED`, `FAILED`, `SUCCESS`로 변경하고 저장한다.
- 매장용 영수증을 필터링한다.
- 매장 정보, store unique id, position order를 조회한다.
- `MenuInfo`를 초기화하고 파싱된 메뉴를 `OrderInfo`로 변환한다.
- 메뉴 매칭, 가격 누락, 메뉴 없음 같은 검증과 Slack 알림을 처리한다.
- Firestore 저장용 주문 객체를 보정한다.
- Firestore에 주문을 저장한다.
- Order Server API 요청 body를 만들고 API를 호출한다.
- 각 실패 지점에서 상태 저장, retry 증가, Slack 알림, 예외 전파 여부를 결정한다.

함수 길이는 약 230라인이며, 단순한 순차 처리라기보다 여러 정책이 한 곳에 모인 오케스트레이션 함수에 가깝다.

## 유지보수 관점의 문제

### 1. 상태 전이와 저장 책임이 흩어져 있음

현재는 여러 분기에서 `receipt.status`를 직접 바꾸고 `orderReceiptRepository.save(receipt)`를 호출한다.

예를 들어 `FAILED`, `SKIPPED`, `SUCCESS` 처리가 함수 곳곳에 반복된다. 이 구조에서는 실패 사유 컬럼 추가, retry 정책 변경, 상태별 기록 방식 변경이 생겼을 때 모든 분기를 찾아 수정해야 한다. 누락 가능성도 높다.

### 2. 엔티티가 처리 흐름 전체를 지나가며 계속 변경됨

`OrderReceiptEntity`가 `processReceipt`에 전달된 뒤 여러 외부 연동 사이에서 직접 변경된다. 엔티티 전달 자체가 항상 문제는 아니지만, 현재처럼 긴 함수 내부에서 계속 mutate하고 저장하면 상태 변경 시점을 추적하기 어려워진다.

유지보수자는 "이 receipt는 어느 조건에서 어떤 최종 상태가 되는가"를 확인하기 위해 함수 전체를 따라가야 한다.

### 3. 도메인 판단, 외부 연동, 알림 정책이 섞여 있음

플랫폼 식별 실패, 메뉴 없음, Firestore 실패, Order Server 실패는 성격이 다르다. 그런데 현재는 한 함수 안에서 각각의 상태 저장, Slack 알림, throw 여부를 직접 결정한다.

그 결과 실패 정책의 일관성을 파악하기 어렵다. 어떤 실패는 retryCount를 증가시키고, 어떤 실패는 증가시키지 않으며, 어떤 실패는 throw하고 어떤 실패는 return한다.

### 4. 테스트 단위가 커짐

현재 구조를 테스트하려면 repository, Slack, Firestore, Order Server, `MenuInfo` static 상태, store repository 함수까지 함께 고려해야 한다. 작은 단위로 검증하기 어렵고, 테스트가 통합 테스트에 가까워진다.

## 리팩터링 원칙

이번 리팩터링은 기능 변경이 아니라 구조 정리를 목표로 한다.

- 기존 동작과 상태 결과를 먼저 보존한다.
- 한 번에 큰 구조를 바꾸기보다 상태 저장 책임부터 모은다.
- `processReceipt`는 전체 흐름을 읽을 수 있는 오케스트레이션 역할로 축소한다.
- DB 상태 변경은 명시적인 메서드로 모은다.
- 외부 연동과 데이터 변환은 단계별 private 메서드로 분리한다.
- 도메인 정책상 의도적인 차이인지 우연한 차이인지 구분해 문서화한다.

## 권장 리팩터링 단계

### 1단계: Receipt 상태 전이 메서드 분리

가장 먼저 `receipt.status = ...`, `retryCount += 1`, `save(receipt)`를 별도 메서드로 모은다.

예상 메서드:

```ts
private async markReceiptProcessing(receiptId: number, decodedText: string): Promise<OrderReceiptEntity>

private async markReceiptSkipped(
  receiptId: number,
  parsed: ParsedReceipt,
): Promise<OrderReceiptEntity>

private async markReceiptFailed(
  receiptId: number,
  options?: { incrementRetry?: boolean },
): Promise<OrderReceiptEntity>

private async markReceiptSuccess(
  receiptId: number,
  parsed: ParsedReceipt,
): Promise<OrderReceiptEntity>
```

가능하면 `save(entity)`보다 `update(id, partial)` 또는 `preload + save`처럼 변경 컬럼이 드러나는 방식을 검토한다. 다만 반환값으로 최신 entity가 필요하다면 현재 응답 형태와 맞춰 결정한다.

이 단계의 목적은 상태 전이 정책을 한 곳에 모으는 것이다. 기능 동작은 바꾸지 않는다.

### 2단계: 처리 단계별 메서드 분리

`processReceipt` 내부의 큰 블록을 의미 단위로 나눈다.

예상 메서드:

```ts
private async buildStoreContext(storeId: number): Promise<{
  storeUid: string | number
  positionOrder: POSITION_ORDER
  storeLabel: string
}>

private buildOrderInfo(parsed: ParsedReceipt, positionOrder: POSITION_ORDER): OrderInfo

private buildFirestoreOrder(orderInfo: OrderInfo): OrderInfo

private async storeOrderToFirestoreAndBuildMenus(
  storeUid: string | number,
  orderForFirestore: OrderInfo,
  orderInfo: OrderInfo,
): Promise<PreppersOrderMenu[]>

private async sendOrderToOrderServer(
  storeId: number,
  orderForFirestore: OrderInfo,
  preppersMenus: PreppersOrderMenu[],
): Promise<void>
```

이렇게 나누면 `processReceipt`는 다음처럼 흐름만 보여주는 함수에 가까워진다.

```ts
await this.markReceiptProcessing(receiptId, decodedText)

if (parsed.receiptType === 'STORE') {
  return await this.markReceiptSkipped(receiptId, parsed)
}

const context = await this.buildStoreContext(storeId)

if (parsed.platform === 'UNKNOWN') {
  await this.markReceiptFailed(receiptId)
  await this.sendReceiptError(...)
  return ...
}

const orderInfo = this.buildOrderInfo(parsed, context.positionOrder)
this.validateOrderInfo(...)

const orderForFirestore = this.buildFirestoreOrder(orderInfo)
const preppersMenus = await this.storeOrderToFirestoreAndBuildMenus(...)
await this.sendOrderToOrderServer(...)

return await this.markReceiptSuccess(receiptId, parsed)
```

### 3단계: 실패 정책 정리

현재 실패별 처리 정책을 명시적으로 정리한다.

예시:

| 상황 | 현재 상태 | retryCount | throw 여부 | Slack |
|---|---|---:|---|---|
| decode/parse 실패 | `FAILED` | 증가 | throw | 없음 |
| 매장용 영수증 | `SKIPPED` | 증가 안 함 | return | 없음 |
| 플랫폼 식별 실패 | `FAILED` | 증가 안 함 | return | 전송 |
| 매장/메뉴 초기화 실패 | `FAILED` | 증가 | throw | 전송 |
| 메뉴 없음 | `SKIPPED` | 증가 안 함 | return | 전송 |
| Firestore 저장 실패 | `FAILED` | 증가 | throw | 전송 |
| Order Server 실패 | `FAILED` | 증가 | throw | 전송 |

이 표를 기준으로 의도된 정책인지 확인한다. 특히 `FAILED`인데 retryCount를 올리지 않는 케이스가 의도인지 검토가 필요하다.

### 4단계: 테스트 보강

리팩터링은 기능 변경이 아니므로, 먼저 현재 동작을 고정하는 테스트가 필요하다.

우선순위:

- 매장용 영수증은 `SKIPPED`가 되고 Firestore/Order Server로 전송되지 않는다.
- 플랫폼 식별 실패는 `FAILED`가 되고 Slack 알림을 보낸다.
- 메뉴 없음은 `SKIPPED`가 되고 Slack 알림을 보낸다.
- Firestore 실패는 `FAILED`, retry 증가, Slack 알림, 예외 전파가 발생한다.
- Order Server 실패는 `FAILED`, retry 증가, Slack 알림, 예외 전파가 발생한다.
- 정상 처리 시 `SUCCESS`, platform, serviceType, orderedAt이 저장된다.

테스트가 어렵다면 첫 단계에서는 `markReceipt...` 메서드 단위 테스트와 replay 기반 통합 테스트를 병행한다.

## 권장 최종 구조

`OrderService`에 모든 책임을 계속 두기보다, 추후에는 다음처럼 분리할 수 있다.

- `OrderService`: API 진입점과 전체 use case 오케스트레이션
- `ReceiptStateService` 또는 private state methods: `order_receipt` 상태 전이와 저장 정책
- `ReceiptOrderBuilder`: `ParsedReceipt`를 `OrderInfo`와 Order Server body로 변환
- `ReceiptIntegrationService`: Firestore, Order Server 연동
- `ReceiptNotificationService`: Slack 알림 메시지 구성과 전송

다만 현재 단계에서는 클래스를 과하게 늘리기보다 `OrderService` 내부 private 메서드 분리부터 시작하는 편이 안전하다.

## 리뷰 전달 문구

구현자의 의도를 인정하면서, 도메인 유지보수 리스크를 중심으로 전달한다.

> 전체 흐름은 이해했고, raw 영수증을 먼저 저장한 뒤 상태를 남기면서 처리하려는 방향은 맞다고 봅니다.
> 다만 프레퍼스 주문/영수증 쪽은 앞으로 예외 케이스나 재처리 정책이 계속 붙을 가능성이 높아서, 지금처럼 `processReceipt` 안에서 엔티티를 직접 수정하고 여러 분기에서 `save`하는 구조는 유지보수 비용이 커질 것 같습니다.
>
> 특히 `FAILED`, `SKIPPED`, `SUCCESS` 전이가 함수 곳곳에 흩어져 있어서, 실패 사유나 retry 정책이 바뀔 때 누락 가능성이 있어 보여요.
> 기능 동작을 바꾸자는 의미는 아니고, 우선 상태 저장 책임만 `markProcessing`, `markFailed`, `markSkipped`, `markSuccess` 같은 메서드로 모아보면 좋겠습니다.

피하는 것이 좋은 표현:

- "이렇게 엔티티 넘기는 건 안 좋아요."
- "함수가 너무 지저분해요."
- "왜 이렇게 했어요?"
- "SRP 위반이에요."

권장 표현:

- "현재 동작은 이해했고, 도메인 특성상 예외가 늘어날 때 위험해 보여요."
- "상태 전이 정책이 흩어져 있어서 한 곳으로 모으면 좋겠습니다."
- "기능 변경보다는 유지보수성 관점에서 구조를 정리하고 싶습니다."

## 결론

현재 구현은 당장 동작 관점에서는 유지 가능하다. 하지만 `processReceipt`는 주문/영수증 도메인의 핵심 흐름이며, 앞으로 예외 케이스와 운영 정책이 늘어날 가능성이 높다.

따라서 현 상태를 장기 유지하기보다는, 먼저 receipt 상태 전이와 저장 책임을 한 곳으로 모으고 이후 처리 단계를 의미 단위로 분리하는 방향이 좋다. 이 접근은 구현자의 기존 작업을 존중하면서도, 도메인 오너십 관점에서 운영 리스크를 줄이는 현실적인 리팩터링이다.
