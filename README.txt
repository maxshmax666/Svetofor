GPS LOGGER RAW MODE

Запуск:
  ~/gps-logger/scripts/start_gps_logger.sh

Остановка:
  ~/gps-logger/scripts/stop_gps_logger.sh

Проверка:
  ~/gps-logger/scripts/healthcheck.sh
  (проверяет http://127.0.0.1:18080/health)

Список сессий:
  ~/gps-logger/scripts/list_sessions.sh

Tail по сессии:
  ~/gps-logger/scripts/tail_session.sh <session_id>

Экспорт сессии:
  ~/gps-logger/scripts/export_session.sh <session_id>

Открыть в браузере:
  http://127.0.0.1:18080


Миграция meta.json (backward-compatible)

- Текущая схема метаданных: `meta_schema_version=2`.
- При первом чтении legacy `meta.json` сервер автоматически нормализует файл и делает атомарный rewrite:
  - добавляет `sensor_events_file_jsonl` и `sensor_events_file_csv` (пути по умолчанию в директории сессии);
  - добавляет `sensor_event_count=0`;
  - добавляет `sensor_streams` с дефолтными флагами потоков;
  - проставляет `meta_schema_version=2`.
- Операционные скрипты (`scripts/list_sessions.sh`) показывают `meta_v`, чтобы быстро видеть состояние миграции по сессиям.
