---
name: fit-parser
description: Use when parsing .fit running/cycling activity files, extracting records to CSV, or summarizing sessions/laps as JSON. Also use compact_fit.py when the data will be fed to AI analysis (token-efficient).
---

# FIT Parser

When the user asks to parse a `.fit` file, use `scripts/parse_fit.py`.

Run:

```bash
python3 /path/to/this/skill/scripts/parse_fit.py <fit-file>
```

Writes `<name>_records.csv` (1Hz full records) and `<name>_summary.json` (session/laps).

## 멀티 디바이스 지원

FIT 표준을 따르는 기기(COROS, Suunto, Garmin, Wahoo 등)를 모두 처리한다.
- `summary.json`의 `device.manufacturer`로 어느 기기 파일인지 확인
- Suunto처럼 speed/altitude를 `enhanced_*` 필드로만 쓰는 파일도 compact에서 자동 폴백
- developer 필드는 field_description의 이름으로 디코딩되어 `dev_<이름>` 컬럼으로 records CSV에 포함
- 기기가 기록하지 않는 지표(예: Suunto의 러닝 다이내믹스)는 compact에서 컬럼 자동 제외 —
  기기 간 비교 시 다이내믹스 지표(gct_ms 등)는 같은 제조사 데이터끼리만 비교할 것

## AI 분석용 축약 CSV

Full records CSV는 수천 행이라 AI 컨텍스트에 넣으면 토큰 낭비가 크다.
**AI에게 분석을 요청하거나 분석용으로 보관할 때는 `compact_fit.py`를 사용한다.**

```bash
python3 /path/to/this/skill/scripts/compact_fit.py <fit-file> [--interval 30]
```

- `<name>_compact.csv` 생성: 30초(기본) 구간별 집계 — elapsed_min, km, pace(min/km), hr, cad, power, alt, moved_m
  + 러닝 다이내믹스: gct_ms(접지시간), vo_mm(수직진폭), vr_pct(수직비율), step_cm(보폭), bal_pct(좌우 접지 균형)
  + Suunto 파일: grade_pct(경사도 %), ngp(경사 보정 페이스) — developer 필드에서 추출
  - 기기가 기록하지 않은 지표 컬럼은 자동 제외됨 (COROS 워치 단독: bal_pct 없음 / Suunto: 러닝 다이내믹스 없음)
- 1시간 러닝 기준 약 3,400행 → 약 115행 (~99% 토큰 절감)
- 원본 `.fit`은 보관하므로 full records CSV는 필요할 때 재생성하면 된다
- AI 분석 시에는 `_compact.csv` + `_summary.json`(세션/랩 통계) 조합이면 충분하다
