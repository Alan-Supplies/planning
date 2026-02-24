# 인증 아키텍처

## 개요

order-server는 두 종류의 클라이언트를 지원하며, 각각 다른 인증 방식을 사용한다.

| 클라이언트 | 인증 방식 | 계층 | 용도 |
|---|---|---|---|
| 주문입력 Lambda | API Key (`X-API-Key`) | APISIX Gateway | POS 듀얼라이트 주문 생성 |
| 대시보드 (프론트엔드) | JWT | NestJS Application | 조회/환불 등 사용자 기능 |

## 인증 흐름

### 1. 주문 생성 (Lambda → order-server)

```text
POS 영수증 → 라즈베리파이 → SQS → Lambda
  → APISIX (keyAuth + consumer-restriction)
    → NestJS (@Public → JWT 면제)
```

- **APISIX**: `POST /pri/v1/order/customer-orders`만 keyAuth 적용
- **NestJS**: `@Public()` 데코레이터로 글로벌 JWT Guard 우회
- Lambda는 사용자가 아닌 인프라 파이프라인의 일부이므로 JWT가 존재하지 않음

### 2. 대시보드 API (프론트엔드 → order-server)

```text
대시보드 → APISIX (인증 없음, 라우팅만)
  → NestJS (JwtAuthGuard → JWT 검증)
```

- **APISIX**: `/pri/v1/order/*` 경로, 게이트웨이 레벨 인증 없음
- **NestJS**: 글로벌 `JwtAuthGuard`가 JWT 토큰 직접 검증

## APISIX 라우트 구성

APISIX는 더 구체적인 경로를 우선 매칭한다.

| 라우트 파일 | 경로 | 메서드 | 인증 | 우선순위 |
|---|---|---|---|---|
| `apisix-route-pri.yaml` | `/pri/v1/order/customer-orders` | POST | keyAuth | 높음 (구체적) |
| `apisix-route-api.yaml` | `/pri/v1/order/*` | ALL | 없음 | 낮음 (와일드카드) |
| `apisix-route-pub.yaml` | `/pub/v1/order/*` | ALL | 없음 | - (healthz, version) |

## NestJS 인증 구성

### 글로벌 Guard

`JwtAuthGuard`가 `APP_GUARD`로 등록되어 모든 엔드포인트에 적용된다.

```typescript
// app.module.ts
providers: [
  { provide: APP_GUARD, useClass: JwtAuthGuard },
]
```

### 엔드포인트별 인증

| 엔드포인트 | 데코레이터 | 인증 |
|---|---|---|
| `POST /customer-orders` | `@Public()` | JWT 면제 (APISIX keyAuth로 보호) |
| 나머지 전체 | 없음 (글로벌 Guard) | JWT 필수 |

## 보안 경계 정리

```text
                    ┌─ POST /customer-orders ─┐
Lambda (API Key) ──→│  APISIX: keyAuth ✅       │──→ NestJS: @Public() ✅
                    └─────────────────────────┘

                    ┌─ POST /customer-orders ─┐
공격자 (키 없음) ──→│  APISIX: keyAuth ❌       │    (차단)
                    └─────────────────────────┘

                    ┌─ GET /sales, etc.  ─────┐
대시보드 (JWT) ────→│  APISIX: 통과            │──→ NestJS: JWT ✅
                    └─────────────────────────┘

                    ┌─ GET /sales, etc.  ─────┐
Lambda (API Key) ──→│  APISIX: 통과            │──→ NestJS: JWT ❌ (401)
                    └─────────────────────────┘
```

---

## 평가: 인증 방식이 두 가지로 나뉜 것에 대해

### 왜 나뉘었는가

초기에는 Lambda 파이프라인(POS → SQS → Lambda) 전용 서버로 keyAuth만 사용했다.
이후 대시보드 조회 서비스가 추가되면서 사용자 인증(JWT)이 필요해졌다.
두 인증 방식의 공존은 서비스 성장에 따른 자연스러운 결과이다.

### 현재 구조의 장점

1. **관심사 분리**: 서비스 간 통신(S2S)과 사용자 인증(B2C)이 명확히 분리됨
2. **최소 권한 원칙**: Lambda는 주문 생성만 가능, 다른 API 접근 불가
3. **변경 최소화**: 기존 URL 체계를 유지하면서 인증만 분리
4. **계층적 보안**: APISIX(게이트웨이) + NestJS(애플리케이션) 이중 보호

### 현재 구조의 한계

1. **URL prefix (`/pri/`)의 의미 희석**: 원래 "private = keyAuth 필수"였으나, 이제 일부만 keyAuth. 이름과 실제 동작이 불일치
2. **`@Public()` 의미의 모호성**: 실제로는 "공개"가 아닌 "APISIX keyAuth로 보호되는 엔드포인트"에 사용. 의도를 코드만으로 파악하기 어려움
3. **APISIX 의존성**: `POST /customer-orders`의 보안이 APISIX에 100% 의존. Pod 직접 접근 시 무인증

### 향후 개선 방향 (필요 시)

- `/pri/` prefix를 `/v1/order/`로 통일하는 URL 정규화 (클라이언트 마이그레이션 필요)
- `@Public()` 대신 `@ApiKeyOnly()` 같은 명시적 데코레이터로 의도 표현
- APISIX jwt-auth 플러그인 도입 시 NestJS JWT 해석을 게이트웨이로 이관 가능
