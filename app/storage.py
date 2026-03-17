from __future__ import annotations
import csv
import json
from pathlib import Path
from typing import Dict, Any, Iterable, Iterator


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def append_jsonl(path: Path, payload: Dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def append_csv_row(path: Path, header: Iterable[str], row_map: Dict[str, Any]) -> None:
    file_exists = path.exists()
    with path.open("a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(list(header))
        writer.writerow([row_map.get(col, "") for col in header])


def iter_jsonl(path: Path) -> Iterator[Dict[str, Any]]:
    if not path.exists():
        return
    with path.open("r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()
            if not line:
                continue
            yield json.loads(line)


def rewrite_csv_from_jsonl(path_jsonl: Path, path_csv: Path, header: Iterable[str]) -> int:
    """Fully rebuild CSV from JSONL and return number of rows written."""
    rows_written = 0
    with path_csv.open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        header_list = list(header)
        writer.writerow(header_list)
        for row in iter_jsonl(path_jsonl):
            writer.writerow([row.get(col, "") for col in header_list])
            rows_written += 1
    return rows_written


def append_text_line(path: Path, line: str) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(line.rstrip("\n") + "\n")
