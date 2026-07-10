-- =====================================================================
-- 이지프렙 셀버스 메뉴키 등록 (7/10 그린 요청, 14건)
-- 출처 시트: 이지프렙 메뉴키/옵션키 2026-04-23, [메뉴] 탭 457행~
-- 교정 반영:
--   A. 더블치킨 고기타입: FRIED_CHICKEN -> FRIED_CHICKEN_DOUBLE  (#5, #12)
--   B. 단품 unique_name의 "콤보" 접미사 제거                     (#10~#14)
-- food_id: 할인 접두사 뗀 동일 이름의 기존 메뉴 food_id로 매칭
--   #14 '치킨 콥 플레이트'(단품) food_id = 106 (지정)
-- 가정: delivery_price=NULL(홀 전용), is_pos_key=0
-- ⚠️ 읽기전용 계정으로는 실행 불가 — write 권한 계정으로 실행하세요.
-- =====================================================================

START TRANSACTION;

-- menu ----------------------------------------------------------------
INSERT INTO `menu`
  (`food_id`, `name`, `unique_name`, `type`, `meat_type`, `hall_price`, `delivery_price`, `is_pos_key`, `status`)
VALUES
  -- 콤보 7종
  ( 2,   '(2,000할인) 치킨 샐러드파스타 콤보',    '치킨 샐러드파스타 콤보',    'NOODLE', 'GRILLED_CHICKEN',        8900, NULL, 0, 'ACTIVE'),
  ( 8,   '(2,000할인) 치킨 로제샐러드파스타 콤보', '치킨 로제샐러드파스타 콤보', 'NOODLE', 'GRILLED_CHICKEN',        9900, NULL, 0, 'ACTIVE'),
  ( 24,  '(2,000할인) 치킨 데리야끼 덮밥 콤보',    '치킨 데리야끼 덮밥 콤보',    'RICE',   'FRIED_CHICKEN',          8900, NULL, 0, 'ACTIVE'),
  ( 42,  '(2,000할인) 치킨 커리 덮밥 콤보',       '치킨 커리 덮밥 콤보',       'RICE',   'FRIED_CHICKEN',          9900, NULL, 0, 'ACTIVE'),
  ( 30,  '(2,000할인) 더블치킨 데리야끼 덮밥 콤보', '더블치킨 데리야끼 덮밥 콤보', 'RICE',   'FRIED_CHICKEN_DOUBLE',   9900, NULL, 0, 'ACTIVE'),  -- A
  ( 15,  '(2,000할인) 치킨 플레이트 샐러드 콤보',  '치킨 플레이트 샐러드 콤보',  'PLATE',  'GRILLED_CHICKEN',        6900, NULL, 0, 'ACTIVE'),
  ( 107, '(2,000할인) 치킨 콥 플레이트 콤보',     '치킨 콥 플레이트 콤보',     'PLATE',  'GRILLED_CHICKEN',        6900, NULL, 0, 'ACTIVE'),
  -- 단품 7종
  ( 1,   '(2,000할인) 치킨 샐러드파스타',         '치킨 샐러드파스타',         'NOODLE', 'GRILLED_CHICKEN',        7900, NULL, 0, 'ACTIVE'),
  ( 7,   '(2,000할인) 치킨 로제샐러드파스타',      '치킨 로제샐러드파스타',      'NOODLE', 'GRILLED_CHICKEN',        8900, NULL, 0, 'ACTIVE'),
  ( 23,  '(2,000할인) 치킨 데리야끼 덮밥',        '치킨 데리야끼 덮밥',        'RICE',   'FRIED_CHICKEN',          7900, NULL, 0, 'ACTIVE'),  -- B
  ( 41,  '(2,000할인) 치킨 커리 덮밥',           '치킨 커리 덮밥',           'RICE',   'FRIED_CHICKEN',          8900, NULL, 0, 'ACTIVE'),  -- B
  ( 29,  '(2,000할인) 더블치킨 데리야끼 덮밥',     '더블치킨 데리야끼 덮밥',     'RICE',   'FRIED_CHICKEN_DOUBLE',   8900, NULL, 0, 'ACTIVE'),  -- A, B
  ( 15,  '(2,000할인) 치킨 플레이트 샐러드',      '치킨 플레이트 샐러드',      'PLATE',  'GRILLED_CHICKEN',        5900, NULL, 0, 'ACTIVE'),  -- B
  ( 106, '(2,000할인) 치킨 콥 플레이트',         '치킨 콥 플레이트',         'PLATE',  'GRILLED_CHICKEN',        5900, NULL, 0, 'ACTIVE');  -- B

-- 확인 후 COMMIT / 이상하면 ROLLBACK
-- COMMIT;
