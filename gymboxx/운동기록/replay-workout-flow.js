#!/usr/bin/env node
/**
 * 운동 기록 출석 플로우 재현 스크립트 (dev 전용)
 *
 * PASS 앱 · USER 앱 없이 아래 5단계를 한 번에 재현한다.
 *   1. USER APP  : 로그인 (PIN 또는 refresh_token) → access_token
 *   2. USER APP  : 출석 바코드 생성 (60초 내 소진 필요)
 *   3. USER APP  : app-web-socket 에 WebSocket 연결 (출석 알림 수신 대기)
 *   4. PASS APP  : 기기 로그인 → device token
 *   5. PASS APP  : 바코드 스캔 → 출석 처리 → 소켓 push 수신
 *
 * 상세 배경은 같은 폴더의 `운동기록.probe` 참고.
 *
 * 사용법:
 *   node replay-workout-flow.js                      # 전체 흐름
 *   node replay-workout-flow.js --listen             # 소켓 수신만 (앱 대신 대기)
 *   node replay-workout-flow.js --ping 12345         # access_history_id 로 소켓 push 만 재발사
 *
 * 인증 (우선순위 순):
 *   (기본)                              테스트 토큰 자체 발급 → access_token       # secret·PIN·DB 불필요
 *   GYMBOXX_REFRESH_TOKEN=... node ...   기존 refresh_token 으로 갱신
 *   GYMBOXX_PHONE=010... node ...        PIN 로그인 (알림톡 수신)
 */

const crypto = require('crypto')
const readline = require('readline')

// ws 모듈은 gymboxx-app-server 의 node_modules 를 빌려 쓴다
const WS_MODULE_PATH = process.env.WS_MODULE_PATH ?? '/Users/swkim/workspace/supplies/gymboxx-app-server/node_modules/ws'
const WebSocket = require(WS_MODULE_PATH)

const CONFIG = {
  appServer: 'https://dev1.supp.fitness/app',
  passServer: 'https://dev1.supp.fitness/pass',
  // configMap env (eks_dev/default) 의 APP_WEB_SOCKET_ENDPOINT — today-workout REST API
  socketRestEndpoint: 'https://kun6eu8mq0.execute-api.ap-northeast-2.amazonaws.com/dev',
  // app-web-socket/env.yml 의 WEB_SCOKET_ENDPOINT — 클라이언트가 붙는 WebSocket API
  socketWsEndpoint: 'wss://bq6ert948k.execute-api.ap-northeast-2.amazonaws.com/dev',

  userId: Number(process.env.GYMBOXX_USER_ID ?? 51758), // 김성욱 / Alan
  phone: process.env.GYMBOXX_PHONE ?? '', // PIN 로그인 시에만 필요
  refreshToken: process.env.GYMBOXX_REFRESH_TOKEN ?? '',

  gymId: Number(process.env.GYMBOXX_GYM_ID ?? 5), // 테스트 지점
  gymUniqueId: process.env.GYMBOXX_GYM_UNIQUE_ID ?? '000005',
  deviceId: process.env.GYMBOXX_DEVICE_ID ?? '9000000000004940',

  socketWaitMs: 20000,
}

const log = {
  step: (n, msg) => console.log(`\n[${n}] ${msg}`),
  info: (msg) => console.log(`    ${msg}`),
  ok: (msg) => console.log(`    ✓ ${msg}`),
  fail: (msg) => console.log(`    ✗ ${msg}`),
}

async function request(method, url, { token, body, deviceToken } = {}) {
  const headers = { accept: 'application/json' }
  if (body) {
    headers['Content-Type'] = 'application/json'
  }
  if (token || deviceToken) {
    headers.Authorization = `Bearer ${token ?? deviceToken}`
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await response.text()
  let parsed
  try {
    parsed = JSON.parse(text)
  } catch {
    parsed = text
  }
  if (!response.ok) {
    throw new Error(`${method} ${url} → HTTP ${response.status}\n    ${text}`)
  }
  return parsed
}

function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close()
      resolve(answer.trim())
    })
  })
}

/**
 * 테스트용 refresh_token 을 직접 만든다 (dev 편의).
 *
 * app-server 의 refreshUserToken 은 만료된 토큰을 decodeTokenWithoutVerify(= jwt.decode,
 * 서명 검증 없음)로 열어 user_id 만 읽는다. 저장된 refresh_token 과 대조하지도 않는다.
 * 따라서 exp 를 과거로 둔 JWT 는 서명 키와 무관하게 통과한다 — secret·PIN·DB 모두 불필요.
 *
 * ⚠️ 이는 dev 테스트 편의용 우회다. 같은 코드가 prod 에도 있어 인증 우회 취약점에 해당하므로
 *    별도 보안 이슈로 다룬다 (운동기록.probe 참고).
 */
function buildTestRefreshToken(userId, deviceId) {
  const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url')
  const header = b64({ alg: 'HS256', typ: 'JWT' })
  const payload = b64({
    user_id: userId,
    device_id: deviceId,
    exp: Math.floor(Date.now() / 1000) - 3600, // 과거 → 서명 검증 우회 경로 유도
  })
  const signature = crypto
    .createHmac('sha256', 'irrelevant-key')
    .update(`${header}.${payload}`)
    .digest('base64url')
  return `${header}.${payload}.${signature}`
}

/**
 * 1. USER APP 로그인 → access_token.
 *
 * 기본은 테스트 토큰 자체 발급. 환경변수로 실제 refresh_token / PIN 경로도 선택할 수 있다.
 */
async function login() {
  log.step(1, 'USER APP 로그인')

  const refreshToken =
    CONFIG.refreshToken || buildTestRefreshToken(CONFIG.userId, CONFIG.deviceId)

  if (!CONFIG.phone) {
    log.info(
      CONFIG.refreshToken
        ? 'refresh_token(env) 으로 갱신'
        : `테스트 토큰 자체 발급 (user_id=${CONFIG.userId})`,
    )
    const { tokens } = await request('PUT', `${CONFIG.appServer}/user/refresh-token`, {
      body: { refresh_token: refreshToken },
    })
    log.ok('access_token 발급 (2h)')
    return tokens
  }

  log.info(`PIN 발송 요청: ${CONFIG.phone}`)
  await request('GET', `${CONFIG.appServer}/user/pin?phone=${CONFIG.phone}`)
  const pin = await prompt('    알림톡으로 받은 4자리 PIN: ')

  const query = `phone=${CONFIG.phone}&pin=${pin}&unique_device_key=${CONFIG.deviceId}`
  const { tokens } = await request('GET', `${CONFIG.appServer}/user/pin/validation?${query}`)
  log.ok('로그인 성공')
  log.info('다음 실행부터는 아래 값을 환경변수로 넣으면 PIN 없이 진행된다:')
  log.info(`export GYMBOXX_REFRESH_TOKEN='${tokens.refresh_token}'`)
  return tokens
}

/**
 * 2. 출석 바코드 생성.
 *
 * 생성 후 60초 뒤 status 가 INACTIVE 로 바뀐다 (app-server user.service.ts:1280,
 * setTimeout 60000 — 함수 이름은 15초지만 실제 값은 60초). 즉시 4~5단계로 넘어가야 한다.
 */
async function createBarcode(accessToken) {
  log.step(2, '출석 바코드 생성')
  const { barcode } = await request('GET', `${CONFIG.appServer}/user/${CONFIG.userId}/barcode`, {
    token: accessToken,
  })
  log.ok(`barcode = ${barcode} (유효 60초)`)
  return barcode
}

/**
 * 3. app-web-socket 연결.
 *
 * $connect 람다는 user_id / gym_id 쿼리스트링만 확인하고 DynamoDB 에 connectionId 를 저장한다.
 * 인증이 없으므로 앱 없이 그대로 붙을 수 있다.
 */
function connectSocket() {
  log.step(3, 'WebSocket 연결')
  const url = `${CONFIG.socketWsEndpoint}?user_id=${CONFIG.userId}&gym_id=${CONFIG.gymId}`
  log.info(url)

  const socket = new WebSocket(url)
  const received = []

  socket.on('message', (data) => {
    const payload = data.toString()
    received.push(payload)
    console.log('\n📨 소켓 수신:')
    try {
      console.log(JSON.stringify(JSON.parse(payload), null, 2))
    } catch {
      console.log(payload)
    }
  })
  socket.on('error', (err) => log.fail(`소켓 오류: ${err.message}`))

  const ready = new Promise((resolve, reject) => {
    socket.on('open', () => {
      log.ok('연결됨 — DynamoDB 에 connectionId 등록')
      resolve()
    })
    socket.on('close', (code) => reject(new Error(`소켓이 닫힘 (code ${code})`)))
    setTimeout(() => reject(new Error('소켓 연결 타임아웃')), 10000)
  })

  return { socket, received, ready }
}

/** 4. PASS 앱 기기 로그인. */
async function passLogin() {
  log.step(4, 'PASS APP 기기 로그인')
  const result = await request('POST', `${CONFIG.passServer}/auth/login`, {
    body: { gym_unique_id: CONFIG.gymUniqueId, device_id: CONFIG.deviceId },
  })
  const deviceToken = result.token ?? result.access_token
  if (!deviceToken) {
    throw new Error(`토큰을 찾을 수 없음: ${JSON.stringify(result)}`)
  }
  log.ok('device token 발급')
  return deviceToken
}

/**
 * 5. 바코드 스캔 = 출석 처리.
 *
 * pass-server 가 access_history 를 만들고, 이어서 app-web-socket 의 today-workout 을 호출한다.
 * 단 그 호출은 try/catch 로 삼켜지므로(user.service.ts:421) 여기 응답이 200이어도
 * 소켓 push 가 갔다는 보장은 없다. 그래서 소켓 수신 여부를 따로 확인한다.
 */
async function scanBarcode(deviceToken, barcode) {
  log.step(5, 'PASS APP 바코드 스캔 → 출석')
  const result = await request('POST', `${CONFIG.passServer}/user/barcode-access`, {
    deviceToken,
    body: { barcode },
  })
  // serializer 는 access_type 을 `status` 필드로 내려준다 (user.serializer.ts:46).
  const status = result.status
  log.ok(`status(access_type) = ${status}`)
  log.info(`raw 응답: ${JSON.stringify(result)}`)
  if (status === 'REENTER') {
    log.fail('REENTER 는 소켓 push 대상이 아니다 (ACCESS / REVISIT 만 ping).')
  } else if (status !== 'ACCESS' && status !== 'REVISIT') {
    log.fail(`${status} 는 소켓 push 대상이 아니다. 멤버십/출입 상태 확인 필요.`)
  }
  return result
}

/** today-workout 을 직접 호출해 소켓 push 만 재발사한다. */
async function pingSocket(accessHistoryId) {
  const url = `${CONFIG.socketRestEndpoint}/today-workout/${CONFIG.userId}?access_history_id=${accessHistoryId}&gym_id=${CONFIG.gymId}`
  log.info(`ping: ${url}`)
  await request('GET', url)
  log.ok('today-workout 호출 완료')
}

function waitForMessage(received, ms) {
  const startedCount = received.length
  return new Promise((resolve) => {
    const startedAt = Date.now()
    const timer = setInterval(() => {
      if (received.length > startedCount) {
        clearInterval(timer)
        resolve(true)
      } else if (Date.now() - startedAt > ms) {
        clearInterval(timer)
        resolve(false)
      }
    }, 200)
  })
}

async function main() {
  const args = process.argv.slice(2)
  const listenOnly = args.includes('--listen')
  const pingIndex = args.indexOf('--ping')
  const pingAccessHistoryId = pingIndex >= 0 ? args[pingIndex + 1] : null

  console.log('운동 기록 출석 플로우 재현 (dev)')
  console.log(`user_id=${CONFIG.userId} gym_id=${CONFIG.gymId} device_id=${CONFIG.deviceId}`)

  const { socket, received, ready } = connectSocket()
  await ready

  try {
    if (listenOnly) {
      log.info(`수신 대기 중… (Ctrl+C 로 종료)`)
      await new Promise(() => {})
      return
    }

    if (pingAccessHistoryId) {
      log.step('P', `today-workout 직접 호출 (access_history_id=${pingAccessHistoryId})`)
      await pingSocket(pingAccessHistoryId)
    } else {
      const tokens = await login()
      const barcode = await createBarcode(tokens.access_token)
      const deviceToken = await passLogin()
      await scanBarcode(deviceToken, barcode)
    }

    log.step(6, `소켓 push 대기 (최대 ${CONFIG.socketWaitMs / 1000}초)`)
    const got = await waitForMessage(received, CONFIG.socketWaitMs)
    if (got) {
      log.ok('출석 → 소켓 전달까지 정상 동작')
    } else {
      log.fail('소켓 push 없음. pass-server 의 pingWebSocketServer 실패 또는 REENTER 로 추정.')
    }
  } finally {
    socket.close()
  }
}

main().catch((err) => {
  console.error(`\n실패: ${err.message}`)
  process.exit(1)
})
