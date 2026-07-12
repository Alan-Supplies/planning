---
name: vertical-analysis
description: Use when analyzing trail/hill running from a fit-parser compact CSV — vertical (max-effort climb) detection with pre/post fatigue for workouts, or course structure/pacing/stops/risk for races.
---

# Vertical Analysis

트레일/업힐 러닝의 `<name>_compact.csv`(fit-parser 스킬 산출물)를 하나의 탐지 엔진으로
분석한다. 훈련과 대회는 리포트 모드만 다르다.

Run:

```bash
python3 /path/to/this/skill/scripts/vertical_analysis.py <name>_compact.csv [--mode auto|workout|race] [--out 리포트.md]
```

## 모드 (기본 auto)

- **자동 판별**: 총 시간 180분 이상 → race, 미만 → workout.
  3시간 미만의 짧은 대회만 `--mode race`로 지정 필요.
- 상승 블록이 없으면 모드와 무관하게 "평지 러닝" 판정 후 종료.

## workout 리포트 (훈련)

1. 상승 블록 표 — VAM 400m/h·경사 3% 이상 연속 구간(1.5분 이내 끊김 병합)
2. **버티컬 판정** — 상승 50m+ 블록 중 VAM 최대 **이면서 HR이 세션 최고의 93% 이상**
   (HR 조건 미달이면 "가파른 지형일 뿐, 의도적 최대치 아님"으로 판정 근거 출력)
3. 전후 피로 비교 — 급경사 내리막(-8%↓) HR 변화(+10bpm↑ = 신호),
   평탄 페이스/NGP 대비 HR 디커플링(페이스 하락 + HR +5bpm↑ = 신호)

## race 리포트 (대회)

1. 상승 블록 표 (코스 구조)
2. 시간대별 운영 — 60분 단위 이동거리·HR·상승, HR 드리프트(첫/마지막 1시간)
3. 정지 구간 — 3분 이상 정지(CP·휴식 추정)의 시각·km·고도
4. 위험 신호 — 급경사 내리막을 세션 평균 HR+20 이상으로 내려간 구간(전반/후반 분리,
   후반 = 피로 상태 이심성 제동 → 부상 위험)

참고:
- COROS처럼 grade_pct/ngp가 없는 파일은 고도·이동거리로 경사를 유도하고 페이스로 비교
- 임계값은 스크립트 상단 상수(MIN_VAM, VERTICAL_HR_FRACTION 등)로 조정
- 지표 정의와 코드 사본: `docs/러닝/버티컬분석.md`
