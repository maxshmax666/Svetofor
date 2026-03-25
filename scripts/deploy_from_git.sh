#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/gps-logger}"
BRANCH="${BRANCH:-main}"
LOCK_DIR="${APP_DIR}/run"
LOCK_FILE="${LOCK_DIR}/deploy.lock"

mkdir -p "$LOCK_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[ERR] Деплой уже выполняется: $LOCK_FILE"
  exit 1
fi

cd "$APP_DIR"

if [ ! -d .git ]; then
  echo "[ERR] $APP_DIR не является git-репозиторием"
  exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
  echo "[INFO] Переключение ветки: $CURRENT_BRANCH -> $BRANCH"
  git checkout "$BRANCH"
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "[ERR] Есть локальные незакоммиченные изменения. Деплой остановлен."
  git status --short
  exit 1
fi

echo "[INFO] Обновление репозитория ($BRANCH)..."
git fetch origin "$BRANCH"
git pull --ff-only origin "$BRANCH"

echo "[INFO] Перезапуск сервиса..."
./scripts/stop_gps_logger.sh || true
./scripts/start_gps_logger.sh
./scripts/healthcheck.sh

echo "[OK] Деплой завершен успешно"
