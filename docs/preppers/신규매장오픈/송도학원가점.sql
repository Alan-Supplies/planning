-- 송도학원가점 관리자 접근 권한 추가
-- 근거: https://w1622455415-twy380170.slack.com/archives/C0A0H4MNS1W/p1784594452259019
-- 대상 매장: store.id = 42
-- 대상 직원: Green(13), Jessie(16), Sia(33), Jackie(73)
--
-- 안전을 위해 기본 상태에서는 마지막에 ROLLBACK한다.
-- 검증 결과가 맞을 때만 ROLLBACK을 주석 처리하고 COMMIT의 주석을 해제한다.

START TRANSACTION;

-- 1. 변경 전 대상 확인: 정확히 4명이 조회돼야 한다.
SELECT id, name, role, is_all_store_access, status
FROM employee
WHERE id IN (13, 16, 33, 73)
ORDER BY id;

-- 2. 기존 중복 확인: 결과가 없어야 한다.
SELECT employee_id, store_id, COUNT(*) AS access_count
FROM employee_store_access
WHERE store_id = 42
  AND employee_id IN (13, 16, 33, 73)
GROUP BY employee_id, store_id
HAVING COUNT(*) > 1;

-- 3. 기존 접근 행이 비활성 상태라면 활성화한다.
UPDATE employee_store_access
SET status = 'ACTIVE'
WHERE store_id = 42
  AND employee_id IN (13, 16, 33, 73)
  AND status <> 'ACTIVE';

-- 4. 접근 행이 없는 직원만 추가한다.
INSERT INTO employee_store_access (
    employee_id,
    store_id,
    status,
    created_at
)
SELECT
    requested.employee_id,
    42,
    'ACTIVE',
    CURRENT_TIMESTAMP
FROM (
    SELECT 13 AS employee_id
    UNION ALL SELECT 16
    UNION ALL SELECT 33
    UNION ALL SELECT 73
) AS requested
WHERE NOT EXISTS (
    SELECT 1
    FROM employee_store_access esa
    WHERE esa.employee_id = requested.employee_id
      AND esa.store_id = 42
);

-- 5. 변경 결과: 각 직원별 ACTIVE 접근 행이 정확히 1개여야 한다.
SELECT
    e.id AS employee_id,
    e.name,
    e.role,
    e.is_all_store_access,
    e.status AS employee_status,
    esa.id AS access_id,
    esa.status AS access_status,
    esa.created_at
FROM employee e
LEFT JOIN employee_store_access esa
    ON esa.employee_id = e.id
   AND esa.store_id = 42
WHERE e.id IN (13, 16, 33, 73)
ORDER BY e.id, esa.id;

-- COMMIT;
ROLLBACK;
