# Control characters in decoded string
_Exported on 2026. 4. 23. at 19시 4분 8초 GMT+9 from Cursor (3.1.17)_

---

**User**

@src/serialServer/serialServer.js:80 decodedString 에는 프린트 제어 문자가 들어있다.
sqs로는 전송되고 rest api 로는 전송시 오류가 날 수 있는가?

---

**Cursor**

## 결론부터

- **SQS 전송**: 현재 코드처럼 `JSON.stringify(...)`로 감싸서 보내기 때문에 **거의 문제없이 통과**합니다.
- **REST API 전송**: 어떻게 실어 보내느냐에 따라 **오류 가능성이 꽤 있습니다**. JSON body로 보내면 대개 괜찮지만, 헤더·쿼리·form-urlencoded, 또는 WAF/프록시가 개입하면 실패할 수 있습니다.

## 근거

### 1) `decodedString` 에 실제로 들어있는 것

```67:73:src/serialServer/serialServer.js
  async handleData (data) {
    try {
      const decodedString = this.decoder.decode(data)
```

POS 프린터는 ESC/POS 계열이라 `0x1B`(ESC), `0x1D`(GS), `0x0A`(LF), `0x00` 같은 C0 제어문자가 섞여 있습니다. `TextDecoder`는 1바이트 제어문자를 그대로 유니코드 코드포인트 U+0000~U+001F로 매핑하므로, 문자열 안에 말 그대로 C0 제어문자가 남아 있는 상태입니다.

### 2) SQS 경로

```27:31:queue.js
  const params = {
    MessageBody: JSON.stringify({shop_id: shopID, data: data, device: device}),
    QueueUrl: queueUrlProd
  }
```

- AWS SQS의 `MessageBody`는 **XML 1.0에서 허용되는 문자**만 받습니다. 즉 `#x9 | #xA | #xD | #x20-#xD7FF | ...` 만 허용되고, 그 외 C0 제어문자(`#x00`, `#x1B`, `#x1D` 등)는 **공식적으로 유효하지 않은 문자**입니다.
- 하지만 여기서는 `JSON.stringify`로 감싸기 때문에 `\u0000`–`\u001F` 범위의 문자가 전부 `\u001b` 같은 **6자 ASCII 이스케이프 시퀀스**로 바뀝니다. 그래서 실제로 SQS에 전달되는 페이로드에는 C0 제어문자가 남지 않아 에러가 나지 않는 것입니다.
- 즉 “SQS로 잘 가는” 진짜 이유는 SQS가 관대해서가 아니라 `JSON.stringify`가 한 번 이스케이프해주기 때문이라고 보시면 됩니다.

### 3) REST API 경로에서 터질 수 있는 포인트

어떤 방식으로 싣느냐가 핵심입니다.

(a) **JSON body (Content-Type: application/json)**  
`JSON.stringify`를 거쳐 보내면 SQS와 동일하게 제어문자가 이스케이프되므로 전송/파싱 자체는 대체로 성공합니다. 하지만 다음에서 문제가 생길 수 있습니다.

- **WAF / CloudFront / API Gateway / ALB / nginx**: 제어문자가 포함된 바디를 악성 트래픽으로 판단해 400/403으로 차단하는 경우가 있습니다. (특히 mod_security, AWS WAF의 기본 룰셋)
- **서버 측 입력 검증**: Laravel/Spring 등에서 컨트롤러 파라미터 validation에 `\p{C}` 또는 printable ASCII만 허용하는 규칙이 있으면 거부.
- **DB 저장 단계**: 받는 쪽이 이걸 그대로 MySQL(utf8mb4)에 넣으면 저장은 되지만, **XML/SOAP/프로토콜 버퍼로 재전달** 시 여기서 터집니다.

(b) **쿼리 스트링(URL) 또는 path 파라미터**  
`?data=...`로 붙이려면 `encodeURIComponent`가 필수입니다. 제어문자를 그대로 URL에 넣으면 “Invalid URL”로 fetch/axios 레벨에서 실패합니다.

(c) **application/x-www-form-urlencoded / multipart**  
`URLSearchParams`를 쓰면 내부적으로 percent-encoding 되어 전송은 되지만, 서버가 text로 받아 decode한 뒤 다시 XML/JSON/DB에 꽂을 때 문제될 수 있습니다.

(d) **HTTP 헤더**  
절대 금물입니다. Node의 `http`는 헤더 값에 `\r\n` 등이 들어있으면 `ERR_INVALID_CHAR`를 던지고, 다른 클라이언트는 응답 스플리팅 방지를 위해 `\x00–\x1F`를 거부합니다.

(e) **XML / SOAP 엔드포인트**  
SQS와 같은 이유로 C0 제어문자는 XML 1.0에서 invalid라서 파서 단계에서 바로 실패합니다.

### 4) 부가로 확인해볼 것

- 생성자에서 `encoding`을 받고 있어요.

```42:47:src/serialServer/serialServer.js
    if (!encoding) {
      throw new Error('encoding is required')
    }

    this.portPath = portPath
    this.decoder = new TextDecoder(encoding)
```
  
  `encoding`이 `euc-kr` / `cp949`처럼 multi-byte인 경우, ESC/POS 바이너리 바이트가 완성되지 않은 한글 바이트로 잡히면 `U+FFFD`(�)로 치환됩니다. 이 상태로 보내면 서버 쪽에서 한글이 깨져 보이고, 원본 바이너리 프로토콜도 복원이 안 됩니다. REST API로 “사람이 읽는 용도”라면 치명적이지는 않지만, 재인쇄 등 바이너리 재사용이 필요하면 base64 등으로 바꿔 보내는 게 안전합니다.

## 실무적 권장

1. REST API로 보낼 때는 반드시 **JSON body**에 실어 보내고, 수신 서버에 WAF가 있다면 C0 제어문자 통과 규칙을 확인.
2. 가능하면 원본 바이너리 그대로를 **Base64 인코딩**해서 `data_base64` 같은 필드로 전송하고, 서버에서 필요 시 디코딩하도록 설계. 이렇게 하면 SQS/REST/DB 어디서든 절대 깨지지 않습니다.
3. 사람이 읽을 텍스트만 필요하다면, 보내기 전에 C0 제어문자를 제거/치환:
   - 예: `data.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, '')`
4. 헤더·쿼리스트링에는 절대로 `decodedString`을 직접 싣지 않기.

요약하자면, “SQS는 `JSON.stringify` 덕에 살아남고, REST API는 JSON body면 대체로 괜찮지만 전송 방식/중간 네트워크 구성에 따라 충분히 400/403이 날 수 있다”가 답입니다.

---

**User**

관련 내용이 SQS에서 람다로 전송할 때 조용히 실패하는 원인이 될 수 있는가?

---

**Cursor**

## 결론

**가능합니다.** 다만 원인은 SQS → Lambda “전송 과정 자체”가 아니라, **Lambda 핸들러가 메시지를 꺼내 쓸 때(파싱 후 다운스트림 처리 단계)** 생기는 게 대부분입니다. 즉, 전송은 성공하지만 처리는 실패하는데도 SQS에서 메시지는 삭제되는 패턴이죠.

## 왜 SQS → Lambda “전송” 구간에서는 문제가 안 되는가

1. `queue.js`에서 `MessageBody: JSON.stringify({...})`로 한 번 감쌌기 때문에 C0 제어문자(`0x00`, `0x1B`, `0x1D` 등)는 이미 `\u001b` 같은 **ASCII 이스케이프 시퀀스**로 바뀐 상태로 저장됩니다. 그래서 SQS가 내부적으로 XML로 보관·재직렬화해도 깨지지 않습니다.
2. Lambda에 이벤트가 전달될 때 AWS가 `Records[].body`에 그 **이스케이프된 문자열** 그대로 실어 줍니다. 이 단계에서도 `JSON.parse`가 문제를 일으키지 않습니다.
3. `TextDecoder`는 기본 옵션에서 invalid 시퀀스를 `U+FFFD`로 치환하므로 lone surrogate가 만들어져 `JSON.stringify`가 잘못된 JSON을 뱉을 가능성도 낮습니다.

즉, “SQS가 메시지를 먹고 Lambda가 못 받는” 류의 실패는 이 제어문자 때문에 일어나기 어렵습니다.

## 그런데도 “조용히 실패”로 이어지는 현실적 경로

`data` 안의 제어문자는 `JSON.parse(body)` 이후 **원본 문자열로 복원**되어 Lambda 핸들러에 들어갑니다. 이 다음이 위험 구간입니다.

### 1) 다운스트림 호출에서 실패 → 핸들러가 에러를 삼킴
가장 흔한 조용한 실패 패턴입니다.
- Lambda가 이 `data`를 받아 REST API/DynamoDB/외부 XML 서비스로 재전송할 때, 앞 답변에서 말한 이유로 **400/403/XML parse 에러**가 납니다.
- 핸들러 내부에 `try/catch`가 있고 catch에서 로깅만 하고 `return` 하면, **Lambda는 성공으로 간주됨 → SQS는 해당 메시지를 삭제** → 처리는 안 됐는데 메시지는 사라집니다.
- CloudWatch Logs에만 에러가 남는데, 알람이 없다면 운영자 입장에서는 “조용히 사라진 영수증”이 됩니다.

### 2) 배치 실패 보고(ReportBatchItemFailures) 미사용
- SQS → Lambda는 기본적으로 배치로 동작합니다. 배치 중 일부 메시지가 실패했는데 핸들러가 전체를 `throw`하지 않고 성공 리턴하면, **실패한 메시지까지 SQS에서 삭제**됩니다.
- `ReportBatchItemFailures`를 켜고 `batchItemFailures`에 실패 ID를 담아 반환해야 실패 건만 재시도·DLQ로 갑니다. 이 설정이 없다면 제어문자 때문에 한 건이 터져도 티 안 나게 묻힙니다.

### 3) DLQ/maxReceiveCount 설정 부재
- Redrive policy/DLQ가 없으면 maxReceiveCount 초과 시 메시지는 **그냥 삭제**됩니다. DLQ가 있더라도 아무도 안 보면 똑같이 조용한 실패.
- 핸들러가 비동기 에러(`async` 함수 내 await 누락)로 실패하면서 반환은 정상이면 SQS는 "성공" 처리해 재시도도 없습니다.

### 4) NULL 바이트(`0x00`) 특이 케이스
- `data`에 `\u0000`이 포함된 채 DynamoDB `String` 속성에 넣으면 `ValidationException`이 납니다(Lambda 핸들러가 예외 처리를 삼키면 조용히 손실).
- PostgreSQL `text` 칼럼은 `\u0000` 저장을 거부합니다. MySQL은 허용하지만 일부 드라이버에서 문자열이 NULL 바이트 이후로 잘릴 수 있습니다.
- 로그에 바로 찍으면 터미널/로그 뷰어가 제어문자를 해석해 **로그 라인이 잘려 보이거나 뒤의 메시지를 덮어쓰는** 현상도 생깁니다. 로그만 보면 "에러가 안 찍힌 것처럼" 보여 원인 추적이 어렵습니다.

### 5) XML/SOAP 기반 AWS 서비스로 재전달
- Lambda가 받은 `data`를 그대로 다른 SQS 큐로 재송신, 또는 XML 기반 서비스(SES 이전 버전 API 등)로 보내면 **XML invalid character**로 5xx/ValidationError가 납니다. 역시 핸들러가 catch-only면 조용히 유실됩니다.

## 현재 코드에서 특히 확인해 볼 지점

`handleData` 내 로컬 에러 처리는 잘 되어 있지만, 진짜 “조용한 실패”는 **Lambda 쪽 코드**에 있을 가능성이 높습니다. 다음을 점검해 보시길 권합니다.

- Lambda 핸들러가 외부 API 호출/DB 저장 실패 시 `throw`를 하는가, 단순 로그 후 `return`하는가.
- SQS 이벤트소스 매핑에 `FunctionResponseTypes: ReportBatchItemFailures`가 설정돼 있고, 핸들러가 `batchItemFailures`를 반환하는가.
- 해당 SQS 큐에 **DLQ**와 **CloudWatch Alarm(ApproximateNumberOfMessagesNotVisible, DLQ depth, Lambda Errors, Throttles)**이 붙어 있는가.
- Lambda가 `data`를 저장하는 저장소가 어떤 문자셋 제한을 가졌는가(특히 NULL 바이트).
- 로그 출력 시 제어문자를 이스케이프해서 찍는가(`JSON.stringify(data)` 또는 치환). 안 그러면 에러 로그 자체가 가려질 수 있습니다.

## 요약

- SQS 메시지 적재·Lambda 트리거 자체가 **제어문자 때문에 실패할 확률은 낮다** (이미 `JSON.stringify`로 이스케이프되어 있음).
- 그러나 Lambda가 **꺼내 쓴 뒤**(REST 재전송, DB 저장, XML 서비스 호출, 다른 SQS 재전송) 제어문자 때문에 에러가 나는데, 핸들러가 이를 삼키거나 배치 실패 보고를 안 하면 **SQS 메시지는 삭제되고 처리는 누락되는 조용한 실패**로 이어집니다.
- 방어책은 (a) 보내는 쪽에서 제어문자를 제거하거나 `data`를 **Base64**로 감싸서 보내기, (b) Lambda에서 에러를 반드시 throw하고 `ReportBatchItemFailures` 사용, (c) DLQ + 알람 세팅입니다.

---

**User**

다음은 SQS에서 실행하는 람다 코드다.
```
export const processOrderSheet: SQSHandler = async (event: any, context: Context) => {
  for (const record of event.Records) {
    const messageId = record.messageId
    const body = typeof record.body === 'string' ? record.body : JSON.stringify(record.body)

    const { shop_id, data, device } = JSON.parse(body)

    console.log(JSON.stringify({
      step: "raw",
      messageId,
      shop_id,
      device,
      data,
    }))

    const dataSource = await createTypeOrmConnection(DB_CONFIG)
    try {
      const storeUid = await findStoreUniqueId(Number(shop_id), dataSource)
      const positionOrder = await findPositionOrder(Number(shop_id), dataSource)
      if (!storeUid) {
        throw new Error('Not found store')
      }

      const shopId = Number(shop_id)

      const orderRawData = await saveOrderRawData(shop_id, data, device, dataSource)
      const plainText = removePrintAsciiCode(data)
      const array = defineStringToArray(plainText)
      console.log(JSON.stringify({
        step: "sanitize",
        shopId,
        device,
        array,
      }))

      if (array.length === 0) {
        if (plainText.length > 0) {
          console.error("=== receipt lines is empty", plainText)
        }
        return
      }

      const order = await convertOrderSheetToOrderInfo(shopId, array, device, positionOrder, dataSource)
      checkMenuMatch({ shopId, order, plainText })

      console.log(JSON.stringify({
        step: "object",
        shopId,
        platform: order?.platform,
        device,
        order,
      }))

      if (!order) {
        return
      }

      // TODO: 직원식사 핕러링이 필요
      if (order.payment_amount === null) {
        await sendSlackMessageWithParams({
          channel: 'preppers-test',
          title: '가격 없음',
          message: `
            간편 주문 체크 해제 확인해주세요.
            지점 아이디: ${shopId}
            주문번호: ${order.order_number}
            주문 시간: ${order.time ? new Date(order.time) : '파싱 실패'}
            주문 내역: ${plainText}
          `,
        }).then(result => {
          console.log('=== sendSlackMessageWithParams()', result?.data)
        }).catch((e) => {
          console.error('convertToKioskOrder:sendSlackMessageWithParams()', e)
        })
      }


      if (order?.menus.length === 0) {
        console.error('order menus is empty', order)
        sendSlackMessageWithParams({
          channel: 'preppers_easyprep',
          title: '메뉴 확인 실패',
          message: `지점: ${shopId}\ndevice: ${device}\n주문: ${array.join('\n')}`,
        }).catch((e) => {
          console.error('sendSlackMessageWithParams error', e)
        })
        return
      }
      // order_time이 null인 경우 firestore 저장용 폴백 적용 (immutable 처리)
      const orderForFirestore = !order.time
        ? Object.assign(Object.create(Object.getPrototypeOf(order)), order, { time: new Date().getTime() })
        : order
      await storeOrderToFirestore(FIRESTORE_CONFIG, String(storeUid), orderForFirestore)
      await updateOrderObject(orderRawData.id, orderForFirestore, dataSource)

      const preppersMenus: PreppersOrderMenu[] = order.menus
        .map((menu) => {
          const savedMenu = MenuInfo.findSavedMenu(menu.title)
          if (!savedMenu) {
            return null
          }

          const options = (menu.options ?? []).map((opt) => {
            const savedOption = MenuInfo.findSavedOption(opt.title)
            if (!savedOption) {
              return null
            }

            return Object.assign({}, savedOption, {
              priceAmount: opt.price ?? undefined,
            })
          }).filter((o): o is NonNullable<typeof o> => o != null)

          return Object.assign({}, savedMenu, {
            count: menu.count,
            priceAmount: menu.price ?? undefined,
            options: options.length > 0 ? options : undefined,
          }) as PreppersOrderMenu
        })
        .filter((m): m is PreppersOrderMenu => m != null)
      await createPreppersOrder(order, shopId, preppersMenus)
    } catch (e) {
      console.error(e)
      await sendSlackMessageWithParams({
        channel: 'preppers-test',
        title: '주문 입력 오류',
        message: e.message,
      })
    } finally {
      await dataSource.destroy()
    }
  }
}
```

SQS가 조용한 실패할 때 람다에서 아무런 로그도 찍히지 않는다.

---

**Cursor**

## 가장 유력한 원인: `for...of` 루프 안의 `return`

이 핸들러에서 **배치 내 일부 메시지가 로그 한 줄 없이 사라지는** 가장 대표적인 원인이 이 구조입니다.

```js
for (const record of event.Records) {
  ...
  if (array.length === 0) {
    if (plainText.length > 0) {
      console.error("=== receipt lines is empty", plainText)
    }
    return  // ← 루프가 아니라 핸들러 전체가 종료됨
  }
  ...
  if (!order) {
    return  // ← 동일
  }
  ...
  if (order?.menus.length === 0) {
    ...
    return  // ← 동일
  }
  ...
}
```

`return`은 `for...of` 루프를 빠져나오는 게 아니라 **async 함수 전체**를 종료시킵니다. SQS → Lambda 이벤트소스 매핑은 기본 `BatchSize`가 10이라 한 invocation에 여러 메시지가 배달되는데, 시나리오는 이렇습니다.

- `event.Records = [A, B, C]`
- A 처리 중 `array.length === 0` 만족 → `return`
- B, C는 **for-loop 자체가 실행되지 않음** → 당연히 `console.log({step:"raw"})`도 안 찍힘
- Lambda는 아무 에러 없이 성공 반환 → 이벤트소스 매핑은 **A/B/C 모두 성공 처리**로 간주해 SQS에서 전부 삭제
- B, C의 처리 흔적이 CloudWatch에 전혀 남지 않음

→ 이것이 “**아무런 로그도 찍히지 않고 사라지는**” 전형입니다. `continue`로 바꿔야 해결됩니다.

## 두 번째 원인: `try/catch` 밖에서 던지는 예외

```js
for (const record of event.Records) {
  const messageId = record.messageId
  const body = typeof record.body === 'string' ? record.body : JSON.stringify(record.body)

  const { shop_id, data, device } = JSON.parse(body)   // ← try 바깥

  console.log(JSON.stringify({ step: "raw", ... }))    // ← 첫 로그는 여기서부터

  const dataSource = await createTypeOrmConnection(DB_CONFIG)   // ← try 바깥
  try {
    ...
  } catch (e) {
    console.error(e)
    ...
  } finally {
    await dataSource.destroy()
  }
}
```

문제 포인트:

1. `JSON.parse(body)` 실패 시 첫 `console.log`가 **아직 실행되지 않은 상태로** throw 됩니다. 
   - 캐치도 없으므로 핸들러는 reject → 배치 전체가 실패(메시지는 재시도 후 DLQ/삭제).
   - 앞서 제어문자 이야기와 연결됩니다. 메시지 자체는 `JSON.stringify`로 감싸서 보내기 때문에 파싱 자체가 깨지는 경우는 드물지만, 만약 경로 어딘가에서 잘못 직렬화된 메시지가 하나라도 섞이면 **원본 `body`가 뭔지 남기는 로그가 전혀 없어서** 재현이 불가능해집니다.
   - 결정적으로, `record.body`가 문자열이 아닐 경우 `JSON.stringify`로 감싸서 `body`로 쓰고 있는데, 이때 `shop_id/data/device` 구조가 아닐 수 있습니다. 파싱 성공하더라도 뒤에서 `Number(shop_id)`가 `NaN`이 되는 등 은근한 에러로 이어집니다.

2. `createTypeOrmConnection(DB_CONFIG)` 실패 시도 마찬가지로 try 바깥에서 throw → 로그 없이 종료. Cold start 시 RDS 연결 타임아웃으로 여기서 자주 터집니다.

3. `finally`의 `await dataSource.destroy()`가 throw 되면 이미 catch 바깥이라 재throw 됩니다. 이 경우 catch에서 슬랙은 보냈을지언정 **핸들러는 실패 반환** → SQS 재시도. 재시도 중 동일 이유로 계속 실패하면 DLQ 없이는 조용히 사라집니다.

## 세 번째 원인: 배치 부분 실패 보고 미사용

`SQSHandler`가 단일 값 반환이면 AWS는 전체 배치를 한 덩어리로 처리합니다.

- 배치 중 1건이 throw하면 **나머지 9건도 같이 재처리**됩니다 (멱등성 없으면 중복 입력).
- 반대로 catch에서 삼킨 실패 1건 때문에 성공 반환하면 **실패한 그 1건은 삭제**됩니다 (손실).

해결 방법: 이벤트소스 매핑에 `ReportBatchItemFailures`를 켜고 핸들러가 `{ batchItemFailures: [{ itemIdentifier: messageId }, ...] }`를 반환하도록 고쳐야 합니다. 지금 코드에는 `messageId`를 변수로 이미 뽑아 놨으니 거기에 연결하기 쉽습니다.

## 네 번째 원인: catch 안에서 다시 throw

```js
} catch (e) {
  console.error(e)
  await sendSlackMessageWithParams({
    channel: 'preppers-test',
    title: '주문 입력 오류',
    message: e.message,
  })
}
```

- `sendSlackMessageWithParams`가 실패하면 catch 블록에서 다시 throw가 일어납니다(래핑 try/catch 없음).
- 그 에러는 `finally`를 거쳐 배치 처리 루프 밖으로 전파 → 뒤에 남은 레코드는 처리 안 됨.
- `console.error(e)`는 찍히지만, **그 이후 레코드들은 역시 아무 로그 없이 사라집니다.**

또한 `e`가 `Error` 인스턴스가 아닌 경우(`throw "something"`, `throw { code: 'X' }`) `e.message`가 `undefined`라 슬랙 본문이 빈 상태로 전송되어, 디버깅 시 “로그는 찍혔는데 내용이 비어있다”는 혼란을 줍니다.

## 다섯 번째 원인: Lambda 자체가 죽는 경우(로그가 완전히 없음)

“아무 로그도 안 찍힌다”는 묘사와 정말 일치하는 경우:

- **Init phase crash**: 모듈 top-level에서 `createTypeOrmConnection`을 import time에 실행하거나, import chain에 syntax/런타임 에러가 있으면 Lambda init 단계에서 실패합니다. 이 경우 `console.log`가 하나도 안 찍히고 AWS가 `INIT_REPORT` 에러만 남길 수 있습니다. CloudWatch Log stream이 아예 새로 안 만들어지기도 합니다.
- **OOM / 서버리스 리소스 초과**: `Task timed out`이나 `Runtime exited with error: signal: killed`만 찍힘.
- **로그 그룹 retention 혹은 다른 로그 그룹**: 버전/alias가 잘못 배포돼서 다른 `$LATEST`가 찍히는 로그 그룹을 안 보고 있는 경우.
- **이벤트소스 매핑이 다른 Lambda로 연결되어 있어서** 정작 이 핸들러는 호출되지 않음.

## 점검 체크리스트

1. CloudWatch에서 해당 Lambda의 **모든 버전/별칭** 로그 그룹을 확인. 특히 `"step":"raw"` 로그가 아예 없는 실행이 있는지.
2. `invocationCount` vs `received message count` 비교. 배치 당 다수 메시지가 묶이는데 invocation 수만 보면 놓치기 쉽습니다.
3. SQS 메트릭 `ApproximateNumberOfMessagesDeleted` vs Lambda 성공 호출 수. 불일치하면 배치 삭제 정책 의심.
4. 이벤트소스 매핑에 `FunctionResponseTypes: ["ReportBatchItemFailures"]` 설정 여부.
5. DLQ/`RedrivePolicy`의 `maxReceiveCount` 확인. DLQ 없으면 재시도 후 사라진 것입니다.
6. X-Ray나 Powertools for Lambda로 각 record 시작/종료를 찍고 있는지.

## 수정 방향 요약

이 코드에서 꼭 손봐야 할 포인트는 다음 3가지입니다.

1. 루프 내부의 `return` → `continue`로 변경.  
   (각 레코드 흐름을 별도 함수로 분리해 `for (const r of event.Records) await handleRecord(r)` 형태로 바꾸면 안전.)
2. `try` 블록을 **record의 모든 처리**를 감싸도록 끌어올리고 `JSON.parse`·DB 연결·`finally` 클린업까지 포함. record 시작 시점에 반드시 “raw body” 로그를 남겨서 어떤 메시지에서 터졌는지 추적 가능하게.
3. `ReportBatchItemFailures` 적용 + `batchItemFailures` 반환. 실패한 메시지만 재시도되도록.

이 세 가지만 잡아도 “배치 안에서 로그 한 줄 없이 사라지는 메시지” 현상은 거의 사라집니다. 제어문자 이슈는 **조용한 실패를 만드는 직접 원인이라기보다**, 위 구조적 문제와 만났을 때 증상을 드러내는 방아쇠로 보는 게 정확합니다.

---

**User**

console이 비동기라서 람다가 빨리 종료되면 안찍힐 수 있다는 거지?

---

**Cursor**

## 반쯤 맞고 반은 다릅니다

`console.log` 자체는 동기 호출입니다. 호출 즉시 `process.stdout`으로 write가 실행됩니다. 다만 **CloudWatch Logs로 전송되는 과정**과 **핸들러 종료 이후의 라이프사이클** 측면에서 “늦게 찍히거나 누락되는” 현상이 실제로 있습니다. 구분해서 보는 게 정확합니다.

## 1) Node.js `console.log`의 실제 동작

- `console.log`는 내부적으로 `process.stdout.write`를 호출합니다.
- `process.stdout`은 목적지에 따라 버퍼링 특성이 다릅니다. Lambda의 stdout은 **pipe**라 line-buffered가 아니라 **block-buffered**로 동작할 수 있고, 대용량 write는 비동기로 flush됩니다. 이 때문에 Node는 [`process.stdout.write`가 경우에 따라 non-blocking이라 경고하는 공식 문서](https://nodejs.org/api/process.html#a-note-on-process-io)를 두고 있습니다.
- 하지만 정상 흐름(`await`로 이어지는 코드)에서는 이벤트 루프가 살아있는 동안 flush가 보장되므로 거의 손실되지 않습니다.

즉, 핸들러가 “빨리 종료된다고 해서” 단순히 앞에 있던 `console.log`가 사라지진 않습니다. Lambda 런타임은 핸들러의 Promise가 resolve될 때까지 기다린 뒤 컨테이너를 freeze합니다.

## 2) 진짜 누락이 일어나는 시나리오

아래 경우엔 로그가 사라지거나 엉뚱한 타이밍(다음 invocation의 로그에 섞여서)에 나타날 수 있습니다.

### (a) `await` 없이 날린 Promise의 콜백 로그
가장 흔하고, 지금 보여주신 코드에도 있는 패턴입니다.

```js
sendSlackMessageWithParams({...})
  .then(result => { console.log('=== sendSlackMessageWithParams()', result?.data) })
  .catch(e => { console.error('convertToKioskOrder:sendSlackMessageWithParams()', e) })
```

- 핸들러는 이 Promise를 `await`하지 않고 지나갑니다.
- 슬랙 API 응답이 50ms 뒤에 오는 사이 `for` 루프는 끝나고 핸들러는 resolve.
- Lambda는 이벤트 루프가 idle이면 컨테이너를 freeze합니다. 이때:
  - 운이 좋으면 같은 컨테이너가 재사용되는 다음 invocation에서 “남아있던 `.then`”이 실행되며 로그가 찍히지만, **이전 invocation의 요청 ID와 섞여서** 엉뚱한 로그 스트림에 들어갑니다. 마치 안 찍힌 것처럼 보이죠.
  - 운이 나쁘면 컨테이너가 종료(shutdown)돼 그 로그는 **영원히 사라집니다**.
- 에러가 나면 더 심합니다. `.catch`의 `console.error`가 실행되기 전에 freeze되면 “에러가 났는데 로그조차 없다”가 됩니다.

### (b) 모듈 top-level의 비동기 초기화
Lambda cold start 중 init phase에서 비동기 로그를 찍으면, init log group으로 가거나 타임아웃 전에 flush되지 않을 수 있습니다. 지금 코드엔 해당 패턴이 보이진 않지만, import chain에 있을 수 있습니다.

### (c) `process.exit()` 또는 네이티브 크래시
- `process.exit(0)`을 직접 호출하면 pending stdout write가 flush되기 전에 프로세스가 종료됩니다.
- OOM, segfault(native addon)로 SIGKILL 당하면 로그가 손실됩니다. CloudWatch에는 `Runtime exited` 같은 메타 로그만 남습니다.

### (d) 아주 큰 문자열
`data`가 프린터 원본이라 길고 제어문자까지 섞여 있으면 단일 `console.log` 페이로드가 커서 CloudWatch의 **max log event size(256KB)** 를 넘을 수 있습니다. 이 경우 해당 이벤트는 잘리거나 드롭될 수 있습니다. “일부 레코드만 로그가 안 보인다”면 의심해볼 지점입니다.

## 3) 지금 보여주신 코드에서 이 관점의 리스크

```js
sendSlackMessageWithParams({...}).then(...).catch(...)   // (1) 가격 없음 알림
sendSlackMessageWithParams({...}).catch(...)             // (2) 메뉴 확인 실패 알림
```

- 이 둘은 `await`가 없습니다. 해당 분기로 빠진 레코드의 슬랙 알림과 그 `.catch`에 있는 `console.error`는 위 (a) 이유로 **로그에서 사라질 수 있습니다**.
- 또 (2) 직후 바로 `return`을 하기 때문에 핸들러가 빠르게 종료됩니다. freeze 타이밍을 매우 잘 잡아 당기는 케이스입니다.

```js
for (const record of event.Records) { ... }
```

- 반대로 `await`가 걸려 있는 부분(`saveOrderRawData`, `storeOrderToFirestore`, `updateOrderObject`, `createPreppersOrder` 등) 앞뒤의 `console.log`는 거의 확실하게 flush됩니다. 이 부분은 “console이 비동기라 안 찍힌다”는 가설로 설명하기 어렵습니다.

## 4) 정리

- “console.log가 비동기라 Lambda가 빨리 끝나면 누락된다”는 설명은 **부분적으로만 맞습니다**. 올바르게 `await`로 이어진 코드의 로그는 대체로 보장됩니다.
- 지금 이 핸들러에서 로그가 통째로 없어지는 현상의 유력 원인은 여전히 앞서 말한 **`for...of` 안의 `return`(뒤 레코드 자체가 실행되지 않음)** 과 **try 밖에서의 throw**입니다. 이쪽은 아예 `console.log`가 호출조차 되지 않는 케이스라 “비동기 flush” 문제가 아닙니다.
- 추가로 **`await` 없는 `.then/.catch` 로그** 는 freeze 타이밍에 휘말려 누락/지연되는 진짜 비동기 이슈이므로, 디버깅 로그는 반드시 `await` 뒤에 두거나 Lambda Powertools Logger처럼 flush를 보장하는 도구로 묶어두시는 게 안전합니다.

요약: **“console.log 자체가 비동기라서”는 주된 원인이 아니고, “비동기 작업이 핸들러보다 늦게 끝나기 때문에 그 콜백 안의 로그가 사라진다”가 정확한 표현**이에요.

---

**User**

루프안의 return 전에 console.log 가 있는데 너말대로면 찍혀야 하는 것 아닌가?
해당 케이스에서만 생각할 때

---

**Cursor**

## 네, 맞아요. 제가 말을 조금 뭉뚱그려 썼네요

**해당 레코드 하나만 놓고 보면 `return` 전의 `console.log`는 분명히 찍힙니다.** 이 부분은 제 앞선 설명이 오해를 줬어요. 그 케이스에서는 로그가 안 찍힐 이유가 없습니다.

## 그럼 언제 “로그가 아예 없는” 레코드가 생기나

`return`으로 인한 무로그 실패는 **그 `return`을 친 레코드가 아니라, 같은 배치의 뒤 레코드**에서 일어납니다.

예를 들어 SQS가 Lambda에 `event.Records = [A, B, C]`를 배달했다고 합시다.

- 레코드 A 처리 중:
  - `console.log({step:"raw", messageId: A, ...})` ← 찍힘
  - `console.log({step:"sanitize", ...})` ← 찍힘
  - 조건 만족 → `return`

- 이 `return`은 for-loop을 빠져나오는 게 아니라 **async 함수 전체**를 종료시키므로, 
  - 레코드 B의 첫 줄(`const messageId = record.messageId`)조차 실행되지 않습니다.
  - 당연히 B의 `"raw"` 로그도 찍히지 않습니다.
  - C 역시 마찬가지.

- Lambda는 아무 에러 없이 성공 반환 → 이벤트소스 매핑은 **A/B/C 전부 성공**으로 간주 → SQS에서 A/B/C 모두 삭제.

→ 결과: **A는 로그가 있고 처리도 됐지만, B/C는 로그 한 줄 없이 사라집니다.** 이게 “조용한 실패”의 실체입니다.

## 같은 관점으로 다시 정리

- 문제를 겪는 특정 `messageId`가 **A 위치(return을 직접 친 레코드)** 라면 → 로그는 반드시 존재해야 합니다. 없다면 원인은 다른 곳(초기화 실패, JSON.parse 실패, 로그 그룹/버전 잘못 보고 있음, CloudWatch 이벤트 크기 초과로 드롭 등).
- 문제를 겪는 `messageId`가 **B/C 위치(같은 배치의 뒤쪽)** 라면 → 앞 레코드의 이른 `return` 때문에 처리 자체가 시작되지 않아 로그가 없음. 이게 현재 구조의 실제 버그.

## 확인 방법

CloudWatch Logs Insights로 이 쿼리를 돌려 보시면 배치 포지션별 누락을 바로 볼 수 있어요.

```
fields @timestamp, @message
| filter @message like /"step":"raw"/
| parse @message '"messageId":"*"' as messageId
| stats count() by bin(1m)
```

또는 특정 `messageId`를 SQS 쪽 `ApproximateNumberOfMessagesDeleted` 증가 시점과 대조해서, **삭제는 됐는데 `"step":"raw"` 로그가 없는 messageId**를 찾으면 그게 B/C 포지션에서 유실된 케이스입니다.

그리고 해결은 간단합니다. 루프 안의 `return`을 전부 `continue`로 바꾸거나, record 처리 로직을 별도 async 함수로 뽑아서 `for (const r of event.Records) { await handleRecord(r) }` 형태로 호출하면 됩니다. 그러면 한 레코드가 조기 종료되더라도 뒤 레코드 처리는 정상 진행되고, 모든 레코드에서 `"step":"raw"` 로그가 최소 한 줄은 찍힙니다.

