#!/bin/bash
# ============================================================
# PASTE THIS ENTIRE FILE into Jenkins → Configure → Execute shell
# Do NOT paste diagram lines that use → arrows
# ============================================================
set -euo pipefail

APP_DIR="fastapi-for-ai"
HOST="127.0.0.1"
PORT="8000"
BASE_URL="http://${HOST}:${PORT}"
VENV_DIR=".venv-ci"
PID_FILE=".uvicorn-ci.pid"
LOG_FILE="uvicorn-ci.log"
MAX_WAIT=60

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cleanup() {
  EXIT_CODE=$?
  log "Cleanup: stopping API server..."
  if [ -f "$APP_DIR/$PID_FILE" ]; then
    PID=$(cat "$APP_DIR/$PID_FILE" 2>/dev/null || true)
    if [ -n "${PID:-}" ]; then
      kill "$PID" 2>/dev/null || true
      sleep 1
      kill -9 "$PID" 2>/dev/null || true
      log "Stopped uvicorn pid=$PID"
    fi
    rm -f "$APP_DIR/$PID_FILE"
  fi
  if command -v lsof >/dev/null 2>&1; then
    EXTRA=$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "${EXTRA:-}" ]; then
      log "Killing leftover on :$PORT → $EXTRA"
      kill $EXTRA 2>/dev/null || true
      sleep 0.5
      kill -9 $EXTRA 2>/dev/null || true
    fi
  fi
  if [ "$EXIT_CODE" -ne 0 ]; then
    log "BUILD FAILED (exit=$EXIT_CODE). Server log (last 80 lines):"
    [ -f "$APP_DIR/$LOG_FILE" ] && tail -n 80 "$APP_DIR/$LOG_FILE" || true
  else
    log "SUCCESS — all API checks passed; server stopped."
  fi
  exit "$EXIT_CODE"
}
trap cleanup EXIT INT TERM

http_code() {
  METHOD="$1"
  URL="$2"
  shift 2
  curl -sS -o /tmp/ci_body.json -w "%{http_code}" -X "$METHOD" "$URL" "$@" || echo "000"
}

assert_eq() {
  NAME="$1"
  EXPECTED="$2"
  ACTUAL="$3"
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    log "FAIL: $NAME — expected HTTP $EXPECTED, got $ACTUAL"
    log "Body: $(cat /tmp/ci_body.json 2>/dev/null || true)"
    exit 1
  fi
  log "OK:   $NAME → HTTP $ACTUAL"
}

# ---------- enter app directory ----------
if [ ! -d "$APP_DIR" ]; then
  log "ERROR: folder '$APP_DIR' not found in workspace."
  log "Workspace contents:"; ls -la
  exit 1
fi
cd "$APP_DIR"
log "Workspace app dir: $(pwd)"

command -v python3 >/dev/null || { log "python3 not found"; exit 1; }
command -v curl >/dev/null || { log "curl not found"; exit 1; }

# ---------- venv + deps (SEPARATE commands — no arrows) ----------
log "Creating virtualenv..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
python -m pip install -q --upgrade pip
log "Installing requirements.txt ..."
pip install -q -r requirements.txt

# ---------- env for the app ----------
export SECRET_KEY="ci-smoke-test-secret-key"
export ALGORITHM="HS256"
export ACCESS_TOKEN_EXPIRE_MINUTES="30"
export DATABASE_URL="sqlite:///./users_ci.db"
export allowed_origins="http://localhost,http://127.0.0.1"
export CRAWLING_URL="https://news.ycombinator.com/"

# free port if busy
if command -v lsof >/dev/null 2>&1; then
  OLD=$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "${OLD:-}" ]; then
    log "Port $PORT busy ($OLD) — killing"
    kill $OLD 2>/dev/null || true
    sleep 1
  fi
fi

# ---------- start server ----------
log "Starting uvicorn on $BASE_URL ..."
nohup uvicorn main:app --host "$HOST" --port "$PORT" --log-level info \
  >"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
log "uvicorn pid=$(cat "$PID_FILE")"

log "Waiting for server (max ${MAX_WAIT}s)..."
i=0
while [ "$i" -lt "$MAX_WAIT" ]; do
  CODE=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/openapi.json" 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ]; then
    log "Server is UP"
    break
  fi
  if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "Server process died. Log:"
    cat "$LOG_FILE"
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$i" -ge "$MAX_WAIT" ]; then
  log "Timeout waiting for server. Log:"
  cat "$LOG_FILE"
  exit 1
fi

# ---------- smoke tests ----------
log "========== API smoke tests =========="

CODE=$(http_code GET "$BASE_URL/openapi.json")
assert_eq "GET /openapi.json" "200" "$CODE"

CODE=$(http_code GET "$BASE_URL/docs")
assert_eq "GET /docs" "200" "$CODE"

CODE=$(http_code GET "$BASE_URL/users")
assert_eq "GET /users" "200" "$CODE"

UNIQUE="ci_user_$(date +%s)_$RANDOM"
EMAIL="${UNIQUE}@example.com"
PASSWORD="CiTestPass123!"
USER_JSON=$(cat <<EOF
{
  "name": "$UNIQUE",
  "age": 28,
  "email": "$EMAIL",
  "role": "user",
  "password": "$PASSWORD",
  "address": {
    "street": "1 CI Street",
    "city": "Mumbai",
    "state": "MH",
    "zip_code": "400001"
  }
}
EOF
)

CODE=$(http_code POST "$BASE_URL/users" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON")
if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  log "FAIL: POST /users expected 200/201, got $CODE"
  log "Body: $(cat /tmp/ci_body.json)"
  exit 1
fi
log "OK:   POST /users → HTTP $CODE"

CODE=$(http_code POST "$BASE_URL/users/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${EMAIL}&password=${PASSWORD}")
assert_eq "POST /users/login" "200" "$CODE"

TOKEN=$(python -c "import json; print(json.load(open('/tmp/ci_body.json')).get('access_token',''))")
if [ -z "$TOKEN" ]; then
  log "FAIL: no access_token in login response"
  cat /tmp/ci_body.json
  exit 1
fi
log "OK:   got JWT access_token"

CODE=$(http_code GET "$BASE_URL/users/protected" \
  -H "Authorization: Bearer $TOKEN")
assert_eq "GET /users/protected (JWT)" "200" "$CODE"

CODE=$(http_code GET "$BASE_URL/users/protected")
if [ "$CODE" = "401" ] || [ "$CODE" = "403" ]; then
  log "OK:   GET /users/protected (no token) → HTTP $CODE"
else
  log "FAIL: expected 401/403 without token, got $CODE"
  exit 1
fi

CODE=$(http_code GET "$BASE_URL/users/99999999")
assert_eq "GET /users/99999999" "404" "$CODE"

CODE=$(http_code GET "$BASE_URL/files/download/does-not-exist-ci.txt")
assert_eq "GET /files/download/missing" "404" "$CODE"

CODE=$(http_code GET "$BASE_URL/webcrawl/news?page=1&limit=2")
if [ "$CODE" = "200" ]; then
  log "OK:   GET /webcrawl/news → 200"
else
  log "WARN: GET /webcrawl/news → $CODE (non-fatal)"
fi

log "========== All required checks passed =========="
exit 0
