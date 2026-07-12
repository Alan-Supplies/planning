#!/usr/bin/env python3
"""Compact a FIT activity into an AI-analysis-friendly CSV.

Full 1Hz records CSV(수천 행)를 그대로 AI에 넣으면 토큰 낭비가 크므로,
시간 구간(기본 30초)별로 집계한 축약 CSV를 생성한다.

Usage:
    python3 skill/fit-parser/scripts/compact_fit.py 러닝/20260710run.fit
    python3 skill/fit-parser/scripts/compact_fit.py 러닝/20260710run.fit --interval 60

The script writes:
    - <fit-name>_compact.csv: 구간별 집계 (elapsed, km, pace, hr, cadence, power, altitude)
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import Any

from parse_fit import parse_fit


def mean(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def pace_str(seconds_per_km: float | None) -> str | None:
    if seconds_per_km is None or seconds_per_km <= 0 or seconds_per_km > 3600:
        return None
    minutes, seconds = divmod(round(seconds_per_km), 60)
    return f"{minutes}:{seconds:02d}"


def compact_records(records: list[dict[str, Any]], interval: int) -> list[dict[str, Any]]:
    # Suunto 등 일부 기기는 speed/altitude를 enhanced_* 필드로만 기록한다.
    for record in records:
        if record.get("speed") is None:
            record["speed"] = record.get("enhanced_speed")
        if record.get("altitude") is None:
            record["altitude"] = record.get("enhanced_altitude")

    timed = [r for r in records if r.get("timestamp") and r.get("distance") is not None]
    if not timed:
        return []

    from datetime import datetime

    start = datetime.fromisoformat(timed[0]["timestamp"])
    bins: dict[int, list[dict[str, Any]]] = {}
    for record in timed:
        elapsed = (datetime.fromisoformat(record["timestamp"]) - start).total_seconds()
        bins.setdefault(int(elapsed // interval), []).append(record)

    rows = []
    prev_distance = timed[0]["distance"] or 0.0
    for index in sorted(bins):
        group = bins[index]
        distance = group[-1]["distance"]
        delta_m = distance - prev_distance
        prev_distance = distance

        def avg(key: str) -> float | None:
            values = [r[key] for r in group if r.get(key)]
            return mean(values)

        avg_speed = avg("speed")
        altitudes = [r["altitude"] for r in group if r.get("altitude") is not None]
        gct = avg("stance_time")
        vertical_oscillation = avg("vertical_oscillation")
        vertical_ratio = avg("vertical_ratio")
        step_length = avg("step_length")
        balance = avg("stance_time_balance")
        # Suunto developer 필드: 경사도(%)와 NGP(경사 보정 페이스, m/s)
        grade = avg("dev_grd_pct")
        ngp_speed = avg("dev_ngp")

        rows.append(
            {
                "elapsed_min": round(index * interval / 60, 1),
                "km": round(distance / 1000, 2),
                "pace": pace_str(1000 / avg_speed if avg_speed else None),
                "hr": round(avg("heart_rate")) if avg("heart_rate") else None,
                "cad": round(avg("cadence")) if avg("cadence") else None,
                "power": round(avg("power")) if avg("power") else None,
                "alt": round(mean(altitudes), 1) if altitudes else None,
                "moved_m": round(delta_m),
                # 러닝 다이내믹스 (부상/폼 분석용): 접지시간 ms, 수직진폭 mm,
                # 수직비율 %, 보폭 cm, 좌우 접지 균형 %(좌측 기준, 미기록 기기는 컬럼 제외됨)
                "gct_ms": round(gct) if gct else None,
                "vo_mm": round(vertical_oscillation, 1) if vertical_oscillation else None,
                "vr_pct": round(vertical_ratio, 1) if vertical_ratio else None,
                "step_cm": round(step_length / 10, 1) if step_length else None,
                "bal_pct": round(balance, 1) if balance else None,
                "grade_pct": round(grade, 1) if grade is not None else None,
                "ngp": pace_str(1000 / ngp_speed if ngp_speed else None),
            }
        )

    empty_columns = {key for key in rows[0] if all(row[key] is None for row in rows)}
    return [{k: v for k, v in row.items() if k not in empty_columns} for row in rows]


def main() -> None:
    parser = argparse.ArgumentParser(description="Compact a FIT file into an analysis CSV.")
    parser.add_argument("fit_file", type=Path, help="Path to .fit file")
    parser.add_argument("--interval", type=int, default=30, help="집계 구간(초). 기본 30")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Output directory. Defaults to the FIT file directory.",
    )
    args = parser.parse_args()

    out_dir = args.out_dir or args.fit_file.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    records = parse_fit(args.fit_file).get("record", [])
    rows = compact_records(records, args.interval)

    out_path = out_dir / f"{args.fit_file.stem}_compact.csv"
    with out_path.open("w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=list(rows[0]) if rows else [])
        writer.writeheader()
        writer.writerows(rows)

    print(f"compact: {len(records)} records -> {len(rows)} rows ({args.interval}s bins) -> {out_path}")


if __name__ == "__main__":
    main()
