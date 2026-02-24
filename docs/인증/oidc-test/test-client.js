const fetch = require('node-fetch');

const ISSUER = 'http://localhost:3001';
const ORDER_SERVER = 'http://localhost:3002';

async function run() {
  console.log('='.repeat(60));
  console.log(' Kubernetes OIDC 서비스 간 인증 테스트');
  console.log('='.repeat(60));

  // 1. OIDC Discovery 확인
  console.log('\n[1] OIDC Discovery 엔드포인트 조회');
  const discovery = await fetch(`${ISSUER}/.well-known/openid-configuration`).then((r) => r.json());
  console.log('    issuer:', discovery.issuer);
  console.log('    jwks_uri:', discovery.jwks_uri);

  // 2. JWKS (공개키) 확인
  console.log('\n[2] JWKS 공개키 조회');
  const jwks = await fetch(discovery.jwks_uri).then((r) => r.json());
  console.log('    키 개수:', jwks.keys.length);
  console.log('    알고리즘:', jwks.keys[0].alg);
  console.log('    kid:', jwks.keys[0].kid);

  // 3. Kiosk Server의 ServiceAccount 토큰 발급
  console.log('\n[3] ServiceAccount 토큰 발급 (kiosk-server → order-server)');
  const tokenRes = await fetch(`${ISSUER}/token?namespace=production&sa=kiosk-server&aud=order-server`).then((r) =>
    r.json(),
  );
  console.log('    subject:', tokenRes.decoded.sub);
  console.log('    audience:', tokenRes.decoded.aud);
  console.log('    토큰 길이:', tokenRes.token.length, 'chars');

  // 4. 토큰으로 Order Server API 호출
  console.log('\n[4] Order Server 보호 API 호출 (유효한 토큰)');
  const orderRes = await fetch(`${ORDER_SERVER}/api/orders`, {
    headers: { Authorization: `Bearer ${tokenRes.token}` },
  }).then((r) => r.json());
  console.log('    결과:', orderRes.message);
  console.log('    호출자:', JSON.stringify(orderRes.caller));
  console.log('    주문 데이터:', JSON.stringify(orderRes.orders));

  // 5. 토큰 없이 호출 (401 기대)
  console.log('\n[5] Order Server 보호 API 호출 (토큰 없음 → 401 기대)');
  const noAuthRes = await fetch(`${ORDER_SERVER}/api/orders`);
  console.log('    상태 코드:', noAuthRes.status);
  const noAuthBody = await noAuthRes.json();
  console.log('    응답:', noAuthBody.error);

  // 6. 잘못된 토큰으로 호출 (403 기대)
  console.log('\n[6] Order Server 보호 API 호출 (위조 토큰 → 403 기대)');
  const fakeRes = await fetch(`${ORDER_SERVER}/api/orders`, {
    headers: { Authorization: 'Bearer fake.token.here' },
  });
  console.log('    상태 코드:', fakeRes.status);
  const fakeBody = await fakeRes.json();
  console.log('    응답:', fakeBody.error);

  // 7. 잘못된 audience로 발급된 토큰 (403 기대)
  console.log('\n[7] 잘못된 audience 토큰으로 호출 (aud=wrong-server → 403 기대)');
  const wrongAudToken = await fetch(`${ISSUER}/token?sa=kiosk-server&aud=wrong-server`).then((r) => r.json());
  const wrongAudRes = await fetch(`${ORDER_SERVER}/api/orders`, {
    headers: { Authorization: `Bearer ${wrongAudToken.token}` },
  });
  console.log('    상태 코드:', wrongAudRes.status);
  const wrongAudBody = await wrongAudRes.json();
  console.log('    응답:', wrongAudBody.error, '-', wrongAudBody.detail);

  console.log('\n' + '='.repeat(60));
  console.log(' 테스트 완료');
  console.log('='.repeat(60));
}

run().catch(console.error);
