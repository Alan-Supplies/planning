-- TECH-997 제약 검증 — dev 에서 V4_30_0 DDL + §1~§4 실행 후 돌린다
--
-- 확인 대상 5가지
--   (1) 생성 열 active_key 가 status 를 따라 채워지는가
--   (2) ACTIVE 행 중복이 UNIQUE 로 막히는가          ← 이슈 「효과 축 조건이 DB 제약으로 강제」
--   (3) INACTIVE 이력 행은 여러 개 허용되는가
--   (4) 효과 축 테이블에 감량·회복을 넣으면 거부되는가  ← 이슈 「저장 단계에서 거부」
--   (5) 이관 SQL 재실행이 안전한가 (ON DUPLICATE KEY UPDATE)
--
-- 롤백: DROP TABLE exercise_effect, exercise_recommend_tag, exercise_function_backup_tech997;

-- ─────────────────────────────────────────────
-- 0) 이관 결과 행수 — dev 기준이라 운영(288/24)과 다르게 나오는 것이 정상
-- ─────────────────────────────────────────────
select 'exercise_effect' t, count(*) c from exercise_effect
union all select 'exercise_recommend_tag', count(*) from exercise_recommend_tag
union all select 'backup', count(*) from exercise_function_backup_tech997
union all select 'exercise_function(원본, 그대로여야 함)', count(*) from exercise_function;

-- 이관 누락 검증 — 반드시 0 행
select ef.exercise_id, ef.functional_tag
from exercise_function ef
where not exists (select 1 from exercise_effect ee
                  where ee.exercise_id = ef.exercise_id and ee.effect_tag = ef.functional_tag)
  and not exists (select 1 from exercise_recommend_tag ert
                  where ert.exercise_id = ef.exercise_id and ert.tag = ef.functional_tag);

-- ─────────────────────────────────────────────
-- (1) 생성 열이 status 를 따라가는가 — ACTIVE 는 1, INACTIVE 는 NULL 이어야 한다
-- ─────────────────────────────────────────────
select status, active_key, count(*) c from exercise_effect group by status, active_key;

-- ─────────────────────────────────────────────
-- (2) ACTIVE 중복 차단 — 🔴 Duplicate entry 에러가 나야 성공이다
--     아래 한 줄만 실행해서 에러를 확인한다
-- ─────────────────────────────────────────────
-- insert into exercise_effect (exercise_id, effect_tag, is_primary, status)
-- select exercise_id, effect_tag, 0, 'ACTIVE' from exercise_effect where status='ACTIVE' limit 1;
--   기대: ERROR 1062 Duplicate entry ... for key 'exercise_effect_active_uk'

-- ─────────────────────────────────────────────
-- (3) INACTIVE 이력 행은 여러 개 허용 — 에러 없이 2행이 들어가야 한다
-- ─────────────────────────────────────────────
-- set @eid = (select exercise_id from exercise_effect where status='ACTIVE' limit 1);
-- set @tag = (select effect_tag  from exercise_effect where status='ACTIVE' limit 1);
-- insert into exercise_effect (exercise_id, effect_tag, is_primary, status) values (@eid, @tag, 0, 'INACTIVE');
-- insert into exercise_effect (exercise_id, effect_tag, is_primary, status) values (@eid, @tag, 0, 'INACTIVE');
--   기대: 둘 다 성공 (active_key 가 NULL 이라 UNIQUE 에 걸리지 않는다)
--   확인: select * from exercise_effect where exercise_id=@eid and effect_tag=@tag;
--   정리: delete from exercise_effect where exercise_id=@eid and effect_tag=@tag and status='INACTIVE';

-- ─────────────────────────────────────────────
-- (4) 효과 축에 감량·회복 저장 시도 — 🔴 거부되어야 한다
-- ─────────────────────────────────────────────
-- insert into exercise_effect (exercise_id, effect_tag, is_primary, status)
-- values ((select id from exercise limit 1), 'FAT_LOSS', 0, 'ACTIVE');
--   기대: ERROR 1265 Data truncated for column 'effect_tag'
--   (sql_mode 가 느슨하면 경고 후 '' 저장될 수 있다 — 그 경우 STRICT_TRANS_TABLES 확인 필요)
select @@sql_mode;

-- ─────────────────────────────────────────────
-- (5) 재실행 안전성 — §2 · §3 · §4 를 한 번 더 실행한 뒤 행수가 그대로인지 본다
--     ON DUPLICATE KEY UPDATE 로 updated_at 만 갱신되고 행이 늘지 않아야 한다
-- ─────────────────────────────────────────────
-- (§2~§4 재실행 후)
-- select 'exercise_effect' t, count(*) c from exercise_effect
-- union all select 'exercise_recommend_tag', count(*) from exercise_recommend_tag;
--   기대: 0) 단계와 같은 행수

-- ─────────────────────────────────────────────
-- 참고: 백필 규칙이 dev 에서 몇 종을 잡는지 (운영은 253/28/225)
-- ─────────────────────────────────────────────
select 'A) 근육 부위 라벨 보유' l, count(distinct ebp.exercise_id) c
from exercise_body_part ebp join body_part bp on bp.id = ebp.body_part_id
where bp.part in ('CHEST','BACK','SHOULDER','ARM','LEG','CORE')
union all
select 'B) 지구력·이완 겸함 (백필 제외)', count(distinct ebp.exercise_id)
from exercise_body_part ebp join body_part bp on bp.id = ebp.body_part_id
where bp.part in ('CHEST','BACK','SHOULDER','ARM','LEG','CORE')
  and ebp.exercise_id in (select exercise_id from exercise_function
                          where functional_tag in ('ENDURANCE','MOBILITY'))
union all
select 'C) STRENGTH 백필 = A - B', count(*) from exercise_effect where effect_tag='STRENGTH';
