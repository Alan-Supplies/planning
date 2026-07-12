#!/usr/bin/env python3
"""Parse a Garmin/ANT FIT activity file without third-party packages.

Usage:
    python3 러닝/parse_fit.py 러닝/20260702보라매.fit
    python3 러닝/parse_fit.py 러닝/20260702보라매.fit --out-dir 러닝/out

The script writes:
    - <fit-name>_records.csv: time-series record points
    - <fit-name>_summary.json: session/lap/activity summary
"""

from __future__ import annotations

import argparse
import csv
import json
import struct
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


FIT_EPOCH = datetime(1989, 12, 31, tzinfo=timezone.utc)

BASE_TYPES: dict[int, tuple[str, int, str, Any]] = {
    0x00: ("enum", 1, "B", 0xFF),
    0x01: ("sint8", 1, "b", 0x7F),
    0x02: ("uint8", 1, "B", 0xFF),
    0x83: ("sint16", 2, "h", 0x7FFF),
    0x84: ("uint16", 2, "H", 0xFFFF),
    0x85: ("sint32", 4, "i", 0x7FFFFFFF),
    0x86: ("uint32", 4, "I", 0xFFFFFFFF),
    0x07: ("string", 1, "s", None),
    0x88: ("float32", 4, "f", 0xFFFFFFFF),
    0x89: ("float64", 8, "d", 0xFFFFFFFFFFFFFFFF),
    0x0A: ("uint8z", 1, "B", 0x00),
    0x8B: ("uint16z", 2, "H", 0x0000),
    0x8C: ("uint32z", 4, "I", 0x00000000),
    0x0D: ("byte", 1, "B", None),
    0x8E: ("sint64", 8, "q", 0x7FFFFFFFFFFFFFFF),
    0x8F: ("uint64", 8, "Q", 0xFFFFFFFFFFFFFFFF),
    0x90: ("uint64z", 8, "Q", 0x0000000000000000),
}

GLOBAL_MESSAGES = {
    0: "file_id",
    18: "session",
    19: "lap",
    20: "record",
    21: "event",
    34: "activity",
    206: "field_description",
    207: "developer_data_id",
}

MANUFACTURERS = {
    1: "garmin",
    23: "suunto",
    32: "wahoo_fitness",
    294: "coros",
}

FIELD_NAMES: dict[int, dict[int, str]] = {
    0: {
        0: "type",
        1: "manufacturer",
        2: "product",
        3: "serial_number",
        4: "time_created",
    },
    206: {
        0: "developer_data_index",
        1: "field_definition_number",
        2: "fit_base_type_id",
        3: "field_name",
        8: "units",
    },
    18: {
        2: "start_time",
        5: "sport",
        6: "sub_sport",
        7: "total_elapsed_time",
        8: "total_timer_time",
        9: "total_distance",
        11: "total_calories",
        14: "avg_speed",
        15: "max_speed",
        16: "avg_heart_rate",
        17: "max_heart_rate",
        18: "avg_cadence",
        19: "max_cadence",
        20: "avg_power",
        21: "max_power",
        22: "total_ascent",
        23: "total_descent",
        57: "avg_temperature",
        64: "min_heart_rate",
        89: "avg_vertical_oscillation",
        90: "avg_stance_time_percent",
        91: "avg_stance_time",
        132: "avg_vertical_ratio",
        133: "avg_stance_time_balance",
        134: "avg_step_length",
        253: "timestamp",
    },
    19: {
        2: "start_time",
        7: "total_elapsed_time",
        8: "total_timer_time",
        9: "total_distance",
        11: "total_calories",
        13: "avg_speed",
        14: "max_speed",
        15: "avg_heart_rate",
        16: "max_heart_rate",
        17: "avg_cadence",
        18: "max_cadence",
        19: "avg_power",
        20: "max_power",
        21: "total_ascent",
        22: "total_descent",
        63: "min_heart_rate",
        77: "avg_vertical_oscillation",
        78: "avg_stance_time_percent",
        79: "avg_stance_time",
        118: "avg_vertical_ratio",
        119: "avg_stance_time_balance",
        120: "avg_step_length",
        253: "timestamp",
    },
    20: {
        0: "position_lat",
        1: "position_long",
        2: "altitude",
        3: "heart_rate",
        4: "cadence",
        5: "distance",
        6: "speed",
        7: "power",
        9: "grade",
        13: "temperature",
        29: "accumulated_power",
        32: "vertical_speed",
        39: "vertical_oscillation",
        40: "stance_time_percent",
        41: "stance_time",
        42: "activity_type",
        73: "enhanced_speed",
        78: "enhanced_altitude",
        83: "vertical_ratio",
        84: "stance_time_balance",
        85: "step_length",
        253: "timestamp",
    },
    34: {
        0: "total_timer_time",
        253: "timestamp",
    },
}

SPORTS = {
    0: "generic",
    1: "running",
    2: "cycling",
    3: "transition",
    4: "fitness_equipment",
    5: "swimming",
    6: "basketball",
    7: "soccer",
    8: "tennis",
    9: "american_football",
    10: "training",
    11: "walking",
}


@dataclass
class FieldDef:
    number: int
    size: int
    base_type: int


@dataclass
class DevFieldDef:
    number: int
    size: int
    data_index: int


@dataclass
class Definition:
    global_message: int
    endian: str
    fields: list[FieldDef]
    developer_fields: list[DevFieldDef]


def fit_time(value: int | None) -> str | None:
    if value is None:
        return None
    return (FIT_EPOCH + timedelta(seconds=value)).isoformat()


def semicircles_to_degrees(value: int | None) -> float | None:
    if value is None:
        return None
    return value * (180.0 / 2**31)


def scaled(field_name: str, value: Any) -> Any:
    if value is None:
        return None
    if field_name in {"timestamp", "start_time", "time_created"}:
        return fit_time(value)
    if field_name == "manufacturer":
        return MANUFACTURERS.get(value, value)
    if field_name in {"position_lat", "position_long"}:
        return semicircles_to_degrees(value)
    if field_name in {"altitude", "enhanced_altitude"}:
        return value / 5 - 500
    if field_name in {"distance", "total_distance"}:
        return value / 100
    if field_name in {"speed", "enhanced_speed", "avg_speed", "max_speed", "vertical_speed"}:
        return value / 1000
    if field_name in {"total_elapsed_time", "total_timer_time"}:
        return value / 1000
    if field_name == "grade":
        return value / 100
    if field_name in {
        "vertical_oscillation",
        "avg_vertical_oscillation",
        "stance_time",
        "avg_stance_time",
        "step_length",
        "avg_step_length",
    }:
        return value / 10
    if field_name in {
        "stance_time_percent",
        "avg_stance_time_percent",
        "vertical_ratio",
        "avg_vertical_ratio",
        "stance_time_balance",
        "avg_stance_time_balance",
    }:
        return value / 100
    if field_name == "sport":
        return SPORTS.get(value, value)
    return value


def read_header(raw: bytes) -> tuple[int, int]:
    header_size = raw[0]
    if raw[8:12] != b".FIT":
        raise ValueError("Not a FIT file: missing .FIT signature")
    data_size = struct.unpack_from("<I", raw, 4)[0]
    return header_size, data_size


def decode_value(payload: bytes, offset: int, field: FieldDef, endian: str) -> Any:
    base_type = field.base_type & 0x1F | (field.base_type & 0xE0)
    info = BASE_TYPES.get(field.base_type) or BASE_TYPES.get(base_type)
    if not info:
        return payload[offset : offset + field.size].hex()

    type_name, unit_size, fmt, invalid = info
    chunk = payload[offset : offset + field.size]

    if type_name == "string":
        return chunk.split(b"\x00", 1)[0].decode("utf-8", errors="replace")

    if field.size == unit_size:
        value = struct.unpack(endian + fmt, chunk)[0]
        return None if invalid is not None and value == invalid else value

    values = []
    for i in range(0, field.size, unit_size):
        part = chunk[i : i + unit_size]
        if len(part) != unit_size:
            break
        value = struct.unpack(endian + fmt, part)[0]
        if invalid is None or value != invalid:
            values.append(value)
    return values or None


def parse_fit(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    header_size, data_size = read_header(raw)
    data = raw[header_size : header_size + data_size]
    offset = 0
    definitions: dict[int, Definition] = {}
    messages: dict[str, list[dict[str, Any]]] = {}
    dev_field_descriptions: dict[tuple[int, int], dict[str, Any]] = {}

    while offset < len(data):
        record_header = data[offset]
        offset += 1

        if record_header & 0x80:
            local_type = record_header & 0x03
            definition = definitions.get(local_type)
            if not definition:
                raise ValueError(f"Compressed record references unknown local type {local_type}")
        else:
            local_type = record_header & 0x0F
            is_definition = bool(record_header & 0x40)

            if is_definition:
                offset += 1  # reserved
                architecture = data[offset]
                offset += 1
                endian = ">" if architecture else "<"
                global_message = struct.unpack_from(endian + "H", data, offset)[0]
                offset += 2
                field_count = data[offset]
                offset += 1
                fields = []
                for _ in range(field_count):
                    number = data[offset]
                    size = data[offset + 1]
                    base_type = data[offset + 2]
                    offset += 3
                    fields.append(FieldDef(number, size, base_type))

                developer_fields: list[DevFieldDef] = []
                if record_header & 0x20:
                    developer_field_count = data[offset]
                    offset += 1
                    for _ in range(developer_field_count):
                        developer_number = data[offset]
                        developer_size = data[offset + 1]
                        developer_index = data[offset + 2]
                        offset += 3
                        developer_fields.append(
                            DevFieldDef(developer_number, developer_size, developer_index)
                        )

                definitions[local_type] = Definition(
                    global_message=global_message,
                    endian=endian,
                    fields=fields,
                    developer_fields=developer_fields,
                )
                continue

            definition = definitions.get(local_type)
            if not definition:
                raise ValueError(f"Data record references unknown local type {local_type}")

        field_map = FIELD_NAMES.get(definition.global_message, {})
        message: dict[str, Any] = {}

        for field in definition.fields:
            field_name = field_map.get(field.number, f"field_{field.number}")
            value = decode_value(data, offset, field, definition.endian)
            offset += field.size
            message[field_name] = scaled(field_name, value)

        for dev_field in definition.developer_fields:
            # field_description(전역 206) 메시지로 등록된 이름/타입으로 디코딩.
            # Suunto 등은 일부 지표를 developer 필드로 기록한다.
            description = dev_field_descriptions.get(
                (dev_field.data_index, dev_field.number)
            )
            if description:
                name = f"dev_{description['name']}"
                base_type = description["base_type"]
                value = decode_value(
                    data,
                    offset,
                    FieldDef(dev_field.number, dev_field.size, base_type),
                    definition.endian,
                )
            else:
                name = f"dev_{dev_field.data_index}_{dev_field.number}"
                value = data[offset : offset + dev_field.size].hex()
            offset += dev_field.size
            message[name] = value

        message_name = GLOBAL_MESSAGES.get(
            definition.global_message,
            f"global_{definition.global_message}",
        )
        messages.setdefault(message_name, []).append(message)

        if message_name == "field_description":
            index = message.get("developer_data_index")
            number = message.get("field_definition_number")
            base_type = message.get("fit_base_type_id")
            if index is not None and number is not None and base_type is not None:
                raw_name = message.get("field_name") or f"{index}_{number}"
                dev_field_descriptions[(index, number)] = {
                    "name": str(raw_name).strip().replace(" ", "_").lower(),
                    "base_type": base_type,
                }

    return messages


def summarize(messages: dict[str, list[dict[str, Any]]]) -> dict[str, Any]:
    records = messages.get("record", [])
    sessions = messages.get("session", [])
    laps = messages.get("lap", [])
    session = sessions[-1] if sessions else {}

    file_ids = messages.get("file_id", [])
    device = file_ids[0] if file_ids else {}

    return {
        "device": {
            "manufacturer": device.get("manufacturer"),
            "product": device.get("product"),
        },
        "session": session,
        "record_count": len(records),
        "lap_count": len(laps),
        "laps": laps,
        "activity": messages.get("activity", []),
    }


def write_records_csv(records: list[dict[str, Any]], path: Path) -> None:
    preferred_columns = [
        "timestamp",
        "position_lat",
        "position_long",
        "distance",
        "speed",
        "enhanced_speed",
        "altitude",
        "enhanced_altitude",
        "heart_rate",
        "cadence",
        "power",
        "stance_time",
        "vertical_oscillation",
        "vertical_ratio",
        "step_length",
        "stance_time_balance",
        "temperature",
    ]
    discovered_columns = sorted({key for record in records for key in record})
    columns = [column for column in preferred_columns if column in discovered_columns]
    columns.extend(column for column in discovered_columns if column not in columns)

    with path.open("w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=columns)
        writer.writeheader()
        writer.writerows(records)


def main() -> None:
    parser = argparse.ArgumentParser(description="Parse a FIT activity file.")
    parser.add_argument("fit_file", type=Path, help="Path to .fit file")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Output directory. Defaults to the FIT file directory.",
    )
    args = parser.parse_args()

    fit_file = args.fit_file
    out_dir = args.out_dir or fit_file.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    messages = parse_fit(fit_file)
    records = messages.get("record", [])
    summary = summarize(messages)

    records_path = out_dir / f"{fit_file.stem}_records.csv"
    summary_path = out_dir / f"{fit_file.stem}_summary.json"

    write_records_csv(records, records_path)
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    session = summary.get("session", {})
    print(f"records: {len(records)} -> {records_path}")
    print(f"summary: {summary_path}")
    if session:
        print(f"start_time: {session.get('start_time')}")
        print(f"distance_m: {session.get('total_distance')}")
        print(f"timer_sec: {session.get('total_timer_time')}")
        print(f"avg_hr: {session.get('avg_heart_rate')}")


if __name__ == "__main__":
    main()
