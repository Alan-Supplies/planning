# 작업 지시: `score.ts` — strict 플래그 채점기

## 컨텍스트와 범위

`gymboxx-app-server` 레포에서, **현재 설정에 TypeScript 플래그 하나를 추가했을 때 지정 모듈에 보고되는 컴파일 에러**를 측정하는 CLI를 만든다.

이건 자동화 루프의 채점기다. 지금은 **채점기만** 구현·검증한다. 에이전트, 오케스트레이터, 정책, 경쟁 로직, sweep 구현은 별도 작업이다. 기존 구현이 있으면 먼저 확인하고 아래 계약에 맞게 보완한다.

[기존 구현·sweep 기록](agent2agent-project.md)의 baseline 미차감, 임시 설정의 타입 탐색, 반복 컴파일 비용 문제를 반영했다. 그 문서의 과거 실행 결과는 이번 구현의 검증 결과로 대신하지 않는다.

**판정의 한계:** TypeScript 옵션은 모듈에만 적용되지 않고 import로 연결된 프로그램 전체에 적용된다. 모듈 경계는 진단의 집계 범위다. `gate: true`는 해당 범위의 컴파일 에러가 없다는 뜻이며, 전체 레포의 빌드 통과나 런타임 동작 보존을 보장하지 않는다.

## 인터페이스와 출력 계약

레포 루트에서 실행한다. 아래 경로는 `tools/` 기준이며, 기존 관례가 `scripts/`라면 그쪽으로 통일한다.

```sh
npx --no-install tsx tools/score.ts <moduleDir> <flag>
npx --no-install tsx tools/score.ts src/modules/membership strictNullChecks
```

`tsx`가 이미 설치된 경우의 예시다. 없으면 레포에 있는 실행 수단을 사용하고 실제 명령을 기록한다. 실행을 위해 패키지를 자동 다운로드하지 않는다.

정상 측정은 stdout에 JSON **한 줄만** 출력한다. 아래는 가독성을 위해 펼친 예시다.

```json
{
  "module": "src/modules/membership",
  "flag": "strictNullChecks",
  "flagAlreadyEnabled": false,
  "typescriptVersion": "5.6.3",
  "gate": false,
  "errors": 47,
  "errorsByCode": { "TS2532": 21, "TS18048": 19, "TS2345": 7 },
  "baselineErrors": 7,
  "introducedErrors": 40,
  "introducedErrorsByCode": { "TS2532": 21, "TS18048": 19 },
  "ignoredErrors": 2,
  "cost": { "nullish": 3, "optChain": 12, "nonNull": 1, "asCast": 4, "anyType": 0 },
  "files": 14,
  "durationMs": 3120
}
```

- `module`: 레포 루트 기준 상대 경로를 `/` 구분자로 정규화한 값.
- `flagAlreadyEnabled`: 상속과 `strict` 기본값까지 해석한 기존 설정에서 요청 플래그가 이미 유효한지.
- `typescriptVersion`: CLI와 AST 분석에 공통으로 사용한 실제 로컬 TypeScript 버전. 예시 버전으로 고정하지 않는다.
- `errors`, `errorsByCode`: 플래그를 켠 뒤 **채점 대상 파일**에 발생한 전체 에러와 코드별 집계. 코드별 합은 `errors`와 같아야 한다.
- `baselineErrors`: 동일 파일·설정에서 요청 플래그를 추가하기 전의 에러 수.
- `introducedErrors`, `introducedErrorsByCode`: probe 진단에서 baseline 진단을 차감한 신규 에러와 코드별 집계. 단순한 총개수 차이가 아니다.
- `gate`: 정상 측정이고 `errors === 0`일 때만 true. 기존 에러만 남아도 false다. `introducedErrors === 0`은 별도로 해석한다.
- `ignoredErrors`: probe에서 채점 대상 밖의 소스 파일에 귀속되어 제외한 에러 수. 설정 오류와 파일 위치 없는 오류를 여기에 숨기지 않는다.
- `cost`: 기존 소스의 문법 사용량. 기준선 관측값이며 가중합 점수나 합격 조건이 아니다.
- `files`: 에러 집계와 cost 분석에 사용하는 채점 대상 파일의 개수. import된 외부 파일·타입 선언은 포함하지 않는다.
- `durationMs`: 입력 검증부터 측정·정리까지의 경과 시간. 결정성 비교에서는 제외한다.
- 정상 측정은 `gate`와 무관하게 exit 0. 입력·설정·실행·파싱 실패는 non-zero이며 stdout에 점수 JSON을 출력하지 않는다. 실패 원인과 로그는 stderr로 보낸다.

## 지원 플래그와 선행 조건

아래 값만 허용한다. 현재 설치된 TypeScript가 해당 옵션을 지원하는지도 확인한다.

- `strictNullChecks`
- `noUncheckedIndexedAccess`
- `exactOptionalPropertyTypes`
- `noImplicitAny`
- `noImplicitOverride`

기존 타입 검사 옵션을 유지하고 요청한 플래그 하나만 `true`로 덮어쓴다. 다른 플래그를 끄거나 `strict: true`를 일괄 적용하지 않는다. 이미 켜진 플래그는 정상 측정하되 `flagAlreadyEnabled: true`로 표시한다.

`exactOptionalPropertyTypes`는 `strictNullChecks`가 필요하다. `noUncheckedIndexedAccess`도 null 검사가 꺼진 상태에서는 기대하는 undefined 접근 오류를 잡는 과제로 사용할 수 없다. **이 두 플래그는 기존의 유효한 `strictNullChecks`가 true일 때만 측정한다.** 아니면 선행 조건 미충족으로 non-zero 종료한다. 몰래 두 플래그를 동시에 켜지 않는다. `strict: true`여도 명시적인 `strictNullChecks: false`가 우선한다.

기존 설정이 `noCheck: true`라면 타입 검사를 생략한 통과를 만들지 말고 설정 오류로 종료한다.

## 동작

### 1. 입력과 채점 대상 확정

- cwd를 레포 루트로 사용하고 루트의 `tsconfig.json`, 로컬 TypeScript, 디렉터리 인자와 플래그를 검증한다. 인자 누락·추가, 없는 경로, 파일 경로, 레포 밖으로 나가는 경로는 실패다.
- TypeScript 설정 API로 JSONC와 `extends`를 해석한다. `JSON.parse`만으로 설정을 읽지 않는다.
- 기본 설정에서 해석된 루트 파일 중 `<moduleDir>` 하위 `.ts`, `.tsx`, `.mts`, `.cts` 구현 파일을 채점 대상으로 한다. 테스트(`*.spec.*`, `*.test.*`, `__tests__/`), 선언 파일(`.d.ts`, `.d.mts`, `.d.cts`), `node_modules`는 제외한다. 기존 `exclude`를 존중한다.
- realpath와 `path.relative`로 경계를 판정한다. 문자열 prefix 비교로 `src/user-old`를 `src/user` 안으로 오인하지 않는다. 심볼릭 링크로 레포·모듈 밖을 가리키는 파일은 채점 대상에 넣지 않는다.
- 대상 목록을 정렬·중복 제거하고 baseline, probe, cost가 같은 목록을 쓰게 한다. 대상이 0개면 실패다. 비어 있는 모듈을 통과로 처리하지 않는다.
- 기본 설정이 포함하던 전역 선언 파일은 컴파일 입력에 유지하되 채점 대상에는 넣지 않는다. 별도 `.ts` 파일의 전역 선언 등 추가 입력이 필요한 구조는 실제 레포에서 확인하고 명시한다.

### 2. baseline과 probe 설정 생성

- `mkdtemp`로 실행별 고유한 임시 디렉터리를 만들고 `tsconfig.baseline.json`, `tsconfig.probe.json`을 생성한다. 정상·실패 경로 모두 `finally`에서 정리하고 SIGINT/SIGTERM에도 자식 프로세스 종료와 정리를 시도한다.
- 둘 다 레포 루트 `tsconfig.json`의 **절대 경로**를 `extends`한다. `files`에 확정한 채점 대상과 유지할 전역 선언 파일의 절대 경로를 넣고 `include: []`로 설정한다. 부모의 `files`나 상대 glob이 다른 파일을 끌어오지 않게 한다.
- `baseUrl`, `paths`, `types`, 명시적 `typeRoots` 등 기존 해석 환경을 보존한다. `typeRoots`가 없으면 레포 기준의 유효한 `node_modules/@types` 탐색 경로를 계산해 명시한다. 상위 디렉터리의 타입 경로도 고려하고 임시 폴더 기준 자동 탐색에 맡기지 않는다.
- 양쪽 모두 `noEmit: true`, `composite: false`를 적용한다. 상속된 `tsBuildInfoFile` 충돌과 레포 내 캐시 쓰기를 피하도록 `incremental: true`, `tsBuildInfoFile: <각 설정별 임시 경로>`를 적용한다. 실행 간 캐시는 공유하지 않는다.
- baseline은 기존 타입 검사 옵션을 유지하고 probe만 요청 플래그를 `true`로 한다. 파일 집합과 나머지 설정은 동일해야 한다.
- `references`는 상속되지 않는다. 기존 설정에 project references가 있다면 이번 단일 프로젝트 채점기의 지원 밖임을 명시하고 실패한다. 참조를 조용히 누락하거나 `tsc -b`로 다른 프로젝트를 빌드하지 않는다.

### 3. 로컬 tsc 실행과 진단 분류

- 레포에서 resolve한 `typescript`의 CLI를 `process.execPath`로 실행한다. 전역 `tsc`나 다운로드 가능한 `npx tsc`에 의존하지 않는다. AST API도 같은 설치본을 사용한다.
- 인자는 배열로 전달하고 shell 문자열로 조합하지 않는다. cwd는 레포 루트로 고정한다.
- 양쪽에 `--noEmit --pretty false --locale en -p <config>`를 사용한다. 상속된 진단 통계·파일 목록 출력 옵션은 꺼서 출력 형식을 고정한다.
- stdout와 stderr를 모두 수집한다. 컴파일별 제한 시간은 120초로 두고, 시간 초과·spawn 실패·시그널 종료·출력 유실/버퍼 초과는 측정 실패다.
- `path(line,col): error TSxxxx: message`를 진단 하나로 읽는다. 여러 줄 메시지의 후속 줄은 그 진단에 붙이고 중복 카운트하지 않는다. 공백·괄호·드라이브 문자가 있는 경로와 CRLF도 처리한다.
- 채점 대상 파일의 진단만 `errors`에 센다. 외부 파일의 진단은 `ignoredErrors`로 집계한다. `error TSxxxx: ...`처럼 위치 없는 진단, tsconfig 진단, 설정 API 오류는 측정 실패다.
- tsc의 에러 종료 자체는 정상 측정일 수 있지만 **종료 코드를 무조건 무시하지 않는다.** 설치된 CLI의 정상/진단 종료 상태만 허용하고, non-zero인데 인식된 진단이 없거나 출력·상태가 모순되면 실패한다. 파서가 모르는 독립 출력도 조용히 버리지 않는다.

### 4. baseline 차감

진단 식별자는 `정규화된 파일 경로 + 행 + 열 + TS 코드 + 전체 메시지`로 만든다. 메시지는 줄바꿈 형식만 정규화한다. 동일 진단의 중복 개수를 보존하는 **다중집합 차감**으로 `probe − baseline`을 구한다. 에러 코드만 비교하거나 `max(0, probe 개수 − baseline 개수)`로 대체하지 않는다.

예를 들어 baseline에 TS2339 1개, probe에 그 TS2339와 TS2322 1개가 있으면 `errors: 2`, `baselineErrors: 1`, `introducedErrors: 1`, `gate: false`다. probe에서 기존 오류가 사라지고 다른 오류 1개가 생겨도 신규 오류는 1개다.

비교는 **한 실행의 같은 소스 상태**에 한정한다. 수정 전후로 줄 번호가 바뀐 진단을 같은 오류로 추적하는 기능은 이번 범위가 아니다. 소스나 설정이 baseline/probe 사이에 바뀐 사실을 감지하면 결과를 폐기한다. 이미 활성화된 플래그라면 신규 에러가 0이어야 한다.

### 5. AST cost 카운트

정규식으로 소스 문법을 세지 않는다. 채점 대상 파일을 `ts.createSourceFile`로 파싱하고 확장자에 맞는 ScriptKind로 순회한다. 파싱 오류를 무시하고 부분 AST의 cost를 정상값으로 내보내지 않는다.

| 항목 | 카운트 규칙 | 제외·경계 사례 |
|---|---|---|
| `nullish` | BinaryExpression의 `operatorToken`이 `QuestionQuestionToken`이면 1 | `??=`는 제외 |
| `optChain` | 접근·인덱스·호출 노드의 명시적 `questionDotToken`마다 1 | `a?.b.c`는 1, `a?.b?.()`는 2; 체인에 속한 모든 노드를 세지 않음 |
| `nonNull` | `NonNullExpression`마다 1 | `!x`, `!=`, `!==`, 선언의 `field!: T`는 제외 |
| `asCast` | `AsExpression`마다 1 | `as const` 포함, import/export 별칭·`satisfies`·`<T>x`는 제외; 이중 단정은 2 |
| `anyType` | 타입 위치의 `AnyKeyword`마다 1 | 추론된 any, 문자열·주석·프로퍼티 이름의 `any`는 제외 |

`ts.forEachChild` 순회와 부모 노드의 토큰 확인을 중복 적용해 같은 문법을 두 번 세지 않는다. 0인 항목도 항상 출력한다.

`??`와 `?.`는 정상적인 방어 코드일 수 있다. cost가 낮다고 좋은 수정이라고 판단하지 않는다. 또한 이 다섯 항목만으로 `<T>x`, 선언의 `!`, `@ts-ignore`/`@ts-expect-error`/`@ts-nocheck`, 파일 삭제, 타입 의미 변경을 막을 수 없다. **현재 결과는 기준선 측정용이다.** 자동 수정의 보상으로 사용하기 전에는 평가기·설정·대상 파일 목록 보호, 검사 억제 및 단정 변경 검토, 별도 동작 검증을 마련해야 한다. 이번 작업에서 자동화 정책까지 구현하지 않는다.

## 제약

- 런타임 의존성 추가 금지. Node 내장 모듈과 레포의 `typescript`만 사용한다.
- 산출물은 `tools/score.ts` 또는 `scripts/score.ts` 단일 파일이다. `tsconfig.json`, `package.json`, lockfile, 기존 소스는 읽기만 한다.
- 임시 검증 fixture는 레포 밖에 만들고 정리한다. 검증을 위해 실제 모듈을 수정하지 않는다.
- stdout에는 최종 결과 한 줄만 출력한다. 모든 키의 출력 순서와 코드별 집계 순서를 고정한다.

## 검증 — 구현 후 반드시 수행

기대값이 명확한 임시 fixture로 먼저 확인한 뒤 실제 모듈에서 smoke test한다. 실제 모듈에 특정 플래그를 켜면 반드시 오류가 날 것이라고 가정하지 않는다. fixture는 프로젝트 기본 옵션의 영향을 통제하며, 전역 변수 충돌을 피하도록 `export {}`를 사용한다.

1. **통과/실패:** 깨끗한 fixture는 `gate: true`. `strictNullChecks: true`에서 `const xs: string[] = []; const s: string = xs[0];`는 `noUncheckedIndexedAccess` probe에 신규 TS2322를 만든다. 둘 다 프로세스는 exit 0이다.
2. **baseline:** 기존 TS2339가 두 실행에 남고 probe에만 TS2322가 추가되는 경우와, 기존 오류가 사라지고 다른 오류가 생겨 총개수가 같은 경우를 검증한다. 메시지가 여러 줄인 진단도 식별·차감된다.
3. **선행 조건:** `strictNullChecks: false`에서 두 종속 플래그는 non-zero. `strict: true`로 상속된 활성값과 명시적 false override를 구분하고, 이미 켜진 플래그는 `flagAlreadyEnabled: true`, `introducedErrors: 0`이다.
4. **AST:** `foo!.bar`, `x as string`, `a ?? b`, `a?.b`, `let v: any`는 해당 항목 각각 1. 표의 제외 사례, optional 호출·인덱스, 이중 단정, 문자열·주석을 섞어도 정확한지 확인한다. 테스트·선언 파일의 문법은 cost에서 제외된다.
5. **대상/환경:** 외부 import의 오류는 점수에서 제외되고 `ignoredErrors`에 남는다. `src/user-old` 경계, 빈 모듈, 기존 `files`/`exclude`, 전역 `.d.ts`, Node 전역 타입, 공백·괄호 경로, `incremental`/`tsBuildInfoFile` 상속을 검증한다.
6. **실패 처리:** 없는 경로, 잘못된 플래그·설정, 위치 없는 진단, tsc 실행 실패, timeout, 인식 불가능한 출력에서 non-zero이며 stdout에 정상 점수가 없는지 확인한다.
7. **결정성/격리:** 같은 인자로 연속 2회와 동시 2회 실행해 `durationMs`를 제외한 결과 전체가 동일한지 확인한다. 다르면 원인을 해결하기 전 채점기로 사용하지 않는다. 임시 설정과 캐시가 서로 충돌하지 않아야 한다.
8. **실제 레포:** 작은 실제 모듈에서 baseline/probe 진단의 수동 집계와 JSON을 대조한다. 실행 전후 `git status`를 비교해 새 구현 파일 외에 변경이 추가되지 않았는지, 성공·실패 뒤 임시 파일과 레포 내 캐시가 남지 않았는지 확인한다. 기존 사용자 변경을 지우지 않는다.

검증 결과에는 실제 실행 명령, TypeScript 버전, 통과·실패한 항목과 미확인 사항을 남긴다. 미실행 항목을 통과로 보고하지 않는다.

## 다음 단계 — 이번에는 구현·실행하지 않음

채점기 검증 뒤 별도 작업으로 모듈 × 플래그 조합을 측정해 `sweep.jsonl`을 만든다. 모듈의 기준 깊이·중첩 모듈 중복 처리부터 확정한다. 기존 기록에서는 `src/modules/` 아래 38개를 사용했다.

- 이미 활성화된 플래그와 선행 조건 미충족 조합은 과제 후보에서 제외한다. 측정 실패를 0점으로 저장하지 않는다.
- 난이도 분류는 `errors` 대신 **`introducedErrors`** 기준으로 한다: 0은 신규 과제 없음, 1~9는 작은 과제, 10~80은 우선 후보, 81~150은 큰 과제/보류, 151 이상은 제외.
- `baselineErrors > 0`인 모듈은 기존 오류 정리 필요로 별도 표시한다. 신규 오류가 없어도 `gate: true`로 바꾸지 않는다.
- `include` 제한은 import된 파일의 검사 비용을 없애지 않는다. sweep에서는 baseline 프로그램 1개 + 플래그별 프로그램 1개를 재사용하고 진단을 모듈별로 나누는 최적화를 검토한다. 단, 입력 파일 집합 차이로 결과가 달라질 수 있으므로 단일 모듈 채점 결과와의 동등성을 먼저 검증한다.

## 참고 근거

- [기존 프로젝트 기록](agent2agent-project.md): baseline 오염, 타입 탐색 문제, sweep 결과와 프로그램 재사용 제안.
- [TypeScript 설정 상속](https://www.typescriptlang.org/tsconfig/extends.html): 상대 경로 기준, `files`/`include`/`exclude` 덮어쓰기와 `references` 비상속.
- [TypeScript TSConfig](https://www.typescriptlang.org/tsconfig/): import와 `exclude`의 관계, `incremental`/`tsBuildInfoFile`, 타입 탐색 설정.
- [TypeScript 4.4](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-4.html): `exactOptionalPropertyTypes`의 `strictNullChecks` 선행 조건.
- [TypeScript noCheck](https://www.typescriptlang.org/tsconfig/noCheck.html): 타입 검사 생략 옵션.
