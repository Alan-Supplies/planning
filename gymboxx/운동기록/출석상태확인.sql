-- 출석 상태 확인 쿼리 (gymboxx dev, readonly)
--
-- 접속 정보(host/계정/비밀번호)는 docs/ai/gymboxx.db.md 참고 (readonly_ssl 계정, --ssl-mode=REQUIRED).
--
-- 배경: pass-server 의 출입 판정(user.service.ts:168 validateUserAccess)은
--   - 오늘(KST) ACCESS/REVISIT 기록이 없으면            → ACCESS  (소켓 push 옴)
--   - 마지막 ACCESS/REVISIT 이 180분 이내 + 같은 지점    → REENTER (소켓 push 없음)
--   - 그 외                                              → REVISIT (소켓 push 옴)
-- 소켓 push 는 ACCESS / REVISIT 에서만 발생한다(user.service.ts:329,334).
-- created_at 은 UTC 저장 → 표시/판정은 KST(+09:00) 로 변환한다.
--
-- 아래 :USER_ID 를 대상 회원으로 바꿔 쓴다 (예: 51758 = Alan).


-- ─────────────────────────────────────────────────────────────
-- 1) 오늘(KST) 출석 기록 — 지금 상태 스냅샷
-- ─────────────────────────────────────────────────────────────
SELECT ah.id,
       ah.type,                                              -- ACCESS / REVISIT / REENTER / EXPIRED ...
       ah.method,                                            -- BARCODE / FACE
       ah.gym_id,
       ah.barcode,
       CONVERT_TZ(ah.created_at, '+00:00', '+09:00') AS created_kst,
       TIMESTAMPDIFF(MINUTE, ah.created_at, UTC_TIMESTAMP()) AS min_ago
FROM access_history ah
WHERE ah.user_id = 51758
  AND ah.created_at >= CONVERT_TZ(
        CONCAT(DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+09:00')), ' 00:00:00'),
        '+09:00', '+00:00')                                  -- 오늘 KST 자정 이후
ORDER BY ah.id DESC;


-- ─────────────────────────────────────────────────────────────
-- 2) 최근 출석 기록 N건 — 어제/지난 실행 추적용
-- ─────────────────────────────────────────────────────────────
SELECT ah.id,
       ah.type,
       ah.method,
       ah.gym_id,
       ah.barcode,
       CONVERT_TZ(ah.created_at, '+00:00', '+09:00') AS created_kst
FROM access_history ah
WHERE ah.user_id = 51758
ORDER BY ah.id DESC
LIMIT 12;


-- ─────────────────────────────────────────────────────────────
-- 3) 다음 스캔 예측 — 지금 바코드를 찍으면 ACCESS/REVISIT/REENTER 중 무엇이 될지
--    (집계함수 대신 LEFT JOIN 으로 "오늘 기록 0건" = NULL 을 정확히 구분한다)
-- ─────────────────────────────────────────────────────────────
SELECT
  CASE
    WHEN t.last_id IS NULL
      THEN 'ACCESS 예상 (오늘 첫 출석 → 소켓 옴)'
    WHEN t.min_ago < 180
      THEN CONCAT('REENTER 위험 — 마지막 출입 ', t.min_ago,
                  '분 전 (gym ', t.last_gym, '). 같은 지점 재스캔이면 소켓 없음')
    ELSE 'REVISIT 예상 (소켓 옴)'
  END AS next_scan_prediction
FROM (SELECT 1) dummy
LEFT JOIN (
  SELECT ah.id AS last_id,
         ah.gym_id AS last_gym,
         TIMESTAMPDIFF(MINUTE, ah.created_at, UTC_TIMESTAMP()) AS min_ago
  FROM access_history ah
  WHERE ah.user_id = 51758
    AND ah.type IN ('ACCESS', 'REVISIT')                     -- getUserLatestAccessHistory 와 동일
    AND ah.created_at >= CONVERT_TZ(
          CONCAT(DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+09:00')), ' 00:00:00'),
          '+09:00', '+00:00')
  ORDER BY ah.id DESC
  LIMIT 1
) t ON 1 = 1;


-- ─────────────────────────────────────────────────────────────
-- 4) 특정 지점 기준 예측 — 스크립트의 gym 과 맞춰서 확인
--    REENTER 는 "같은 지점(gym.unique_id 일치)" 조건이므로 지점을 고정해서 본다.
--    :GYM_ID 를 스크립트의 gymId 로 바꾼다 (예: 5 또는 494).
-- ─────────────────────────────────────────────────────────────
SELECT
  CASE
    WHEN t.last_id IS NULL
      THEN 'ACCESS 예상 (이 지점 오늘 첫 출석 → 소켓 옴)'
    WHEN t.min_ago < 180
      THEN CONCAT('REENTER 예상 (소켓 없음) — 이 지점 마지막 출입 ', t.min_ago, '분 전')
    ELSE 'REVISIT 예상 (소켓 옴)'
  END AS next_scan_prediction_for_gym
FROM (SELECT 1) dummy
LEFT JOIN (
  SELECT ah.id AS last_id,
         TIMESTAMPDIFF(MINUTE, ah.created_at, UTC_TIMESTAMP()) AS min_ago
  FROM access_history ah
  WHERE ah.user_id = 51758
    AND ah.gym_id = 5                                        -- ← 대상 지점
    AND ah.type IN ('ACCESS', 'REVISIT')
    AND ah.created_at >= CONVERT_TZ(
          CONCAT(DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+09:00')), ' 00:00:00'),
          '+09:00', '+00:00')
  ORDER BY ah.id DESC
  LIMIT 1
) t ON 1 = 1;


-- ─────────────────────────────────────────────────────────────
-- 5) 지점(gym) 확인 — id ↔ unique_id ↔ 이름
--    스크립트의 gymId 와 gymUniqueId 가 같은 지점을 가리키는지 대조한다.
--    (pass login 은 gym_unique_id, 소켓 연결/판정은 gym_id 를 쓴다)
-- ─────────────────────────────────────────────────────────────
SELECT id, unique_id, name
FROM gym
WHERE id IN (5, 494);
