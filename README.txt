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


Автодеплой после merge PR в main (GitHub Actions)

- Workflow: `.github/workflows/deploy-on-main.yml`
- Триггер: любой `push` в `main` (включая merge Pull Request)
- На сервере выполняется: `./scripts/deploy_from_git.sh`
- Скрипт деплоя:
  - берёт lock (`run/deploy.lock`);
  - делает `git fetch` + `git pull --ff-only` по ветке `main`;
  - останавливает/стартует сервер;
  - проверяет `/health`.

Требуемые GitHub Secrets:
- `DEPLOY_HOST` — хост сервера
- `DEPLOY_USER` — SSH-пользователь
- `DEPLOY_SSH_KEY` — приватный ключ (PEM/OpenSSH)
- `DEPLOY_PORT` — порт SSH (обычно `22`, опционально)

Важно:
- Если в рабочей директории сервера есть незакоммиченные изменения, деплой завершится ошибкой (защита от случайной потери данных).
- Убедитесь, что `scripts/deploy_from_git.sh` исполняемый: `chmod +x scripts/deploy_from_git.sh`


Миграция meta.json (backward-compatible)

- Текущая схема метаданных: `meta_schema_version=2`.
- При первом чтении legacy `meta.json` сервер автоматически нормализует файл и делает атомарный rewrite:
  - добавляет `sensor_events_file_jsonl` и `sensor_events_file_csv` (пути по умолчанию в директории сессии);
  - добавляет `sensor_event_count=0`;
  - добавляет `sensor_streams` с дефолтными флагами потоков;
  - проставляет `meta_schema_version=2`.
- Операционные скрипты (`scripts/list_sessions.sh`) показывают `meta_v`, чтобы быстро видеть состояние миграции по сессиям.


Индекс сессий: назначение файлов

- `data/manifests/sessions_index.jsonl` — **audit log** (append-only): исторические снапшоты `meta` для диагностики и расследований; не использовать как источник истины для чтения актуального состояния.
- `data/manifests/sessions_index.json` — **query index** (JSON map, upsert по `session_id`): быстрый lookup актуальных полей (`status`, счетчики, даты) без сканирования дерева файлов.
- Источником истины по конкретной сессии остается `meta.json` в директории сессии; индекс — производное представление.
