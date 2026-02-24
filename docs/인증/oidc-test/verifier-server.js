const express = require('express');
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const app = express();
app.use(express.json());

const PORT = 3002;
const ISSUER_URL = 'http://localhost:3001';
const EXPECTED_AUDIENCE = 'order-server';

// JWKS 클라이언트 - Issuer의 공개키를 자동으로 가져와서 캐싱
const client = jwksClient({
  jwksUri: `${ISSUER_URL}/openid/v1/jwks`,
  cache: true,
  cacheMaxAge: 600000, // 10분
});

function getSigningKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    if (err) return callback(err);
    callback(null, key.getPublicKey());
  });
}

function verifyToken(token) {
  return new Promise((resolve, reject) => {
    jwt.verify(
      token,
      getSigningKey,
      {
        issuer: ISSUER_URL,
        audience: EXPECTED_AUDIENCE,
        algorithms: ['RS256'],
      },
      (err, decoded) => {
        if (err) reject(err);
        else resolve(decoded);
      },
    );
  });
}

// 인증 미들웨어 (Kubernetes OIDC 토큰 검증)
async function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization 헤더가 없습니다' });
  }

  const token = authHeader.slice(7);

  try {
    const decoded = await verifyToken(token);
    req.serviceAccount = {
      subject: decoded.sub,
      namespace: decoded['kubernetes.io']?.namespace,
      name: decoded['kubernetes.io']?.serviceaccount?.name,
      pod: decoded['kubernetes.io']?.pod?.name,
    };
    next();
  } catch (err) {
    console.log(`[Verifier] 토큰 검증 실패: ${err.message}`);
    return res.status(403).json({ error: '토큰 검증 실패', detail: err.message });
  }
}

// 보호된 API 엔드포인트
app.get('/api/orders', authMiddleware, (req, res) => {
  console.log(`[Verifier] 인증 성공: ${req.serviceAccount.subject}`);

  res.json({
    message: '주문 데이터 조회 성공',
    caller: req.serviceAccount,
    orders: [
      { id: 'ORD-001', item: '아메리카노', qty: 2 },
      { id: 'ORD-002', item: '카페라떼', qty: 1 },
    ],
  });
});

// 토큰 없이 접근 테스트용
app.get('/api/public', (req, res) => {
  res.json({ message: '공개 엔드포인트 - 인증 불필요' });
});

app.listen(PORT, () => {
  console.log(`\n📦 Order Server (OIDC 토큰 검증 서버)`);
  console.log(`   http://localhost:${PORT}`);
  console.log(`\n   보호 API:  GET /api/orders  (Bearer 토큰 필요)`);
  console.log(`   공개 API:  GET /api/public\n`);
});
