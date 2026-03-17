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
