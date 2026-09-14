# TECH-997 배포 런북

> 작성 2026-08-31 · [TECH-997](https://linear.app/suppliesfitness/issue/TECH-997)
> 대상 PR — lib [#260](https://github.com/suppliesfitness/gymboxx-lib/pull/260) · app-server [#705](https://github.com/suppliesfitness/gymboxx-app-server/pull/705)
> 관련 문서 — `DB_구조_업그레이드_방안.md` §01 · `TECH-997-효과축-추천태그-분리.claude.md` (결정 기록) · `TECH-997-제약검증.claude.sql`

## 이 배포의 성격

**자동분(§1~§5)은 추가·백필만 한다.** 기존 테이블을 바꾸지 않고 `exercise_function` 도 그대로 둔다.
그래서 구버전 앱과 호환되고, 롤백이 `DROP TABLE` 3개로 끝난다.

🔴 **순서의 핵심 한 가지** — 운영 마이그레이션이 app-server 배포보다 **먼저**여야 한다.
app-server 가 `exercise_effect` · `exercise_recommend_tag` relation 을 로드하므로 테이블이 없으면 추천 API 가 깨진다.
반대 방향(마이그레이션만 먼저)은 안전하다. 구버전 app-server 는 새 테이블을 읽지 않는다.

## 브랜치 전략 — GitHub Flow

- 모든 피처 브랜치는 **`main` 에서 딴다.** `develop` 에서 따지 않는다
- **`develop` 머지는 테스트 배포용**이다. 피처의 최종 목적지가 아니다
- 작업 중에는 **`main` 으로 주기적 rebase** 한다 (`git rebase origin/main`)
- **`main` 용 PR 은 별도 지시가 있을 때만** 만든다

레포별로 이렇게 적용된다.

| 레포 | PR base | 테스트 배포 | 비고 |
|---|---|---|---|
| gymboxx-lib | `main` | `-dev.N` 태그 프리릴리스 | 배포가 npm publish 라 develop 머지가 불필요하다 |
| gymboxx-app-server | `develop` (테스트) | develop 머지 → dev 환경 | `main` PR 은 지시가 있을 때 |

---

## Phase 0 — 준비

- [ ] **VPN 연결** (dev·운영 DB 접속 필수)
- [ ] ⚠️ VPN 연결 시 GitHub 접근이 DNS 문제로 막힐 수 있다. git 작업과 DB 작업을 번갈아 할 때 확인
- [ ] **dev DB 쓰기 권한 계정** 확보 (읽기 전용 `readonly_ssl` 로는 Phase 1 불가)
- [ ] **운영 DB 쓰기 권한 계정** 확보 (Phase 4)
- [ ] 🔴 **git 브랜치 확인** — 같은 클론을 여러 세션이 공유한다. 매 작업 전 `git branch --show-current`

```sh
cd /Users/swkim/workspace/supplies/gymboxx-lib && git branch --show-current
cd /Users/swkim/workspace/supplies/gymboxx-app-server && git branch --show-current
# 기대: 둘 다 feature/tech-997/exercise-effect-split
```

- [ ] **`main` 으로 rebase** — 배포 직전에 한 번 더 (main 이 앞서갔을 수 있다)

```sh
git fetch origin
git rebase origin/main
git log --oneline origin/main..HEAD    # 내 커밋만 남아야 정상
npx tsc --noEmit -p tsconfig.json      # rebase 후 검증
git push --force-with-lease
```

### 원 설계자 확인 — Phase 3(머지) 전에 완료

`exercise_function` 과 app-server `exercise-recommendation` 모듈은 **둘 다 Austin 이 만들었다**
(lib 엔티티·SQL 2026-05-21 · 추천 모듈 20커밋 중 20개). 아래는 이관하며 추론으로 메운 부분이라
원 의도 확인이 필요하다. 리뷰 요청은 직접 한다.

- [ ] 🔴 **`STRENGTH_GAIN` 이 `ENDURANCE` 를 참조하는 것이 의도인지**

  ```ts
  // constants/goal-to-specific-compatibility.constants.ts
  [USER_EXERCISE_PURPOSE.STRENGTH_GAIN]: [EXERCISE_EFFECT_TAG.ENDURANCE]
  ```

  근력 증가 목적이 **지구력만** 본다. 이관 전부터 그랬고 이번에 바꾸지 않았지만,
  `STRENGTH` 값이 새로 생겼으므로 여기 넣을지 판단할 수 있는 시점이다.

  ⚠️ **답이 "바꾼다" 면 추천 결과가 달라진다.** 코드 변경 후 Phase 1 검증(추천 before/after)을
  다시 해야 하므로 머지 전에 결론이 나야 한다.

  참고 — `ENDURANCE` 는 6개 목적 중 **4개**가 참조한다:
  `WEIGHT_LOSS` · `STRENGTH_GAIN` · `ENDURANCE_GAIN` · `ATHLETIC_PERFORMANCE`.
  이 태그를 건드리면 영향 범위가 가장 넓다.

- [ ] 기능성 풀 판정을 **"근력 제외 효과 축 + 추천 태그"** 로 재현한 것이 원래 의도와 같은지
      (이관 후 `STRENGTH` 가 225종에 붙어 "매핑 보유" 조건을 그대로 쓸 수 없었다)
- [ ] 5개 태그의 축 분류(효과 축 `ENDURANCE`·`MOBILITY`·`BALANCE` / 추천용 `FAT_LOSS`·`RECOVERY`)가
      원 설계와 맞는지
- [ ] 응답 `specific` 필드에 `STRENGTH` 가 새로 나타나는 것 — 클라이언트 노출 여부 확인

### ✅ dev / 운영 스키마 정렬 확인 — **2026-08-31 완료. 이상 없음**

운동 도메인 7개 테이블의 컬럼 구성이 **dev·운영에서 완전히 일치**한다.
`sig` 는 `CONCAT(column_name,':',column_type)` 을 ordinal 순으로 이어 붙인 MD5 다.

| 테이블 | cols | sig (dev = 운영) |
|---|---|---|
| `body_part` | 4 | `df028167…` ✅ |
| `body_part_detail` | 5 | `a1b77fca…` ✅ |
| `exercise` | 14 | `64b13bcb…` ✅ |
| `exercise_body_part` | 5 | `0b4cfb55…` ✅ |
| `exercise_body_part_detail` | 5 | `f2fbd2d6…` ✅ |
| `exercise_function` | 2 | `7d687bf8…` ✅ |
| `exercise_machine` | 2 | `6fb4ae78…` ✅ |

**이 마이그레이션이 FK·조인으로 참조하는 테이블이 전부 같으므로 Phase 1 의 dev 검증 결과를
운영에 그대로 적용할 수 있다.**

MySQL 버전도 같다 — **dev 8.0.45 / 운영 8.0.45**. 생성 열 동작이 갈릴 여지가 없다.

#### 다만 두 가지는 다르다

**① dev 에 생성 열 선례가 0건이다** (운영 1건 — `payment_card.favorite_user_id`)

`V4_28_9__pii_financial_columns_expand.sql` · `V4_28_14__payment_card_favorite_unique.sql` 이
dev 에 반영되지 않았다 (`payment_card.number` dev `varchar(20)` / 운영 `varchar(85)`).
운동 도메인과 무관해 이 작업에는 영향이 없지만, **Phase 1 이 dev 에서 생성 열을 처음 만드는 셈**이라
제약 검증 5가지의 비중이 그만큼 크다.

**② 데이터는 여전히 다르다** — 스키마가 같다는 것이지 행이 같다는 뜻이 아니다.

| | dev | 운영 |
|---|---|---|
| `exercise` | 275종 | 273종 |
| `exercise_function` | 88행 | 87행 |
| 근육 부위 라벨 보유 | 220종 | 253종 |

**Phase 1 의 행수가 288/24 와 다르게 나오는 것은 정상이다.** 규칙의 정확성은 운영 SELECT 로
이미 확인했고(253/28/225), Phase 1 에서 볼 것은 제약과 SQL 이 도는지다.

---

## Phase 1 — dev 검증 (30분)

목적은 **DDL 문법이 아니라** 두 가지다.
① 생성 열 + `UNIQUE` 가 의도대로 막는가 ② 생성 열 테이블에 `INSERT ... SELECT ... ON DUPLICATE KEY UPDATE` 가 도는가

### 1-1. 마이그레이션 실행 (dev)

`gymboxx-lib` 의 `feature/tech-997/exercise-effect-split` 브랜치에서 순서대로 실행한다.

```
src/sqlv4/V4_30_0__exercise_effect.sql
src/sqlv4/V4_30_0__exercise_recommend_tag.sql
src/sqlv4/V4_30_0__exercise_function_split.sql   ← §1~§4 까지. §5 는 점검 쿼리(주석), §6 은 실행하지 않는다
```

### 1-2. 제약 검증

`TECH-997-제약검증.claude.sql` 을 돌린다. 확인 5가지:

| # | 확인 | 성공 기준 |
|---|---|---|
| 1 | 생성 열이 `status` 를 따라가는가 | ACTIVE→`1` · INACTIVE→`NULL` |
| 2 | ACTIVE 중복 차단 | 🔴 **`ERROR 1062 Duplicate entry` 가 나야 성공** |
| 3 | INACTIVE 이력 여러 개 허용 | 에러 없이 2행 들어감 |
| 4 | 효과 축에 `FAT_LOSS` 저장 시도 | 🔴 **거부되어야 함** (`sql_mode` 에 `STRICT_TRANS_TABLES` 필요) |
| 5 | 재실행 안전성 | §2~§4 재실행 후 행수 동일 |

**이관 누락 검증은 반드시 0행**이어야 한다 (스크립트에 포함).

⚠️ dev 행수는 운영(288/24)과 다르게 나오는 것이 **정상**이다. dev 는 부위 매핑이 운영과 33종 차이난다.
규칙의 정확성은 이미 운영 SELECT 로 확인했다 (253 / 28 / 225).

### 1-3. 추천 결과 동등성 (선택, 권장)

이관 **전후** 추천 API 를 같은 입력으로 호출해 결과를 비교한다. 절대값이 아니라 상대 비교라 dev 데이터로 충분하다.
※ app-server 를 lib 신버전으로 띄운 상태여야 한다 → Phase 2 이후에 하는 것이 편하다.

### Phase 1 롤백

```sql
DROP TABLE exercise_effect;
DROP TABLE exercise_recommend_tag;
DROP TABLE exercise_function_backup_tech997;
```

---

## Phase 2 — lib 프리릴리스로 app-server 검증 (권장)

app-server 는 `package-lock.json` 이 갱신되어야 CI 가 통과한다. 정식 4.30.0 전에 프리릴리스로 먼저 맞춘다.
(레포에 `4.29.0-dev.1~4` 선례가 있다)

```sh
cd /Users/swkim/workspace/supplies/gymboxx-lib
git checkout feature/tech-997/exercise-effect-split
git tag 4.30.0-dev.1
git push origin 4.30.0-dev.1        # → GitHub Actions 가 publish
```

publish 완료 후:

```sh
cd /Users/swkim/workspace/supplies/gymboxx-app-server
git checkout feature/tech-997/exercise-effect-split
npm i @suppliesfitness/gymboxx-lib@4.30.0-dev.1   # package.json + lock 동시 갱신
npx tsc --noEmit -p tsconfig.json
npx jest src/modules/exercise-recommendation
git add package.json package-lock.json && git commit -m "chore(deps): gymboxx-lib 4.30.0-dev.1" && git push
```

- [ ] app-server CI 통과 확인
- [ ] `filter.spec.ts` 실행 — dev DB 접속 정보가 있는 환경에서. Phase 1 을 마쳐야 테이블이 있다

---

## Phase 3 — lib 머지 & 4.30.0 publish

- [ ] PR [#260](https://github.com/suppliesfitness/gymboxx-lib/pull/260) **Ready for review** 전환 → 리뷰 → **머지** (base: `main`)
- [ ] ⚠️ lib PR [#263](https://github.com/suppliesfitness/gymboxx-lib/pull/263) (TECH-998) 이 #260 을 base 로 스택되어 있다. #260 머지 시 base 가 `main` 으로 자동 전환된다 — TECH-998 담당자에게 공유
- [ ] 정식 태그 push

```sh
cd /Users/swkim/workspace/supplies/gymboxx-lib
git checkout main && git pull
git tag 4.30.0
git push origin 4.30.0             # → Actions 가 npm publish + 버전 커밋 push
```

- [ ] GitHub Packages 에서 `@suppliesfitness/gymboxx-lib@4.30.0` 확인

**이 단계는 DB 에 영향이 없다.** 다른 서버가 4.30.0 을 받아도 새 엔티티를 쿼리하는 코드가 없어 안전하다.

---

## Phase 4 — 운영 마이그레이션 🔴

### 4-1. 트랜잭션 리허설 (강력 권장)

운영 데이터 그대로 실제 INSERT 를 돌려 행수를 확인한 뒤 되돌린다.

```sql
START TRANSACTION;
  -- V4_30_0__exercise_function_split.sql §1~§4 실행
  --   ※ DDL(CREATE TABLE)은 암묵적 커밋이 일어나 롤백되지 않는다.
  --      테이블은 미리 만들고, 이 리허설에서는 §1~§4(INSERT)만 감싼다.
  SELECT COUNT(*) FROM exercise_effect;         -- 기대 288
  SELECT COUNT(*) FROM exercise_recommend_tag;  -- 기대 24
  SELECT COUNT(*) FROM exercise_effect WHERE effect_tag='STRENGTH';  -- 기대 225
ROLLBACK;
```

- [ ] 288 / 24 / 225 확인

### 4-2. 본실행

```
V4_30_0__exercise_effect.sql
V4_30_0__exercise_recommend_tag.sql
V4_30_0__exercise_function_split.sql   §1~§4
```

- [ ] §5 점검 쿼리 실행 — **이관 누락 0행** · 행수 288 / 24
- [ ] `exercise_function` 87행 **그대로**인지 확인 (건드리지 않아야 정상)
- [ ] 백업 테이블 `exercise_function_backup_tech997` 87행 확인

### Phase 4 롤백

app-server 배포 **전**이면 안전하다.

```sql
DROP TABLE exercise_effect;
DROP TABLE exercise_recommend_tag;
DROP TABLE exercise_function_backup_tech997;
```

---

## Phase 5 — app-server 머지 & 배포

- [ ] `package.json` 이 `4.30.0` 인지 확인 (Phase 2 에서 `-dev.1` 로 두었다면 정식으로 올린다)

```sh
cd /Users/swkim/workspace/supplies/gymboxx-app-server
npm i @suppliesfitness/gymboxx-lib@4.30.0
git add package.json package-lock.json && git commit -m "chore(deps): gymboxx-lib 4.30.0" && git push
```

- [ ] PR [#705](https://github.com/suppliesfitness/gymboxx-app-server/pull/705) Ready → 리뷰 → 머지 (base: `develop`)
- [ ] **`main` 용 PR 은 만들지 않는다** — `develop` 머지는 테스트 배포다. `main` 반영은 별도 지시가 있을 때 진행한다
- [ ] CodeBuild 빌드 + ECR push 확인
- [ ] **ArgoCD 동기화** — 배포는 GitOps 전담이다 (buildspec 에서 `kubectl apply` 제거됨). 이미지 태그 갱신 후 sync

### Phase 5 롤백

app-server 를 이전 버전으로 롤백한다. **신설 테이블은 그대로 둬도 무해하다** — 구버전은 읽지 않는다.

---

## Phase 6 — 배포 후 확인

- [ ] 추천 API `POST /exercise-recommendation` 정상 응답
- [ ] `general_routine` · `functional_routine` 이 **비어 있지 않은지** — 기능성 판정에서 `STRENGTH` 제외가 동작하는지 보는 지표다
- [ ] 응답 `specific` 필드에 `STRENGTH` 가 새로 나타난다. **클라이언트가 이 값을 화면에 노출한다면 사전 공유 필요** (Phase 0 원 설계자 확인 항목)
- [ ] 에러 로그에 `exercise_effect` · `exercise_recommend_tag` 관련 쿼리 실패 없는지

---

## 후속 (이번 배포 범위 밖)

### §6 검수 반영분 — 트레이너·기획 회신 후

별도 마이그레이션으로 분리해 실행한다. 대기 중인 결정 4건:

- [ ] `is_primary` 29종 지정
- [ ] **겸함 28종 주 효과 판정** — §4 백필에서 제외한 종목
- [ ] 효과 축 0개 **7종**(전부 `STRETCHING` 전용) 처리 방침 — `MOBILITY` 를 줄지
- [ ] `PLYOMETRIC` 부여 대상 지정
- [ ] "유산소 주 효과" 정의를 "부위 라벨 CARDIO 13종 기준" 으로 문장 확정

### `exercise_function` 제거 — 앱 코드 참조 0건 확인 후

- [ ] 운영에서 신설 두 테이블로 읽기 경로가 완전히 옮겨간 것 확인
- [ ] `DROP TABLE exercise_function` — **백업 테이블은 유지**

---

## 전체 순서 요약

```
Phase 1  dev 검증 (DDL + §1~§4 + 제약 5가지)
   ↓
Phase 2  lib 4.30.0-dev.1 프리릴리스 → app-server package-lock 갱신 · CI 통과   [권장]
   ↓
Phase 3  lib PR #260 머지 → 4.30.0 태그 push → publish
   ↓
Phase 4  🔴 운영 마이그레이션 (트랜잭션 리허설 → 본실행)   ← app-server 배포보다 먼저
   ↓
Phase 5  app-server PR #705 머지 → 빌드 → ArgoCD 배포
   ↓
Phase 6  배포 후 확인
   ↓
(후속)   §6 검수 반영분  →  exercise_function DROP
```

## 알려진 리스크

| 리스크 | 대응 |
|---|---|
| 생성 열 + `UNIQUE` 조합이 MySQL 에서 의도대로 안 될 가능성 | Phase 1 에서 검증. 실패 시 부분 유니크를 트리거나 앱 레벨 검증으로 대체 |
| `INSERT ... SELECT ... ON DUPLICATE KEY UPDATE` 가 생성 열 테이블에서 실패 | Phase 1 에서 검증. 실패 시 `INSERT IGNORE` + 사전 `DELETE` 로 변경 |
| `sql_mode` 가 느슨해 enum 위반이 경고로 넘어감 | Phase 1 (4)번에서 `@@sql_mode` 확인 |
| 마이그레이션 없이 app-server 가 먼저 배포됨 | **Phase 4 → 5 순서 엄수.** 역순이면 추천 API 500 |
| 클라이언트가 `specific` 값을 그대로 노출 | Phase 6 에서 확인 · 사전 공유 |
| dev 데이터가 운영과 달라 dev 검증이 운영을 대변하지 못함 | 규칙 정확성은 운영 SELECT 로 이미 확인 · Phase 4-1 리허설로 보강 |
| ~~dev 와 운영의 스키마가 어긋남~~ | ✅ **해소** — 운동 도메인 7개 테이블 `sig` 일치 확인(2026-08-31) · MySQL 8.0.45 동일 |
