from __future__ import annotations

import argparse
import tarfile
from pathlib import Path

from app.config import EXPORTS_DIR, SESSIONS_DIR
from app.session_manager import materialize_session_csv


def _find_session_dir(session_id: str) -> Path:
    for candidate in SESSIONS_DIR.glob("*/*"):
        if candidate.is_dir() and candidate.name == session_id:
            return candidate
    raise FileNotFoundError(f"session not found: {session_id}")


def export_session_archive(session_id: str, output_path: Path | None = None) -> Path:
    target_dir = _find_session_dir(session_id)
    materialize_session_csv(session_id)

    EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
    archive_path = output_path or (EXPORTS_DIR / f"{session_id}.tar.gz")
    archive_path.parent.mkdir(parents=True, exist_ok=True)

    with tarfile.open(archive_path, mode="w:gz") as tar:
        for child in target_dir.iterdir():
            tar.add(child, arcname=f"{session_id}/{child.name}")

    return archive_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Export session archive with on-demand CSV materialization")
    parser.add_argument("session_id", help="Session identifier")
    parser.add_argument("--output", type=Path, help="Output .tar.gz path")
    args = parser.parse_args()

    archive_path = export_session_archive(args.session_id, args.output)
    print(str(archive_path))


if __name__ == "__main__":
    main()
