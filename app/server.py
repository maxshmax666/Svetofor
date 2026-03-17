from __future__ import annotations
import io
import json
import tarfile
from pathlib import Path

from flask import Flask, jsonify, request, send_file, Response

from app.config import (
    EXPORTS_DIR,
    HOST,
    PORT,
    RUN_DIR,
    SESSIONS_DIR,
    TIMEZONE_NAME,
)
from app.session_manager import (
    append_point,
    append_sensor_event,
    create_session,
    load_session_meta,
    mark_interrupted_sessions,
    stop_session,
)

app = Flask(__name__, static_folder=None, template_folder=None)


@app.get("/")
def index() -> Response:
    html_path = Path(__file__).resolve().parent.parent / "web" / "gps_logger.html"
    return Response(html_path.read_text(encoding="utf-8"), mimetype="text/html")


@app.get("/health")
def health():
    return jsonify({
        "ok": True,
        "host": HOST,
        "port": PORT,
        "timezone": TIMEZONE_NAME,
        "run_dir": str(RUN_DIR),
        "sessions_dir": str(SESSIONS_DIR),
    })


@app.post("/api/session/start")
def api_session_start():
    payload = request.get_json(silent=True) or {}
    meta = create_session(payload)
    return jsonify({"ok": True, "session": meta})


@app.post("/api/session/stop")
def api_session_stop():
    payload = request.get_json(silent=True) or {}
    session_id = payload.get("sessionId")
    if not session_id:
        return jsonify({"ok": False, "error": "sessionId required"}), 400

    meta = stop_session(session_id)
    return jsonify({"ok": True, "session": meta})


@app.post("/api/point")
def api_point():
    payload = request.get_json(silent=True) or {}
    session_id = payload.get("sessionId")
    if not session_id:
        return jsonify({"ok": False, "error": "sessionId required"}), 400

    try:
        meta, point = append_point(session_id, payload)
        return jsonify({
            "ok": True,
            "sessionId": session_id,
            "pointSeq": point["point_seq"],
            "pointCount": meta["point_count"],
        })
    except FileNotFoundError as e:
        return jsonify({"ok": False, "error": str(e)}), 404
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.post("/api/sensor-event")
def api_sensor_event():
    payload = request.get_json(silent=True) or {}
    session_id = payload.get("sessionId")
    if not session_id:
        return jsonify({"ok": False, "error": "sessionId required"}), 400

    try:
        meta, event = append_sensor_event(session_id, payload)
        return jsonify({
            "ok": True,
            "sessionId": session_id,
            "eventSeq": event["event_seq"],
            "sensorEventCount": meta["sensor_event_count"],
            "eventType": event["event_type"],
        })
    except FileNotFoundError as e:
        return jsonify({"ok": False, "error": str(e)}), 404
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.get("/api/session/<session_id>")
def api_session_meta(session_id: str):
    try:
        meta = load_session_meta(session_id)
        return jsonify({"ok": True, "session": meta})
    except FileNotFoundError as e:
        return jsonify({"ok": False, "error": str(e)}), 404


@app.get("/api/sessions")
def api_sessions():
    items = []
    if SESSIONS_DIR.exists():
        for meta_path in sorted(SESSIONS_DIR.glob("*/*/meta.json")):
            try:
                payload = json.loads(meta_path.read_text(encoding="utf-8"))
                items.append(payload)
            except Exception:
                continue
    items.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return jsonify({"ok": True, "sessions": items})


@app.get("/api/export/session/<session_id>.tar.gz")
def api_export_session(session_id: str):
    target_dir = None
    for candidate in SESSIONS_DIR.glob(f"*/*"):
        if candidate.is_dir() and candidate.name == session_id:
            target_dir = candidate
            break

    if target_dir is None:
        return jsonify({"ok": False, "error": "session not found"}), 404

    EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
    memory_file = io.BytesIO()

    with tarfile.open(fileobj=memory_file, mode="w:gz") as tar:
        for child in target_dir.iterdir():
            tar.add(child, arcname=f"{session_id}/{child.name}")

    memory_file.seek(0)
    return send_file(
        memory_file,
        mimetype="application/gzip",
        as_attachment=True,
        download_name=f"{session_id}.tar.gz",
    )


if __name__ == "__main__":
    recovered = mark_interrupted_sessions()
    print(f"[gps-logger] recovered_interrupted_sessions={recovered}")
    app.run(host=HOST, port=PORT, debug=False)
