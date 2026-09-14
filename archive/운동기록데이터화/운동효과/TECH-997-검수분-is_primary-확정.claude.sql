-- TECH-997 §6-가/다 반영: 검수 대상 28종의 주 효과(is_primary) 확정
--
-- 선행: V4_30_0__exercise_function_split.sql §1~§5
--       TECH-997-is_primary-자동확정.claude.sql        (자동 235종)
--       TECH-997-폼롤링-MOBILITY-부여.claude.sql        (폼롤링 7종)
--       PLYOMETRIC 부여 (135 버피 · 233 점핑잭 · 161 스플릿 점프 투 박스) — 실행 완료
--
-- 이 파일로 "효과 행은 있는데 주 효과가 없는" 종목이 0이 된다.
--
-- ══════════════════════════════════════════════════════════════════════════
-- 판정 근거 — 트레이너 회신 대신 NASM / ACSM 공식 분류 체계를 기준으로 확정했다.
--
--   ① 런지 · 스쿼트 · 푸시업류 → ENDURANCE
--      ACSM 은 런지를 muscular strength / endurance 저항운동으로 분류하고 balance 는
--      부수 효과로 본다. ACSM CPT 시험 콘텐츠도 standing lunge → walking lunge →
--      walking lunge with resistance 진행을 근력·근지구력 프로그램으로 제시한다.
--
--   ② 플랭크 · 레그레이즈 등 등척성 코어 → BALANCE
--      NASM 은 플랭크를 core stabilization 종목으로 분류하며, 이 단계(Stabilization
--      Endurance)를 balance 훈련과 같은 범주에 둔다. ACE 도 코어 안정성을 정적·동적
--      균형의 전제로 명시한다.
--
--   ③ 한 발 지지 · 불안정면(보수볼) → BALANCE
--      NASM 균형 훈련 진행 체계가 양발 안정면 → 한발 안정면 → 양발 불안정면 →
--      한발 불안정면 순이고, BOSU 를 대표적 불안정면 도구로 지정한다.
--      정의상 한 발 동작과 보수볼 종목은 균형 훈련이다.
--
--   ④ 위 3원칙에 걸리지 않는 4종(56 · 126 · 133 · 240)은 공식 근거가 아니라
--      "지지된 자세 = 균형 요구 없음 → 가동성" 이라는 운영 판단으로 확정했다.
--      🔴 트레이너 회신이 오면 이 4종을 우선 재검토한다.
--
--   출처: NASM Exercise Library (Plank) · NASM OPT Stabilization Endurance ·
--         ACE "Core Exercises to Improve Balance" · ACSM CPT Exam Content Outline
-- ══════════════════════════════════════════════════════════════════════════
--
-- ⚠️ status 조건을 걸지 않는다 — 241(머신 리버스 하이퍼 익스텐션)은 운동 자체가
--    INACTIVE 라 효과 행도 INACTIVE 다. 지금 계산에 쓰이지는 않지만, 나중에 다시
--    ACTIVE 로 되살릴 때 주 효과가 비어 있는 상태로 돌아오지 않도록 같이 채운다.

-- ── ① ENDURANCE 를 주 효과로 (11종) ──────────────────────────────────────
--    5 덤벨 런지 · 50 마운틴 클라이머 · 53 맨몸 백 런지 · 54 맨몸 런지
--    58 맨몸 풀 스쿼트 · 145 스미스 런지 · 155 스쿼트 · 170 워킹 런지
--    174 인클라인 푸시업 · 215 푸시업(무릎) · 260 덤벨 스텝 업
update exercise_effect
   set is_primary = 1
 where effect_tag = 'ENDURANCE'
   and exercise_id in (5, 50, 53, 54, 58, 145, 155, 170, 174, 215, 260);

-- ── ② · ③ BALANCE 를 주 효과로 (8종) ────────────────────────────────────
--    125 박스 원 레그 런지 · 137 벤치 스플릿 스쿼트 · 141 사이드 원 레그 스쿼트  (③ 한발)
--    216 푸시업(보수 볼)                                                    (③ 불안정면)
--    178 캡틴스 체어 레그 레이즈 · 220 플랭크 · 221 플랭크 레그 리프트
--    223 행잉 레그 레이즈                                                   (② 등척성 코어)
update exercise_effect
   set is_primary = 1
 where effect_tag = 'BALANCE'
   and exercise_id in (125, 137, 141, 178, 216, 220, 221, 223);

-- ── ④ MOBILITY 를 주 효과로 (8종) ───────────────────────────────────────
--    76 머신 리버스 플라이 · 185 케이블 리버스 플라이 · 241 머신 리버스 하이퍼 익스텐션
--    245 머신 백 익스텐션                                          (태그가 MOBILITY 하나뿐)
--    56 맨몸 스쿼트 월 서포트 · 126 백 익스텐션 · 133 밴드 페이스 풀
--    240 머신 토르소 로테이션                                      (🔴 운영 판단 · 재검토 대상)
update exercise_effect
   set is_primary = 1
 where effect_tag = 'MOBILITY'
   and exercise_id in (56, 76, 126, 133, 185, 240, 241, 245);

-- ── STRENGTH 를 주 효과로 (1종) ─────────────────────────────────────────
--    81 머신 앱도미널 크런치 — 머신 지지라 균형 요구가 없다. STRENGTH,BALANCE 중 STRENGTH.
update exercise_effect
   set is_primary = 1
 where effect_tag = 'STRENGTH'
   and exercise_id = 81;

-- ══════════════════════════════════════════════════════════════════════════
-- 점검 — 실행 후 아래 두 쿼리로 확인한다.
--
-- (1) 주 효과가 없는 종목 — 0 행이어야 한다.
-- select ee.exercise_id, e.name, group_concat(ee.effect_tag) tags
--   from exercise_effect ee
--   join exercise e on e.id = ee.exercise_id
--  group by ee.exercise_id, e.name
-- having sum(ee.is_primary) = 0;
--
-- (2) 주 효과가 2개 이상인 종목 — 0 행이어야 한다 (한 종목에 주 효과는 1개).
-- select exercise_id, count(*) c from exercise_effect
--  where is_primary = 1 group by exercise_id having c > 1;
-- ══════════════════════════════════════════════════════════════════════════
