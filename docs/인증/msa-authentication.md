# MSA 서비스 간 인증 (Service-to-Service Authentication)

## 주문 요청 흐름

```
Kiosk Client(KC) → Kiosk Server(KS) → Order Server(OS)
```

---

## 인증 방식: Kubernetes OIDC + APISIX

### Kubernetes 자체 OIDC Issuer

Kubernetes API Server는 OIDC Provider 역할을 하며, Pod에 마운트되는 ServiceAccount 토큰을 OIDC 호환 JWT로 발급한다.

- **OIDC Discovery**: `/.well-known/openid-configuration`
- **JWKS 공개키**: `/openid/v1/jwks`
- **토큰 형식**: RS256 서명 JWT (만료 시간 있음, kubelet이 자동 갱신)

#### Projected ServiceAccount Token

| 항목 | 설명 |
|------|------|
| 형식 | OIDC 호환 JWT |
| 만료 | 기본 1시간 (설정 가능) |
| Audience | 대상 서비스 지정 가능 |
| 갱신 | kubelet이 자동 갱신 |
| 검증 | JWKS 공개키로 외부 시스템도 검증 가능 |

#### JWT 페이로드 구조

```json
{
  "iss": "https://kubernetes.default.svc.cluster.local",
  "sub": "system:serviceaccount:production:kiosk-server",
  "aud": "order-server",
  "kubernetes.io": {
    "namespace": "production",
    "serviceaccount": { "name": "kiosk-server" },
    "pod": { "name": "kiosk-server-pod-abc123" }
  }
}
```

---

## 인증 경계 설계

### 토큰 전파(Token Propagation) vs 서비스 신원(Service Identity)

KC 토큰을 OS까지 전파하지 않는다. 인증 경계를 분리하여 각 구간에서 독립적으로 인증한다.

```
┌─ 외부 경계 ──────────┐    ┌─ 내부 경계 ──────────────┐
│                      │    │                          │
│  KC ──[KC 토큰]──► KS│    │KS ──[SA 토큰]──► OS      │
│                      │    │                          │
│  클라이언트 인증      │    │  서비스 간 인증           │
│  "누가 주문하는가?"   │    │  "어떤 서비스가 요청하는가?" │
└──────────────────────┘    └──────────────────────────┘
```

**이유:**
- OS가 KC의 인증 체계를 몰라도 됨 → 결합도 감소
- KC 토큰의 audience는 KS 대상이므로 OS에서 audience 불일치 발생
- KC 인증 방식 변경 시 OS 수정 불필요
- 각 서비스가 자신의 인증 경계만 관리

### 필요한 컨텍스트 전달 방법

KS가 KC 토큰을 검증한 후, OS에는 서비스 토큰 + 컨텍스트 헤더로 전달한다.

```javascript
const saToken = fs.readFileSync('/var/run/secrets/tokens/order-server-token', 'utf8');

fetch('http://order-server/api/orders', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${saToken}`,     // KS의 서비스 신원
    'X-Kiosk-Id': kioskInfo.kioskId,          // 키오스크 식별자
    'X-Store-Id': kioskInfo.storeId,          // 매장 식별자
    'X-Request-Id': generateRequestId(),       // 추적용
  },
  body: JSON.stringify(orderData),
});
```

---

## 토큰 검증: APISIX openid-connect 플러그인

APISIX의 `jwt-auth`는 APISIX 자체가 JWT를 발급/검증하는 플러그인이므로 부적합.
외부 발급 JWT 검증에는 `openid-connect` 플러그인을 사용한다.

| 구분 | `jwt-auth` | `openid-connect` |
|------|-----------|------------------|
| 역할 | APISIX가 JWT 발급+검증 | 외부 IdP 토큰 검증만 |
| 키 관리 | 수동 등록 | JWKS URI 자동 조회 |
| K8s OIDC | 키 교체 시 수동 갱신 필요 | 자동 대응 |

### APISIX 설정

```json
{
  "plugins": {
    "openid-connect": {
      "discovery": "https://<k8s-api-server>/.well-known/openid-configuration",
      "bearer_only": true,
      "realm": "k8s-oidc",
      "token_signing_alg_values_expected": "RS256"
    }
  }
}
```

### 검증 흐름

```
KS ──Bearer JWT──► APISIX ──────────────► OS
                     │
                     ├─ discovery URL로 OIDC 설정 조회
                     ├─ jwks_uri에서 공개키 가져옴 (캐싱)
                     ├─ kid 매칭 → 서명 검증
                     ├─ issuer, exp 확인
                     └─ 통과 시 upstream으로 전달
```

---

## Pod 설정 예시

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: kiosk-server
      volumeMounts:
        - name: oidc-token
          mountPath: /var/run/secrets/tokens
  volumes:
    - name: oidc-token
      projected:
        sources:
          - serviceAccountToken:
              audience: order-server
              expirationSeconds: 3600
              path: order-server-token
```

---

## 테스트

로컬 시뮬레이션 코드: [oidc-test/](./oidc-test/)
