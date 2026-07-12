#!/usr/bin/env bash
# ============================================================
# Run the SAME smoke flow as Jenkins — from VS Code / Terminal
# Usage:
#   ./run-local.sh
#   ./run-local.sh --repo /path/to/fastapi-for-ai
#   ./run-local.sh --port 8001
#   APP_ENV=stage ./run-local.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR=""
PORT="${PORT:-8000}"
APP_ENV="${APP_ENV:-dev}"
SKIP_INSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --env)  APP_ENV="$2"; shift 2 ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--repo PATH] [--port 8000] [--env dev|stage|prod] [--skip-install]"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Resolve repo that contains fastapi-for-ai/main.py
if [[ -z "$REPO_DIR" ]]; then
  # 1) sibling / parent common layouts
  for candidate in \
    "$SCRIPT_DIR/../fastapi-for-ai" \
    "$SCRIPT_DIR/../../fastapi-for-ai" \
    "$HOME/fastapi-for-ai" \
    "$HOME/Documents/fastapi-for-ai" \
    "$HOME/Desktop/fastapi-for-ai" \
    "$HOME/Projects/fastapi-for-ai" \
    "$HOME/Developer/fastapi-for-ai"
  do
    if [[ -f "$candidate/fastapi-for-ai/main.py" ]]; then
      REPO_DIR="$candidate"
      break
    fi
    if [[ -f "$candidate/main.py" && -f "$candidate/requirements.txt" ]]; then
      # user opened the inner folder as repo
      REPO_DIR="$(cd "$candidate/.." && pwd)"
      break
    fi
  done
fi

if [[ -z "${REPO_DIR}" || ! -d "$REPO_DIR" ]]; then
  echo "ERROR: Could not find GitHub repo folder."
  echo "Clone it, then pass the path:"
  echo "  git clone https://github.com/mohd14shoeb/fastapi-for-ai.git"
  echo "  $0 --repo \$HOME/fastapi-for-ai"
  exit 1
fi

APP_DIR="$REPO_DIR/fastapi-for-ai"
if [[ ! -f "$APP_DIR/main.py" ]]; then
  echo "ERROR: main.py not found at $APP_DIR"
  echo "Expected layout:"
  echo "  fastapi-for-ai/                 ← git root"
  echo "    fastapi-for-ai/main.py        ← app"
  exit 1
fi

echo "============================================"
echo " Local CI smoke (same idea as Jenkins)"
echo " Repo   : $REPO_DIR"
echo " App    : $APP_DIR"
echo " APP_ENV: $APP_ENV"
echo " Port   : $PORT"
echo "============================================"

export PORT
export APP_ENV
export APP_DIR
export SECRET_KEY="${SECRET_KEY:-ci-${APP_ENV}-secret-key}"
export ALGORITHM="${ALGORITHM:-HS256}"
export ACCESS_TOKEN_EXPIRE_MINUTES="${ACCESS_TOKEN_EXPIRE_MINUTES:-30}"
export DATABASE_URL="${DATABASE_URL:-sqlite:///./users_ci.db}"
export allowed_origins="${allowed_origins:-http://localhost,http://127.0.0.1}"
export CRAWLING_URL="${CRAWLING_URL:-https://news.ycombinator.com/}"

# Reuse full smoke script if present (expects to cd into APP_DIR via APP_DIR env)
if [[ -f "$SCRIPT_DIR/smoke-test.sh" ]]; then
  chmod +x "$SCRIPT_DIR/smoke-test.sh"
  # smoke-test.sh does: cd "$APP_DIR" relative to CWD — run from repo root
  cd "$REPO_DIR"
  APP_DIR="fastapi-for-ai" PORT="$PORT" bash "$SCRIPT_DIR/smoke-test.sh"
  exit $?
fi

echo "smoke-test.sh missing — cannot continue"
exit 1
