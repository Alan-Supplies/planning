# gymboxx app-api liveness/readiness probe 타임아웃 (2026-09-03)

## 증상
dev-eks `gymboxx` 네임스페이스 `app-api` 에서 이벤트 발생:

```
Liveness probe failed: Get "http://100.65.100.34:8080/hc": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

## 조사

- 이벤트는 **2026-09-03 04:22:37Z 단 1회**. liveness/readiness 각각 `count: 1` 이고
  `failureThreshold: 3` 에 닿지 않아 파드는 계속 `1/1 Running`, `restarts 0` 이었다 —
  실제 재시작·다운타임은 없었음.
- 같은 시각 앱 로그(`kubectl logs app-api-... -n gymboxx -c app-api`)를 보면
  사용자 1명(`userId=52448`)이 앱을 여는 동안 04:22:35~37 사이 요청 20여 건이
  몰렸고 latency 가 이렇게 튀었다:

  ```
  04:22:36.658  1398ms  GET /app/user/52448/membership/
  04:22:36.765  1412ms  GET /app/user/52448/pt-history/review
  04:22:37.521  2215ms  GET /app/user/52448/membership/
  04:22:37.664  2395ms  GET /app/gym/5/info
  ```

- 파드 spec 실측 probe:
  ```
  kubectl get pod <pod> -n gymboxx -o json --context=arn:aws:eks:ap-northeast-2:699016088228:cluster/dev-eks
  ```
  → `timeoutSeconds: 1` (k8s 기본값). `apps/gymboxx/app-api/values.yaml` 에
  `timeoutSeconds` 를 안 적어서 그렇게 됐고, `/hc` 도 같은 이벤트 루프를 타므로
  위 구간에서 1초를 넘길 수밖에 없었다.

## 원인

앱 장애가 아니라 **probe 예산이 너무 타이트**했던 것. 3회 연속 실패하면
컨테이너가 죽고, 재기동 중 런타임 TS 컴파일(`npm start` → `nest start`)이
CPU 를 다시 몰아쓰므로 재시작 루프로 번질 수 있는 구조였다.

## 조치

`apps/gymboxx/app-api/values.yaml` 의 probes 에 `timeoutSeconds` 명시.
차트 helper(`charts/preppers-service/templates/_helpers.tpl`)가 이미 지원해서
값만 넣으면 됨.

| probe | timeoutSeconds | 최악 감지 시간 |
|---|---|---|
| startup | 5 | 10s x 30 |
| readiness | 3 | 5s x 3 |
| liveness | 5 | 10s x 3 = 최대 45초 |

liveness 는 "프로세스가 정말 죽었는가"만 판별해야 하므로 느린 응답에 관대해야
한다. 45초는 hq-api 사례(npm 은 살아있고 node 만 죽은 상태, 2026-08-10)식
"죽은 프로세스" 감지 목적에는 충분.

PR: https://github.com/suppliesfitness/platform-gitops/pull/117 (base `main`,
platform-gitops 는 develop 브랜치가 없어 main PR 1건만)

## 후속 (이 PR 범위 밖)

- **gymboxx 전체 동일 문제**: `apps/gymboxx/*/values.yaml` 23개 전부
  `timeoutSeconds` 미설정(=1초). `app-api` 만 먼저 고침.
- **노드 CPU 압박**: `app-api` 가 올라간 `ip-10-20-74-100`(t3.large,
  allocatable CPU 1930m)에 gymboxx api 파드 4개(`app-api`, `pass-api`,
  `public-api`, `trainer-api`)가 각 `limits.cpu: 750m` = 합계 3000m 으로
  allocatable 초과 배치. `values.yaml` 주석에 적힌 2026-08-10 argocd-server
  사고와 같은 구조. platform-iac 소유라 별건.
- **metrics-server**: dev-eks 에서 `kubectl top` 이
  `Metrics API not available` — CPU 스로틀링 실측 불가.
