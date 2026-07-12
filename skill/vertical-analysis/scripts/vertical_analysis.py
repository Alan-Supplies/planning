#!/usr/bin/env python3
"""업힐 러닝 분석: 훈련(버티컬)과 대회(코스 운영)를 하나의 탐지 엔진으로 처리.

fit-parser 스킬의 compact_fit.py가 만든 `<name>_compact.csv`를 입력으로:
- 상승 블록 탐지 — VAM(시간당 상승 m)·경사 기준, 짧은 끊김(휴식·스위치백)은 병합
- 모드 자동 판별:
  * workout — 버티컬(의도적 최대치 등반) 판정 + 전후 피로 비교
  * race    — 코스 구조, 시간대별 운영, 정지(CP), 위험 신호(피로 상태 내리막 고강도)
- 버티컬 판정 조건: VAM 최대이면서 HR이 세션 최고에 근접(기본 93%)
  → 대회의 "그냥 가파른 지형"과 훈련의 "최대치 시도"를 구분

Usage:
    python3 vertical_analysis.py 러닝/20260613_achasan_compact.csv
    python3 vertical_analysis.py 러닝/2026-korea50k_compact.csv --mode race
    python3 vertical_analysis.py <compact.csv> --out 리포트.md

COROS처럼 grade_pct/ngp 컬럼이 없는 파일은 고도·이동거리에서 경사를 유도하고
페이스로 대신 비교한다.
"""

from __future__ import annotations

import argparse
import csv
import statistics
from dataclasses import dataclass
from pathlib import Path

MIN_VAM = 400          # 상승 블록으로 인정할 최소 VAM (m/h)
MIN_GRADE = 3.0        # 상승 블록으로 인정할 최소 경사 (%)
MAX_GAP_BINS = 3       # 블록 병합 시 허용하는 비상승 구간 수
MIN_CLIMB_GAIN = 30    # 보고할 블록의 최소 상승량 (m)
VERTICAL_MIN_GAIN = 50  # 버티컬 후보의 최소 상승량 (m)
VERTICAL_HR_FRACTION = 0.93  # 버티컬 인정에 필요한 HR (세션 최고 대비)
STEEP_DOWN_GRADE = -8.0  # 급경사 내리막 기준 (%)
FLAT_GRADE = 3.0       # 평탄 구간 기준 (|경사| %)
RACE_MIN_MINUTES = 180  # 이 시간을 넘으면 race 모드로 판별
STOP_MOVED_M = 20      # 30초에 이만큼도 못 가면 정지로 간주
STOP_MIN_MINUTES = 3.0  # 정지로 보고할 최소 지속 시간
RISK_HR_MARGIN = 20    # 내리막 위험 신호: 세션 평균 HR + 이 값 이상


@dataclass
class Bin:
    t: float          # 경과 분
    km: float
    alt: float | None
    hr: int | None
    power: int | None
    pace_s: int | None
    ngp_s: int | None
    grade: float | None
    moved: float
    vam: float = 0.0  # 직전 구간 대비 상승률 (m/h)


@dataclass
class Climb:
    start: Bin
    end: Bin
    gain: float
    minutes: float
    vam: float
    hr_avg: int
    hr_max: int
    power_avg: int


@dataclass
class Stop:
    start: Bin
    end: Bin
    minutes: float


def pace_seconds(text: str | None) -> int | None:
    if not text:
        return None
    minutes, seconds = text.split(":")
    return int(minutes) * 60 + int(seconds)


def fmt_pace(seconds: float | None) -> str:
    if not seconds:
        return "-"
    return f"{int(seconds // 60)}:{int(seconds % 60):02d}"


def load_bins(path: Path) -> list[Bin]:
    bins: list[Bin] = []
    with path.open(encoding="utf-8") as csvfile:
        for row in csv.DictReader(csvfile):
            bins.append(
                Bin(
                    t=float(row["elapsed_min"]),
                    km=float(row["km"]),
                    alt=float(row["alt"]) if row.get("alt") else None,
                    hr=int(row["hr"]) if row.get("hr") else None,
                    power=int(row["power"]) if row.get("power") else None,
                    pace_s=pace_seconds(row.get("pace")),
                    ngp_s=pace_seconds(row.get("ngp")),
                    grade=float(row["grade_pct"]) if row.get("grade_pct") else None,
                    moved=float(row["moved_m"]) if row.get("moved_m") else 0.0,
                )
            )

    prev_alt = None
    minutes = bin_minutes(bins)
    for b in bins:
        if b.alt is not None and prev_alt is not None:
            b.vam = (b.alt - prev_alt) * 60 / minutes
            if b.grade is None and b.moved > 0:
                b.grade = (b.alt - prev_alt) / b.moved * 100
        prev_alt = b.alt if b.alt is not None else prev_alt
    return bins


def bin_minutes(bins: list[Bin]) -> float:
    steps = [b2.t - b1.t for b1, b2 in zip(bins, bins[1:]) if b2.t > b1.t]
    return statistics.median(steps) if steps else 0.5


def is_climbing(b: Bin) -> bool:
    return b.vam >= MIN_VAM and (b.grade or 0) >= MIN_GRADE


def detect_climbs(bins: list[Bin]) -> list[Climb]:
    """상승 구간 인덱스를 모으고, MAX_GAP_BINS 이하의 끊김은 한 블록으로 병합."""
    groups: list[list[int]] = []
    for i, b in enumerate(bins):
        if not is_climbing(b):
            continue
        if groups and i - groups[-1][-1] <= MAX_GAP_BINS + 1:
            groups[-1].append(i)
        else:
            groups.append([i])

    climbs = []
    for group in groups:
        segment = bins[group[0] : group[-1] + 1]
        # 상승량은 시작 직전 고도 대비 종료 고도 (병합 구간 내 하강 반영)
        start_alt = bins[group[0] - 1].alt if group[0] > 0 else segment[0].alt
        gain = (segment[-1].alt or 0) - (start_alt or 0)
        minutes = segment[-1].t - segment[0].t + bin_minutes(bins)
        if gain < MIN_CLIMB_GAIN or minutes <= 0:
            continue
        heart_rates = [b.hr for b in segment if b.hr]
        powers = [b.power for b in segment if b.power]
        climbs.append(
            Climb(
                start=segment[0],
                end=segment[-1],
                gain=gain,
                minutes=minutes,
                vam=gain / minutes * 60,
                hr_avg=round(statistics.mean(heart_rates)) if heart_rates else 0,
                hr_max=max(heart_rates) if heart_rates else 0,
                power_avg=round(statistics.mean(powers)) if powers else 0,
            )
        )
    return climbs


def find_stops(bins: list[Bin]) -> list[Stop]:
    stops = []
    current: list[Bin] = []
    for b in bins:
        if b.moved < STOP_MOVED_M:
            current.append(b)
        else:
            if current:
                minutes = current[-1].t - current[0].t + bin_minutes(bins)
                if minutes >= STOP_MIN_MINUTES:
                    stops.append(Stop(current[0], current[-1], minutes))
            current = []
    if current:
        minutes = current[-1].t - current[0].t + bin_minutes(bins)
        if minutes >= STOP_MIN_MINUTES:
            stops.append(Stop(current[0], current[-1], minutes))
    return stops


def pick_vertical(climbs: list[Climb], session_hr_max: int) -> tuple[Climb | None, Climb | None]:
    """(버티컬, 탈락한 최대 VAM 후보)를 반환.

    버티컬 = 상승 VERTICAL_MIN_GAIN 이상 블록 중 VAM 최대이면서
    HR이 세션 최고의 VERTICAL_HR_FRACTION 이상 — 즉 '의도적 최대치'.
    """
    candidates = [c for c in climbs if c.gain >= VERTICAL_MIN_GAIN]
    if not candidates:
        return None, None
    best = max(candidates, key=lambda c: c.vam)
    if session_hr_max and best.hr_max >= VERTICAL_HR_FRACTION * session_hr_max:
        return best, None
    return None, best


def decide_mode(bins: list[Bin], stops: list[Stop]) -> tuple[str, str]:
    # 훈련 중 휴식도 CP처럼 보이므로 정지 패턴은 판별에 쓰지 않는다.
    # 3시간 미만의 짧은 대회는 --mode race로 지정.
    total_minutes = bins[-1].t if bins else 0
    if total_minutes >= RACE_MIN_MINUTES:
        return "race", f"총 {total_minutes:.0f}분 ≥ {RACE_MIN_MINUTES}분"
    return "workout", f"총 {total_minutes:.0f}분 < {RACE_MIN_MINUTES}분"


def climbs_table(climbs: list[Climb], vertical: Climb | None) -> list[str]:
    lines = ["## 상승 블록", "", "| 시간(분) | km | 상승 | 소요 | VAM | HR(평균~최고) | 파워 | |", "|---|---|---|---|---|---|---|---|"]
    for c in sorted(climbs, key=lambda c: c.start.t):
        mark = " **← 버티컬**" if c is vertical else ""
        lines.append(
            f"| {c.start.t:.1f}~{c.end.t:.1f} | {c.start.km:.1f}~{c.end.km:.1f} | +{c.gain:.0f}m "
            f"| {c.minutes:.1f}분 | {c.vam:.0f}m/h | {c.hr_avg}~{c.hr_max} | {c.power_avg}W |{mark} |"
        )
    lines.append("")
    return lines


def fatigue_report(bins: list[Bin], vertical: Climb) -> list[str]:
    """버티컬 전/후의 내리막 HR과 평탄 구간 페이스-HR 디커플링 비교."""
    before = [b for b in bins if b.t < vertical.start.t]
    after = [b for b in bins if b.t > vertical.end.t]
    lines = ["## 버티컬 전후 운영 비교 (피로 지표)", ""]

    def downhill_hr(section: list[Bin]) -> tuple[int, int] | None:
        hrs = [b.hr for b in section if b.hr and (b.grade or 0) <= STEEP_DOWN_GRADE]
        return (round(statistics.mean(hrs)), len(hrs)) if len(hrs) >= 3 else None

    def flat_stats(section: list[Bin]) -> tuple[float, float, int] | None:
        flat = [
            b for b in section
            if b.hr and abs(b.grade or 99) < FLAT_GRADE and (b.ngp_s or b.pace_s)
        ]
        if len(flat) < 3:
            return None
        pace = statistics.mean(b.ngp_s or b.pace_s for b in flat)
        hr = statistics.mean(b.hr for b in flat)
        return pace, hr, len(flat)

    down_before, down_after = downhill_hr(before), downhill_hr(after)
    if down_before and down_after:
        delta = down_after[0] - down_before[0]
        lines.append(
            f"- 급경사 내리막({STEEP_DOWN_GRADE:.0f}%↓) HR: "
            f"전 {down_before[0]}({down_before[1]}구간) → 후 {down_after[0]}({down_after[1]}구간), "
            f"**{delta:+d}bpm**"
        )
        if delta >= 10:
            lines.append("  - 내리막에서 심박이 충분히 회복되지 않음 → 피로 누적 신호")

    flat_before, flat_after = flat_stats(before), flat_stats(after)
    if flat_before and flat_after:
        pace_delta = flat_after[0] - flat_before[0]
        hr_delta = flat_after[1] - flat_before[1]
        lines.append(
            f"- 평탄 구간(±{FLAT_GRADE:.0f}%) 페이스/NGP: 전 {fmt_pace(flat_before[0])} → 후 {fmt_pace(flat_after[0])}"
            f" | HR: 전 {flat_before[1]:.0f} → 후 {flat_after[1]:.0f}"
        )
        if pace_delta > 0 and hr_delta >= 5:
            lines.append("  - 출력(페이스)은 줄었는데 심박은 상승 → 디커플링(피로) 신호")

    if len(lines) == 2:
        lines.append("- 비교 가능한 전/후 구간이 부족함")
    if vertical.start.t < 15:
        lines.append(
            "- ⚠️ 버티컬이 러닝 초반이라 '전' 구간 표본이 적음 — 전후 비교 신뢰도 낮음"
        )
    return lines


def workout_report(bins: list[Bin], climbs: list[Climb], session_hr_max: int) -> list[str]:
    vertical, rejected = pick_vertical(climbs, session_hr_max)
    lines = climbs_table(climbs, vertical)

    if vertical:
        lines += [
            f"## 버티컬 판정: {vertical.start.t:.1f}~{vertical.end.t:.1f}분 (km {vertical.start.km:.1f}~{vertical.end.km:.1f})",
            "",
            f"- +{vertical.gain:.0f}m / {vertical.minutes:.1f}분, VAM {vertical.vam:.0f}m/h, "
            f"HR 최고 {vertical.hr_max} (세션 최고 {session_hr_max}의 {vertical.hr_max / session_hr_max * 100:.0f}%)",
            "",
        ]
        lines += fatigue_report(bins, vertical)
    elif rejected:
        lines += [
            "## 버티컬 판정: 없음",
            "",
            f"- 최대 VAM 블록({rejected.start.t:.1f}~{rejected.end.t:.1f}분, VAM {rejected.vam:.0f})의 "
            f"HR 최고 {rejected.hr_max}가 세션 최고 {session_hr_max}의 "
            f"{rejected.hr_max / session_hr_max * 100:.0f}%에 그침 — 의도적 최대치 시도로 보기 어려움",
        ]
    else:
        lines.append(f"+{VERTICAL_MIN_GAIN}m 이상 블록이 없어 버티컬 판정 없음.")
    return lines


def race_report(bins: list[Bin], climbs: list[Climb], stops: list[Stop]) -> list[str]:
    hrs = [b.hr for b in bins if b.hr]
    hr_avg = statistics.mean(hrs) if hrs else 0
    lines = climbs_table(climbs, None)

    # 시간대별 운영
    lines += ["## 시간대별 운영", "", "| 구간 | 이동 | HR 평균 | 상승 |", "|---|---|---|---|"]
    total = bins[-1].t
    for hour_start in range(0, int(total) + 1, 60):
        window = [b for b in bins if hour_start <= b.t < hour_start + 60]
        if len(window) < 2:
            continue
        window_hrs = [b.hr for b in window if b.hr]
        ascent = sum(b.vam for b in window if b.vam > 0) * bin_minutes(bins) / 60
        lines.append(
            f"| {hour_start}~{min(hour_start + 60, int(total))}분 "
            f"| {window[-1].km - window[0].km:.1f}km "
            f"| {statistics.mean(window_hrs):.0f} "
            f"| +{ascent:.0f}m |"
        )
    first_hrs = [b.hr for b in bins if b.hr and b.t < 60]
    last_hrs = [b.hr for b in bins if b.hr and b.t >= total - 60]
    if first_hrs and last_hrs:
        drift = statistics.mean(last_hrs) - statistics.mean(first_hrs)
        lines += ["", f"- HR 드리프트(첫 1시간 → 마지막 1시간): {drift:+.0f}bpm"]
    lines.append("")

    # 정지 구간 (CP/휴식)
    lines += ["## 정지 구간 (CP·휴식 추정)", ""]
    if stops:
        for s in stops:
            lines.append(
                f"- {s.start.t:.1f}~{s.end.t:.1f}분 ({s.minutes:.1f}분), km {s.start.km:.1f}, 고도 {s.start.alt:.0f}m"
            )
    else:
        lines.append("- 3분 이상 정지 없음")
    lines.append("")

    # 위험 신호: 급경사 내리막에서 세션 평균 + RISK_HR_MARGIN 이상
    risky = [
        b for b in bins
        if b.hr and (b.grade or 0) <= STEEP_DOWN_GRADE and b.hr >= hr_avg + RISK_HR_MARGIN
    ]
    lines += ["## 위험 신호 (내리막 고강도)", ""]
    if risky:
        half = bins[-1].t / 2
        early = [b for b in risky if b.t < half]
        late = [b for b in risky if b.t >= half]
        risk_hr_max = max(b.hr for b in risky)
        lines.append(
            f"- 급경사 내리막(-8%↓)을 세션 평균 HR({hr_avg:.0f})+{RISK_HR_MARGIN} 이상으로 내려간 구간: "
            f"전반 {len(early)}개 / 후반 {len(late)}개 (HR 최고 {risk_hr_max})"
        )
        if late:
            lines.append(
                f"- 특히 후반({half:.0f}분 이후)의 {len(late)}개 구간은 피로한 안정근 + 이심성 제동이 겹침 "
                "— 부상 관리 관점에서 강도 재고 권장"
            )
    else:
        lines.append("- 없음 (내리막을 평균 강도 이내로 운영)")
    return lines


def build_report(path: Path, bins: list[Bin], mode_arg: str) -> str:
    climbs = detect_climbs(bins)
    stops = find_stops(bins)
    hrs = [b.hr for b in bins if b.hr]
    session_hr_max = max(hrs) if hrs else 0

    lines = [f"# 버티컬/업힐 분석 — {path.stem}", ""]
    if not climbs:
        lines.append(f"상승 블록(VAM {MIN_VAM}+ m/h, +{MIN_CLIMB_GAIN}m 이상) 없음 — 평지 러닝으로 판단.")
        return "\n".join(lines)

    if mode_arg == "auto":
        mode, reason = decide_mode(bins, stops)
        lines.append(f"**모드: {mode}** (자동 판별 — {reason})")
    else:
        mode = mode_arg
        lines.append(f"**모드: {mode}** (사용자 지정)")
    lines.append("")

    if mode == "race":
        lines += race_report(bins, climbs, stops)
    else:
        lines += workout_report(bins, climbs, session_hr_max)
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="compact CSV에서 버티컬/업힐 분석")
    parser.add_argument("compact_csv", type=Path, help="fit-parser의 <name>_compact.csv")
    parser.add_argument("--mode", choices=["auto", "workout", "race"], default="auto")
    parser.add_argument("--out", type=Path, default=None, help="리포트를 저장할 마크다운 경로")
    args = parser.parse_args()

    bins = load_bins(args.compact_csv)
    report = build_report(args.compact_csv, bins, args.mode)

    print(report)
    if args.out:
        args.out.write_text(report + "\n", encoding="utf-8")
        print(f"\n(saved: {args.out})")


if __name__ == "__main__":
    main()
