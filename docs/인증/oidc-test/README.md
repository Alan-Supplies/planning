# Kubernetes OIDC 서비스 간 인증 테스트

Kubernetes가 OIDC Issuer로서 발급하는 ServiceAccount 토큰을 활용한
**서비스 간 인증(service-to-service authentication)** 시뮬레이션

## 구조

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Issuer Server  │     │  Kiosk Server   │     │  Order Server   │
│  (K8s API 역할) │     │  (클라이언트)    │     │  (검증 서버)     │
│  :3001          │     │  test-client.js  │     │  :3002          │
├─────────────────┤     ├─────────────────┤     ├─────────────────┤
│ OIDC Discovery  │◄────│ 1. 토큰 발급    │     │                 │
│ JWKS 공개키     │     │    요청         │     │                 │
│ JWT 토큰 발급   │     │                 │     │                 │
│                 │     │ 2. Bearer 토큰  │────►│ JWKS로 검증     │
│                 │     │    포함 요청     │     │ audience 확인   │
│                 │     │                 │◄────│ 주문 데이터 응답 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## 실행 방법

```bash
# 의존성 설치
npm install

# 터미널 1: OIDC Issuer 서버 시작
npm run issuer

# 터미널 2: Order Server (검증 서버) 시작
npm run verifier

# 터미널 3: 테스트 실행
npm test
```

## 테스트 시나리오

| # | 시나리오 | 기대 결과 |
|---|---------|----------|
| 1 | OIDC Discovery 조회 | issuer, jwks_uri 확인 |
| 2 | JWKS 공개키 조회 | RS256 키 확인 |
| 3 | ServiceAccount 토큰 발급 | JWT 발급 성공 |
| 4 | 유효한 토큰으로 API 호출 | 200 + 주문 데이터 |
| 5 | 토큰 없이 API 호출 | 401 Unauthorized |
| 6 | 위조 토큰으로 API 호출 | 403 Forbidden |
| 7 | 잘못된 audience 토큰 | 403 Forbidden |

## 실제 Kubernetes 환경과의 매핑

| 이 테스트 | 실제 Kubernetes |
|-----------|----------------|
| `issuer-server.js` | kube-apiserver (OIDC Issuer) |
| `/token` 엔드포인트 | Pod에 자동 마운트되는 Projected SA Token |
| `verifier-server.js` | Order Server (JWKS로 토큰 검증) |
| `test-client.js` | Kiosk Server Pod |
| `audience: "order-server"` | TokenRequest API의 audience 파라미터 |

## 실제 K8s에서 적용할 때

```yaml
# Pod에서 특정 audience로 토큰 요청
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
              audience: order-server  # 대상 서비스 지정
              expirationSeconds: 3600
              path: order-server-token
```

```javascript
// Kiosk Server에서 토큰 읽기
const fs = require('fs');
const token = fs.readFileSync('/var/run/secrets/tokens/order-server-token', 'utf8');

// Order Server에 요청
fetch('http://order-server/api/orders', {
  headers: { Authorization: `Bearer ${token}` }
});
```
