-- =====================================================================
-- 이지프렙 셀버스 메뉴키 등록 (7/13 제이 요청, 14건)
-- 출처 시트: [메뉴] 탭 471행~
--
-- kds_dev 사전 확인 결과 (2026-07-13):
--   name의 공백을 제거한 값 + hall_price 기준: 기존 10건 / 추가 대상 4건
--   추가 대상: 치킨 플레이트 샐러드/치킨 콥 플레이트의 콤보·단품
--
-- 교정 반영:
--   A. 더블치킨 고기타입: FRIED_CHICKEN -> FRIED_CHICKEN_DOUBLE
--   B. 단품 unique_name의 잘못된 "콤보" 접미사 제거
-- food_id: 동일 기본 메뉴의 기존 food_id로 매칭
-- 가정: delivery_price=NULL(홀 전용), is_pos_key=0
--
-- 안전장치: 공백을 제거한 name + hall_price가 같은 ACTIVE 행이 있으면 건너뜀
-- ⚠️ 읽기 전용 계정으로는 실행 불가 — write 권한 계정으로 실행하세요.
-- =====================================================================

START TRANSACTION;

-- 등록 전 상태 확인 ----------------------------------------------------
SELECT
  requested.no,
  requested.name,
  requested.unique_name,
  requested.hall_price,
  existing.id AS existing_menu_id,
  CASE WHEN existing.id IS NULL THEN 'TO_INSERT' ELSE 'ALREADY_EXISTS' END AS result
FROM (
            SELECT  1 AS no, 2 AS food_id, '(EVENT) 치킨 샐러드파스타 콤보' AS name, '치킨 샐러드파스타 콤보' AS unique_name, 'NOODLE' AS type, 'GRILLED_CHICKEN' AS meat_type, 8900 AS hall_price
  UNION ALL SELECT  2, 8,   '(EVENT) 치킨 로제샐러드파스타 콤보', '치킨 로제샐러드파스타 콤보', 'NOODLE', 'GRILLED_CHICKEN',      9900
  UNION ALL SELECT  3, 24,  '(EVENT) 치킨 데리야끼 덮밥 콤보',    '치킨 데리야끼 덮밥 콤보',    'RICE',   'FRIED_CHICKEN',        8900
  UNION ALL SELECT  4, 42,  '(EVENT) 치킨 커리 덮밥 콤보',       '치킨 커리 덮밥 콤보',       'RICE',   'FRIED_CHICKEN',        9900
  UNION ALL SELECT  5, 30,  '(EVENT) 더블치킨 데리야끼 덮밥 콤보', '더블치킨 데리야끼 덮밥 콤보', 'RICE',   'FRIED_CHICKEN_DOUBLE', 9900
  UNION ALL SELECT  6, 16,  '(EVENT) 치킨 플레이트 샐러드 콤보',  '치킨 플레이트 샐러드 콤보',  'PLATE',  'GRILLED_CHICKEN',      6900
  UNION ALL SELECT  7, 107, '(EVENT) 치킨 콥 플레이트 콤보',     '치킨 콥 플레이트 콤보',     'PLATE',  'GRILLED_CHICKEN',      6900
  UNION ALL SELECT  8, 1,   '(EVENT) 치킨 샐러드파스타',         '치킨 샐러드파스타',         'NOODLE', 'GRILLED_CHICKEN',      7900
  UNION ALL SELECT  9, 7,   '(EVENT) 치킨 로제샐러드파스타',      '치킨 로제샐러드파스타',      'NOODLE', 'GRILLED_CHICKEN',      8900
  UNION ALL SELECT 10, 23,  '(EVENT) 치킨 데리야끼 덮밥',        '치킨 데리야끼 덮밥',        'RICE',   'FRIED_CHICKEN',        7900
  UNION ALL SELECT 11, 41,  '(EVENT) 치킨 커리 덮밥',           '치킨 커리 덮밥',           'RICE',   'FRIED_CHICKEN',        8900
  UNION ALL SELECT 12, 29,  '(EVENT) 더블치킨 데리야끼 덮밥',     '더블치킨 데리야끼 덮밥',     'RICE',   'FRIED_CHICKEN_DOUBLE', 8900
  UNION ALL SELECT 13, 15,  '(EVENT) 치킨 플레이트 샐러드',      '치킨 플레이트 샐러드',      'PLATE',  'GRILLED_CHICKEN',      5900
  UNION ALL SELECT 14, 106, '(EVENT) 치킨 콥 플레이트',         '치킨 콥 플레이트',         'PLATE',  'GRILLED_CHICKEN',      5900
) requested
LEFT JOIN `menu` existing
  ON REPLACE(existing.name, ' ', '') = REPLACE(requested.name, ' ', '')
 AND existing.hall_price = requested.hall_price
 AND existing.status = 'ACTIVE'
ORDER BY requested.no;

-- 미등록 행만 등록 -----------------------------------------------------
INSERT INTO `menu`
  (`food_id`, `name`, `unique_name`, `type`, `meat_type`, `hall_price`, `delivery_price`, `is_pos_key`, `status`)
SELECT
  requested.food_id,
  requested.name,
  requested.unique_name,
  requested.type,
  requested.meat_type,
  requested.hall_price,
  NULL,
  0,
  'ACTIVE'
FROM (
            SELECT 2 AS food_id, '(EVENT) 치킨 샐러드파스타 콤보' AS name, '치킨 샐러드파스타 콤보' AS unique_name, 'NOODLE' AS type, 'GRILLED_CHICKEN' AS meat_type, 8900 AS hall_price
  UNION ALL SELECT 8,   '(EVENT) 치킨 로제샐러드파스타 콤보', '치킨 로제샐러드파스타 콤보', 'NOODLE', 'GRILLED_CHICKEN',      9900
  UNION ALL SELECT 24,  '(EVENT) 치킨 데리야끼 덮밥 콤보',    '치킨 데리야끼 덮밥 콤보',    'RICE',   'FRIED_CHICKEN',        8900
  UNION ALL SELECT 42,  '(EVENT) 치킨 커리 덮밥 콤보',       '치킨 커리 덮밥 콤보',       'RICE',   'FRIED_CHICKEN',        9900
  UNION ALL SELECT 30,  '(EVENT) 더블치킨 데리야끼 덮밥 콤보', '더블치킨 데리야끼 덮밥 콤보', 'RICE',   'FRIED_CHICKEN_DOUBLE', 9900
  UNION ALL SELECT 16,  '(EVENT) 치킨 플레이트 샐러드 콤보',  '치킨 플레이트 샐러드 콤보',  'PLATE',  'GRILLED_CHICKEN',      6900
  UNION ALL SELECT 107, '(EVENT) 치킨 콥 플레이트 콤보',     '치킨 콥 플레이트 콤보',     'PLATE',  'GRILLED_CHICKEN',      6900
  UNION ALL SELECT 1,   '(EVENT) 치킨 샐러드파스타',         '치킨 샐러드파스타',         'NOODLE', 'GRILLED_CHICKEN',      7900
  UNION ALL SELECT 7,   '(EVENT) 치킨 로제샐러드파스타',      '치킨 로제샐러드파스타',      'NOODLE', 'GRILLED_CHICKEN',      8900
  UNION ALL SELECT 23,  '(EVENT) 치킨 데리야끼 덮밥',        '치킨 데리야끼 덮밥',        'RICE',   'FRIED_CHICKEN',        7900
  UNION ALL SELECT 41,  '(EVENT) 치킨 커리 덮밥',           '치킨 커리 덮밥',           'RICE',   'FRIED_CHICKEN',        8900
  UNION ALL SELECT 29,  '(EVENT) 더블치킨 데리야끼 덮밥',     '더블치킨 데리야끼 덮밥',     'RICE',   'FRIED_CHICKEN_DOUBLE', 8900
  UNION ALL SELECT 15,  '(EVENT) 치킨 플레이트 샐러드',      '치킨 플레이트 샐러드',      'PLATE',  'GRILLED_CHICKEN',      5900
  UNION ALL SELECT 106, '(EVENT) 치킨 콥 플레이트',         '치킨 콥 플레이트',         'PLATE',  'GRILLED_CHICKEN',      5900
) requested
WHERE NOT EXISTS (
  SELECT 1
  FROM `menu` existing
  WHERE REPLACE(existing.name, ' ', '') = REPLACE(requested.name, ' ', '')
    AND existing.hall_price = requested.hall_price
    AND existing.status = 'ACTIVE'
);

SELECT ROW_COUNT() AS inserted_count;

-- 등록 후 14건 확인 ----------------------------------------------------
SELECT
  id,
  food_id,
  name,
  unique_name,
  type,
  meat_type,
  hall_price,
  delivery_price,
  is_pos_key,
  status
FROM `menu`
WHERE status = 'ACTIVE'
  AND (
       (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 샐러드파스타 콤보', ' ', '') AND hall_price = 8900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 로제샐러드파스타 콤보', ' ', '') AND hall_price = 9900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 데리야끼 덮밥 콤보', ' ', '') AND hall_price = 8900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 커리 덮밥 콤보', ' ', '') AND hall_price = 9900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 더블치킨 데리야끼 덮밥 콤보', ' ', '') AND hall_price = 9900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 플레이트 샐러드 콤보', ' ', '') AND hall_price = 6900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 콥 플레이트 콤보', ' ', '') AND hall_price = 6900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 샐러드파스타', ' ', '') AND hall_price = 7900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 로제샐러드파스타', ' ', '') AND hall_price = 8900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 데리야끼 덮밥', ' ', '') AND hall_price = 7900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 커리 덮밥', ' ', '') AND hall_price = 8900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 더블치킨 데리야끼 덮밥', ' ', '') AND hall_price = 8900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 플레이트 샐러드', ' ', '') AND hall_price = 5900)
    OR (REPLACE(name, ' ', '') = REPLACE('(EVENT) 치킨 콥 플레이트', ' ', '') AND hall_price = 5900)
  )
ORDER BY id;

-- 확인 후 COMMIT / 이상하면 ROLLBACK
-- COMMIT;
