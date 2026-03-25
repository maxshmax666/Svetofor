#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APP_DIR:-/opt/gps-logger}"
BRANCH="${BRANCH:-main}"
RUN_DIR="$ROOT_DIR/run"
LOCK_FILE="$RUN_DIR/deploy.lock"

mkdir -p "$RUN_DIR"

exec 9>"$LOCK_FILE"
flock -n 9 || {
  echo "Another deploy is already running"
  exit 1
}

cd "$ROOT_DIR"

git rev-parse --is-inside-work-tree >/dev/null 2>&1

DIRTY="$(git status --porcelain \
  --untracked-files=all \
  -- . \
  ':(exclude)data/sessions' \
  ':(exclude)data/exports' \
  ':(exclude)data/manifests/sessions_index.json' \
  ':(exclude)data/manifests/sessions_index.jsonl' \
  ':(exclude)run/deploy.lock'
)"

if [[ -n "$DIRTY" ]]; then
  echo "Working tree is dirty (excluding runtime data)."
  echo "$DIRTY"
  exit 1
fi

git fetch origin "$BRANCH"
git pull --ff-only origin "$BRANCH"

if [[ -x "$ROOT_DIR/scripts/stop_gps_logger.sh" ]]; then
  "$ROOT_DIR/scripts/stop_gps_logger.sh"
fi

if [[ -x "$ROOT_DIR/scripts/start_gps_logger.sh" ]]; then
  "$ROOT_DIR/scripts/start_gps_logger.sh"
fi

if [[ -x "$ROOT_DIR/scripts/healthcheck.sh" ]]; then
  "$ROOT_DIR/scripts/healthcheck.sh"
else
  curl -fsS http://127.0.0.1:18080/health >/dev/null
fi

echo "Deploy completed successfully"
