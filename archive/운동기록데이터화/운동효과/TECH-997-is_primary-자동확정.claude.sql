-- TECH-997 §6-가 (일부 선반영): is_primary 자동 확정분 235종
--
-- 실행 순서: V4_30_0__exercise_function_split.sql §1~§5 (자동분 이관·STRENGTH 백필) 실행 후.
-- exercise_effect 가 아직 없으면 이 파일은 아무 효과가 없다.
--
-- 운영 replica 실측 (2026-09-01, gymboxx-prod-replica-01) — 방안 문서 §01 수치와 전부 일치:
--   exercise_function 87행 (FAT_LOSS 14 · ENDURANCE 25 · MOBILITY 18 · BALANCE 20 · RECOVERY 10)
--   STRENGTH 백필: 자동 225종 / 검수 대상 28종
--   전체 273종 = 자동 235종 + 검수/보류 31종(28종 검수 목록 + id=81 + PLYOMETRIC 보류 2종) + 효과 축 0개 7종
--   is_primary 자동 대상 235종 = ACTIVE 199 + INACTIVE 36
--
-- ⚠️ 러ンブック 초안(V4_30_0__exercise_function_split.sql §6-가 주석)의 버그를 여기서 고쳤다.
--    초안은 "ACTIVE 효과 행 COUNT(*) = 1 이면 자동"이었는데, 이 조건은 28종 검수 목록 중
--    지금 태그가 1개뿐인 7종(id 50·76·174·185·215·241·245 — STRENGTH 부여 여부를 트레이너가
--    아직 안 정함)까지 같이 자동 승인해버린다. 태그 개수가 아니라 검수/보류 대상을
--    명시적으로 제외해야 한다.
update exercise_effect e
   set e.is_primary = 1
 where e.exercise_id not in (
   -- 28종 검수 목록 (STRENGTH 부여 여부 + 주 효과, 트레이너 판단 대기)
   5, 50, 53, 54, 56, 58, 76, 125, 126, 133, 137, 141, 145, 155, 161, 170,
   174, 178, 185, 215, 216, 220, 221, 223, 240, 241, 245, 260,
   -- STRENGTH 백필로 기존 BALANCE 와 겸하게 된 종목 (위 목록과 별도 판단 필요)
   81,
   -- PLYOMETRIC 보류 — 버피(135) · 점핑잭(233)
   135, 233
 );

-- 점검 — 실행 후 반드시 확인한다.
-- (1) 위 UPDATE 로 바뀐 행 수가 235 여야 한다 (MySQL 은 "값이 이미 1인 행"은 matched 로 잡지만
--     changed 로는 세지 않을 수 있다 — Rows matched 기준으로 확인).
-- (2) "효과 행이 있는데 주 효과가 없는 종목" 감사 쿼리 — 31종(28종 검수 + id=81 + 135·233)이 나와야 정상.
-- select ee.exercise_id, e.name, group_concat(ee.effect_tag) tags
--   from exercise_effect ee
--   join exercise e on e.id = ee.exercise_id
--  where ee.status = 'ACTIVE'
--  group by ee.exercise_id, e.name
-- having sum(ee.is_primary) = 0;
