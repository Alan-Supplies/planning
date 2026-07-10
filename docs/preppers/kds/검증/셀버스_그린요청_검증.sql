-- =====================================================================
-- 검증 쿼리 — 셀버스 그린요청 14건 food_id 매칭 확인
-- =====================================================================

-- ① 삽입 전 검증 : 지정한 food_id가 "할인 접두사 뗀 동일 이름" 원본 메뉴와 일치하는지
--    (읽기 전용 계정으로 지금 실행 가능)
--    result: OK=일치 / MISMATCH=불일치 / BASE_NOT_FOUND=원본 이름 없음
--    ※ #14 치킨 콥 플레이트는 원본 food_id가 NULL이라 106을 별도 지정 → 의도된 MISMATCH
SELECT
  x.no,
  x.base_name,
  x.assigned_food_id,
  m.id       AS base_menu_id,
  m.food_id  AS base_food_id,
  CASE
    WHEN m.id IS NULL                       THEN 'BASE_NOT_FOUND'
    WHEN x.assigned_food_id <=> m.food_id   THEN 'OK'
    ELSE 'MISMATCH'
  END        AS result
FROM (
            SELECT  1 AS no, '치킨 샐러드파스타 콤보'      AS base_name,   2 AS assigned_food_id
  UNION ALL SELECT  2, '치킨 로제샐러드파스타 콤보',   8
  UNION ALL SELECT  3, '치킨 데리야끼 덮밥 콤보',      24
  UNION ALL SELECT  4, '치킨 커리 덮밥 콤보',         42
  UNION ALL SELECT  5, '더블치킨 데리야끼 덮밥 콤보',  30
  UNION ALL SELECT  6, '치킨 플레이트 샐러드 콤보',    15
  UNION ALL SELECT  7, '치킨 콥 플레이트 콤보',       107
  UNION ALL SELECT  8, '치킨 샐러드파스타',            1
  UNION ALL SELECT  9, '치킨 로제샐러드파스타',        7
  UNION ALL SELECT 10, '치킨 데리야끼 덮밥',          23
  UNION ALL SELECT 11, '치킨 커리 덮밥',             41
  UNION ALL SELECT 12, '더블치킨 데리야끼 덮밥',       29
  UNION ALL SELECT 13, '치킨 플레이트 샐러드',        15
  UNION ALL SELECT 14, '치킨 콥 플레이트',           106
) x
LEFT JOIN `menu` m ON m.`name` = x.base_name
ORDER BY x.no;


-- ② 삽입 후 검증 : 실제 등록된 (2,000할인) 행의 food_id가 원본과 일치하는지
--    (INSERT COMMIT 이후 실행)
SELECT
  d.id,
  d.name                                              AS inserted_name,
  d.food_id                                           AS inserted_food_id,
  TRIM(REPLACE(d.name, '(2,000할인)', ''))            AS base_name,
  b.food_id                                           AS base_food_id,
  CASE
    WHEN d.name LIKE '%치킨 콥 플레이트' AND d.name NOT LIKE '%콤보'
                                         THEN 'OK(수동지정 106)'
    WHEN d.food_id <=> b.food_id         THEN 'OK'
    ELSE 'CHECK'
  END                                                 AS result
FROM `menu` d
LEFT JOIN `menu` b ON b.`name` = TRIM(REPLACE(d.name, '(2,000할인)', ''))
WHERE d.name LIKE '(2,000할인)%'
ORDER BY d.id;
