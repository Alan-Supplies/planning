START TRANSACTION;

-- 여 40대 · 근력
UPDATE user_goal_card
SET phrase = '지금부터 근육 모아 두기',
    updated_at = CURRENT_TIMESTAMP
WHERE gender = 'FEMALE'
  AND age_group = 'FORTIES'
  AND purpose = 'STRENGTH_GAIN'
  AND phrase = '뼈 건강 지키기';

-- 남 30대 · 다이어트
UPDATE user_goal_card
SET phrase = '건강검진 복부비만 벗어나기',
    updated_at = CURRENT_TIMESTAMP
WHERE gender = 'MALE'
  AND age_group = 'THIRTIES'
  AND purpose = 'WEIGHT_LOSS'
  AND phrase = '허리띠 한 칸 줄이기';

-- 남 30대 · 근력
UPDATE user_goal_card
SET phrase = '터질듯한 셔츠 핏',
    updated_at = CURRENT_TIMESTAMP
WHERE gender = 'MALE'
  AND age_group = 'THIRTIES'
  AND purpose = 'STRENGTH_GAIN'
  AND phrase = '셔츠 핏이 달라지는 몸 만들기';

-- 남 40대 · 다이어트
UPDATE user_goal_card
SET phrase = '건강검진 복부비만 벗어나기',
    updated_at = CURRENT_TIMESTAMP
WHERE gender = 'MALE'
  AND age_group = 'FORTIES'
  AND purpose = 'WEIGHT_LOSS'
  AND phrase = '허리띠 한 칸 줄이기';

-- 남 40대 · 근력
UPDATE user_goal_card
SET phrase = '힘 좋던 시절 몸 되찾기',
    updated_at = CURRENT_TIMESTAMP
WHERE gender = 'MALE'
  AND age_group = 'FORTIES'
  AND purpose = 'STRENGTH_GAIN'
  AND phrase = '계단에서 숨 차지 않기';

-- 변경 결과 확인
SELECT gender, age_group, purpose, phrase
FROM user_goal_card
WHERE (gender = 'FEMALE' AND age_group = 'FORTIES' AND purpose = 'STRENGTH_GAIN')
   OR (gender = 'MALE' AND age_group = 'THIRTIES'
       AND purpose IN ('WEIGHT_LOSS', 'STRENGTH_GAIN'))
   OR (gender = 'MALE' AND age_group = 'FORTIES'
       AND purpose IN ('WEIGHT_LOSS', 'STRENGTH_GAIN'))
ORDER BY gender, age_group, sort_order;

COMMIT;