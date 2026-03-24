from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Optional, Dict, Any


@dataclass
class SessionMeta:
    session_id: str
    created_at: str
    closed_at: Optional[str]
    status: str
    session_date: str
    points_file_jsonl: str
    points_file_csv: str
    sensor_events_file_jsonl: str
    sensor_events_file_csv: str
    comments_file_jsonl: str
    csv_materialized: bool
    csv_last_exported_at: Optional[str]
    events_file: str
    point_count: int
    sensor_event_count: int
    comment_count: int
    sensor_streams: Dict[str, Any]
    device: Dict[str, Any]
    client: Dict[str, Any]
    sampling: Dict[str, Any]
    meta_schema_version: int = 2

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class RawPoint:
    session_id: str
    point_seq: int
    client_timestamp_ms: Optional[int]
    client_iso_time: Optional[str]
    client_local_time: Optional[str]
    server_received_at: str
    latitude: float
    longitude: float
    accuracy_m: Optional[float]
    altitude_m: Optional[float]
    altitude_accuracy_m: Optional[float]
    heading_deg: Optional[float]
    speed_mps: Optional[float]
    speed_kmh: Optional[float]
    battery_level: Optional[int]
    is_screen_visible: Optional[bool]
    sample_source: Optional[str]
    raw_position_timestamp_ms: Optional[int]
    user_agent: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class SensorEvent:
    session_id: str
    event_seq: int
    event_type: str
    client_timestamp_ms: Optional[int]
    client_iso_time: Optional[str]
    client_local_time: Optional[str]
    server_received_at: str
    value_x: Optional[float]
    value_y: Optional[float]
    value_z: Optional[float]
    alpha: Optional[float]
    beta: Optional[float]
    gamma: Optional[float]
    heading_deg: Optional[float]
    battery_level: Optional[int]
    is_charging: Optional[bool]
    is_screen_visible: Optional[bool]
    sample_source: Optional[str]
    user_agent: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class PointComment:
    session_id: str
    comment_seq: int
    point_seq: int
    point_client_timestamp_ms: Optional[int]
    latitude: float
    longitude: float
    color: str
    duration_sec: int
    comment_text: str
    client_timestamp_ms: Optional[int]
    client_iso_time: Optional[str]
    client_local_time: Optional[str]
    server_received_at: str
    user_agent: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
