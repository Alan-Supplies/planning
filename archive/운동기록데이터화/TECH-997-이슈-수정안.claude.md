# TECH-997 Linear 이슈 수정안

> 작성 2026-08-31 · Linear MCP 토큰 만료로 직접 수정하지 못해 남긴다.
> 인증되면 이 내용으로 이슈 본문을 교체하면 된다. 아래 `---` 사이가 붙여넣을 본문이다.
>
> **원본 대비 바뀐 곳** (5군데, 나머지는 원문 그대로)
> 1. 「하는 일」 — `exercise_effect` 예상 290행 → **288행** (63 이관 + 225 백필, 운영 실측)
> 2. 「하는 일」 — **근력 백필 규칙** 한 줄 추가 (253종 − 겸함 28종 = 225종)
> 3. 「신규 테이블 두 개를 어떻게 나누는가」 — **추천 경로가 두 축을 모두 읽는다**는 비대칭 추가
> 4. 「착수 전 확인」 — **겸함 28종 주 효과 판정** 항목 추가 · 전수조사 결과 기입 · 7종 정체 명시
> 5. 「진행 상황」 절 신설 — PR 링크와 남은 작업

---

## 대상

`exercise_function`(87행) → `exercise_effect` · `exercise_recommend_tag` 두 테이블로 분리

## 하는 일

* `exercise_effect` **신설** — `effect_tag enum('STRENGTH','ENDURANCE','MOBILITY','BALANCE','PLYOMETRIC')` · `is_primary` · `status` · 생성 열 `active_key` · `UNIQUE(exercise_id, effect_tag, active_key)` · **288행**(이관 63 + 근력 백필 225, 운영 실측)
* `exercise_recommend_tag` **신설** — `tag enum('FAT_LOSS','RECOVERY')` · 24행
* **근력 백필 규칙** — 근육 부위 라벨(`CHEST`·`BACK`·`SHOULDER`·`ARM`·`LEG`·`CORE`) 보유 **253종** 중 지구력·이완을 겸한 **28종을 제외한 225종**에 `STRENGTH` 부여 · 겸함 28종은 주 효과 판정 후로 미룬다(주 효과 판정 없이 근력을 붙이면 유산소 시간이 부풀려진다) · 균형 `BALANCE` 는 제외 조건이 아니다
* 순발력 `PLYOMETRIC` 은 열거형에만 열어두고 행 삽입은 후순위 · 주 효과 구분 · 상태 · 시각 컬럼 신설
* 이관 후 `exercise_function` 제거는 앱 코드 전환 확인 후 (백업 테이블 유지)

## 신규 테이블 두 개를 어떻게 나누는가

계산 경로(효과 축)와 추천 경로(태그)를 분리한다. 추천용 태그는 목표 달성률·랭킹·리포트 계산 경로에서 읽지 않는다. 두 테이블의 구조 차이는 `is_primary` 유무 하나 — 감량·회복에는 주 효과/부가 효과 개념이 없다.

**배타는 계산 경로에만 성립하는 단방향이다.** 추천 경로는 두 테이블을 **모두** 읽는다 — 목적별 태그 매핑 6개 중 4개(`STRENGTH_GAIN`·`ENDURANCE_GAIN`·`POSTURE_CORRECTION`·`ATHLETIC_PERFORMANCE`)가 효과 축 태그만으로 판정되기 때문이다. 추천을 `exercise_recommend_tag` 만 읽게 바꾸면 그 4개 목적의 기능성 루틴이 빈 배열이 된다.

## 기대효과

근력 판정이 하나로 확정되고, 효과 축 조건이 DB 제약으로 강제된다.

## 착수 전 확인

* ~~**앱 코드 참조 지점 전수조사**~~ — **완료**. 참조는 app-server `exercise-recommendation` 모듈 한 곳뿐이었다(dao · 필터 · 스코어러 · 셀렉터 · 응답 DTO · 상수 · spec 3개). 다른 모듈·다른 레포에는 없다
* 트레이너 검수 회신: 효과 축 검수 + `is_primary` **29종**
* **겸함 28종 주 효과 판정** — 근력 백필에서 제외한 종목. 근력을 줄지, 지구력·이완을 주 효과로 둘지 (트레이너)
* 효과 축 0개 **7종** 처리 방침 결정 1건 (트레이너·기획) — 백필 규칙 적용 후 실측 결과 **전부 `STRETCHING` 전용 7종**으로 확정. `MOBILITY` 를 줄지가 쟁점
* "유산소 주 효과" 정의를 **"부위 라벨 CARDIO 13종 기준"** 으로 문장 1건 확정 — 운영 실측 CARDIO **전용** 13종과 일치 확인
* 회신 지연 시: "자동분"과 "검수 반영"으로 쪼개 전자를 먼저 배포

## 진행 상황

* lib PR **suppliesfitness/gymboxx-lib#260** (draft) — 스키마 신설 · 데이터 이관 SQL · 엔티티 · enum
* app-server PR **suppliesfitness/gymboxx-app-server#705** (draft) — 추천 파이프라인을 두 축 기준으로 전환
* 배포 순서: lib 4.30.0 publish → `V4_30_0` 마이그레이션 §1~§5(자동분) → app-server 배포 → §6 검수 반영분 → `exercise_function` DROP
* 남은 것: DDL 을 dev 에 실제 실행해 검증 · app-server `package-lock.json` 갱신(lib publish 후) · 검수 회신 4건

## 소요

**3영업일** — 8개 순위 중 유일하게 3일

## 근거

* `docs/운동기록데이터화/DB_구조_업그레이드_방안.md` §1 · §17-1 순위 1 · §17-2 가/나
* `docs/운동기록데이터화/느슨하게작성일정.md` 1번
* 구현 결정 기록: `docs/운동기록데이터화/TECH-997-효과축-추천태그-분리.claude.md`

---
