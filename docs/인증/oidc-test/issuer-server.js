const crypto = require('crypto');
const express = require('express');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = 3001;
const ISSUER = `http://localhost:${PORT}`;

// RSA 키 쌍 생성 (Kubernetes API Server가 내부적으로 하는 것과 동일)
const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
  publicKeyEncoding: { type: 'spki', format: 'pem' },
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});

const KID = crypto.randomUUID();

function pemToJwk(pem, kid) {
  const key = crypto.createPublicKey(pem);
  const jwk = key.export({ format: 'jwk' });
  return { ...jwk, kid, use: 'sig', alg: 'RS256' };
}

// Kubernetes와 동일한 OIDC Discovery 엔드포인트
app.get('/.well-known/openid-configuration', (req, res) => {
  res.json({
    issuer: ISSUER,
    jwks_uri: `${ISSUER}/openid/v1/jwks`,
    response_types_supported: ['id_token'],
    subject_types_supported: ['public'],
    id_token_signing_alg_values_supported: ['RS256'],
  });
});

// JWKS 엔드포인트 - 공개키 제공
app.get('/openid/v1/jwks', (req, res) => {
  res.json({
    keys: [pemToJwk(publicKey, KID)],
  });
});

// ServiceAccount 토큰 발급 (Kubernetes가 Pod에 마운트하는 것을 시뮬레이션)
app.get('/token', (req, res) => {
  const namespace = req.query.namespace || 'default';
  const serviceAccount = req.query.sa || 'kiosk-server';
  const audience = req.query.aud || 'order-server';

  const payload = {
    iss: ISSUER,
    sub: `system:serviceaccount:${namespace}:${serviceAccount}`,
    aud: audience,
    'kubernetes.io': {
      namespace,
      serviceaccount: { name: serviceAccount, uid: crypto.randomUUID() },
      pod: { name: `${serviceAccount}-pod-${crypto.randomBytes(3).toString('hex')}`, uid: crypto.randomUUID() },
    },
  };

  const token = jwt.sign(payload, privateKey, {
    algorithm: 'RS256',
    expiresIn: '1h',
    keyid: KID,
  });

  console.log(`[Issuer] 토큰 발급: ${payload.sub} → audience: ${audience}`);

  res.json({ token, decoded: jwt.decode(token) });
});

app.listen(PORT, () => {
  console.log(`\n🔐 OIDC Issuer Server (Kubernetes API Server 시뮬레이션)`);
  console.log(`   http://localhost:${PORT}`);
  console.log(`\n   Discovery: http://localhost:${PORT}/.well-known/openid-configuration`);
  console.log(`   JWKS:      http://localhost:${PORT}/openid/v1/jwks`);
  console.log(`   토큰 발급:  http://localhost:${PORT}/token?namespace=default&sa=kiosk-server&aud=order-server\n`);
});
