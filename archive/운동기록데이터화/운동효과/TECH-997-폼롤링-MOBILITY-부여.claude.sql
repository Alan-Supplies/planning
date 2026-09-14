-- TECH-997 §6-라 결정 반영: 효과 축 0개로 남아있던 폼롤링류 7종에 MOBILITY 부여
--
-- 배경: §5(3) 점검에서 효과 축이 하나도 없는 ACTIVE 운동 7종이 확인됐다 (전부 STRETCHING 단독).
--   방안 문서 §6-라는 "STRETCHING 전용 7종에 MOBILITY를 부여할지, 축 없이 둘지가 쟁점"이라고
--   미결정으로 남겨뒀는데, 이번에 MOBILITY 부여로 확정했다.
--
-- 실행 순서: V4_30_0__exercise_function_split.sql §1~§5, TECH-997-is_primary-자동확정.claude.sql 이후.
--
-- 운영 replica 확인 (2026-09-01) — 7종 전부 ACTIVE, exercise_effect 행 0개:
--   3   대원근 폼 롤링
--   4   대퇴직근 폼 롤링
--   45  둔근 폼 롤링
--   139 비복근 폼 롤링
--   162 승모근 폼 롤링
--   169 외측광근 폼 롤링
--   226 회전근개 폼 롤링
--
-- is_primary=1 로 바로 넣는다 — 이 7종은 태그가 1개뿐이라(§4에서 STRENGTH 백필 대상도 아니었음:
-- 근육 부위 라벨이 없는 스트레칭 전용이라 애초에 STRENGTH 백필 조건에 안 걸린다) 주 효과 판정에
-- 모호함이 없다. 235종 자동확정과 같은 논리다.
insert into exercise_effect (exercise_id, effect_tag, is_primary, status)
select e.id, 'MOBILITY', 1, 'ACTIVE'
  from exercise e
 where e.id in (3, 4, 45, 139, 162, 169, 226)
on duplicate key update exercise_effect.updated_at = current_timestamp;

-- 점검 — 실행 후 7행이 전부 MOBILITY / is_primary=1 로 들어갔는지 확인한다.
-- select exercise_id, effect_tag, is_primary, status from exercise_effect
--  where exercise_id in (3, 4, 45, 139, 162, 169, 226);
