# TODO

## publish 워크플로 속도 개선 (미룸, 2026-09-17 기록)

`.github/workflows/publish.yaml` 이 preppers-kds-lib 의 `release.yml` 보다 약 30초 느리다.
하는 일은 더 적은데(semantic-release·CHANGELOG·GitHub Release·develop 동기화·Slack 알림 전부 없음) 더 느리다.

### 측정값

- gymboxx-lib  run 35183932605 — job 86초
- preppers-kds-lib run 35068791849 — job 56초

```
gymboxx  : added 399 packages, and audited 400  packages in 1m
preppers : added 903 packages, and audited 1069 packages in 19s
```

### 원인

1. **npm 캐시 없음 (약 42초)** — preppers 는 `setup-node@v4` 에 `cache: 'npm'` 이 있고 gymboxx 는 없다.
   패키지 수는 preppers 가 2.3배 많은데 설치는 1/3 시간.
2. **같은 빌드 3회 (약 12초 낭비)** — `package.json` 의 `prepare: "npm run build"` 때문에
   `npm ci` · `npm build` 스텝 · `npm publish` 에서 각각 `tsc` 2회씩 돈다. 회당 약 6초.

부차적 — Node 18 vs 22, `checkout`/`setup-node` v3 vs v4. 몇 초 수준.

### 손볼 내용

- `setup-node` 에 `cache: "npm"` + `cache-dependency-path: package-lock.json` 추가
- `npm build` 스텝 제거 (`npm publish` 의 `prepare` 가 어차피 빌드한다)
- 기대치: 86초 → 약 40초

### 주의

- `prepare` 를 아예 없애면 git 설치(`npm i <repo>`) 시 `lib/` 이 빌드되지 않는다. 제거는 빌드 스텝 쪽만.
- 캐시 추가는 `package-lock.json` 해시 기준이라 lock 갱신 시 첫 런은 여전히 느리다.

## entity parity 컬럼명 비교 개선 (미룸, 2026-09-17 기록)

`src/entity-camel/crm/app_instance.ts`의 `deviceOS` 때문에 parity 도구가
`device_os` → `deviceOS` 예외 규칙을 가지고 있다.

### 손볼 내용

- `AppInstanceEntity.deviceOS`의 `@Column`에 `name: 'device_os'`를 명시한다.
- parity 검사가 프로퍼티명의 기계적 snake/camel 변환보다 명시된 `@Column.name`을 우선해 비교하도록 개선한다.
- `ops/scripts/entity-parity/naming.ts`의 `NAME_EXCEPTIONS`와 관련 문서·테스트를 제거한다.

### 주의

- `deviceOS` 프로퍼티 자체를 `deviceOs`로 바꾸는 작업은 별개다. 변경 시 패키지 소비 코드의 호환성을 먼저 확인한다.
