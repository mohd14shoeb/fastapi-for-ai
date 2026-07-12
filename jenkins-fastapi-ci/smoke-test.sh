#!/usr/bin/env bash
# Jenkins smoke test for fastapi-for-ai
# Flow: install deps → start API → check endpoints → always stop server
set -euo pipefail

APP_DIR="${APP_DIR:-fastapi-for-ai}"
HOST="127.0.0.1"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"
VENV_DIR=".venv-ci"
PID_FILE=".uvicorn-ci.pid"
LOG_FILE="uvicorn-ci.log"
MAX_WAIT_SECS="${MAX_WAIT_SECS:-60}"

# ---------- helpers ----------
log() { echo "[$(date '+%H:%M:%S')] $*"; }

cleanup() {
  local exit_code=$?
  log "Cleanup: stopping API server (if running)..."
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # give it a moment, then force-kill if needed
      for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
      done
      kill -9 "$pid" 2>/dev/null || true
      log "Stopped uvicorn (pid=$pid)"
    fi
    rm -f "$PID_FILE"
  fi
  # safety: anything still bound to our port
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids="$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "${pids:-}" ]]; then
      log "Killing leftover listeners on :$PORT → $pids"
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
      sleep 0.5
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
    fi
  fi
  if [[ $exit_code -ne 0 ]]; then
    log "FAILED (exit=$exit_code). Last 80 lines of server log:"
    [[ -f "$LOG_FILE" ]] && tail -n 80 "$LOG_FILE" || true
  else
    log "SUCCESS — all API checks passed; server stopped."
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

http_code() {
  # usage: http_code METHOD URL [curl-extra-args...]
  local method="$1" url="$2"
  shift 2
  curl -sS -o /tmp/ci_body.json -w "%{http_code}" -X "$method" "$url" "$@"
}

assert_status() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    log "FAIL: $name — expected HTTP $expected, got $actual"
    log "Body: $(cat /tmp/ci_body.json 2>/dev/null || true)"
    return 1
  fi
  log "OK:   $name → HTTP $actual"
}

wait_for_server() {
  local i=0
  log "Waiting for server at $BASE_URL (max ${MAX_WAIT_SECS}s)..."
  while (( i < MAX_WAIT_SECS )); do
    if curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/openapi.json" 2>/dev/null | grep -qE '200|401|403'; then
      log "Server is up."
      return 0
    fi
    # also fail fast if process died
    if [[ -f "$PID_FILE" ]]; then
      local pid
      pid="$(cat "$PID_FILE")"
      if ! kill -0 "$pid" 2>/dev/null; then
        log "Server process exited early. Log:"
        cat "$LOG_FILE" || true
        return 1
      fi
    fi
    sleep 1
    i=$((i + 1))
  done
  log "Timed out waiting for server."
  [[ -f "$LOG_FILE" ]] && cat "$LOG_FILE" || true
  return 1
}

# ---------- main ----------
cd "$APP_DIR"
log "Working directory: $(pwd)"

# Prefer python3
PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null || { log "python3 not found"; exit 1; }
command -v curl >/dev/null || { log "curl not found"; exit 1; }

log "Creating virtualenv..."
"$PYTHON" -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip -q
log "Installing requirements..."
pip install -r requirements.txt -q

# CI-friendly env (no secrets required for smoke tests)
export SECRET_KEY="${SECRET_KEY:-ci-smoke-test-secret-key}"
export ALGORITHM="${ALGORITHM:-HS256}"
export ACCESS_TOKEN_EXPIRE_MINUTES="${ACCESS_TOKEN_EXPIRE_MINUTES:-30}"
export DATABASE_URL="${DATABASE_URL:-sqlite:///./users_ci.db}"
export allowed_origins="${allowed_origins:-http://localhost,http://127.0.0.1}"
# webcrawl needs a URL; use a public page so the endpoint can be exercised
export CRAWLING_URL="${CRAWLING_URL:-https://news.ycombinator.com/}"

# free the port if a previous run left something behind
if command -v lsof >/dev/null 2>&1; then
  old="$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "${old:-}" ]]; then
    log "Port $PORT busy (pids: $old) — killing"
    # shellcheck disable=SC2086
    kill $old 2>/dev/null || true
    sleep 1
  fi
fi

log "Starting uvicorn on $BASE_URL ..."
# main:app because main.py is at fastapi-for-ai/main.py
nohup uvicorn main:app --host "$HOST" --port "$PORT" --log-level info \
  >"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
log "uvicorn pid=$(cat "$PID_FILE")"

wait_for_server

log "========== API smoke tests =========="

# 1) OpenAPI / docs always present for FastAPI
code="$(http_code GET "$BASE_URL/openapi.json")"
assert_status "GET /openapi.json" "200" "$code"

code="$(http_code GET "$BASE_URL/docs")"
assert_status "GET /docs (Swagger UI)" "200" "$code"

# 2) Users list (public GET; may be empty list)
code="$(http_code GET "$BASE_URL/users")"
assert_status "GET /users" "200" "$code"

# 3) Create a unique user (matches UserCreate schema), then login, then protected route
UNIQUE="ci_user_$(date +%s)_$RANDOM"
EMAIL="${UNIQUE}@example.com"
PASSWORD="CiTestPass123!"
# UserCreate: name, age, email, role, address{street,city,state,zip_code}, password
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

code="$(http_code POST "$BASE_URL/users" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON")"
if [[ "$code" == "200" || "$code" == "201" ]]; then
  log "OK:   POST /users → HTTP $code"
  CREATED=1
else
  log "FAIL: could not create user (HTTP $code)."
  log "Body: $(cat /tmp/ci_body.json)"
  exit 1
fi

if [[ "$CREATED" -eq 1 ]]; then
  # OAuth2 password form login
  code="$(http_code POST "$BASE_URL/users/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${EMAIL}&password=${PASSWORD}")"
  assert_status "POST /users/login" "200" "$code"

  TOKEN="$(python -c "import json; print(json.load(open('/tmp/ci_body.json')).get('access_token',''))")"
  if [[ -z "$TOKEN" ]]; then
    log "FAIL: login response missing access_token"
    cat /tmp/ci_body.json
    exit 1
  fi
  log "OK:   received JWT access_token"

  code="$(http_code GET "$BASE_URL/users/protected" \
    -H "Authorization: Bearer $TOKEN")"
  assert_status "GET /users/protected (with JWT)" "200" "$code"

  # protected without token should fail
  code="$(http_code GET "$BASE_URL/users/protected")"
  if [[ "$code" == "401" || "$code" == "403" ]]; then
    log "OK:   GET /users/protected (no token) → HTTP $code (expected unauthorized)"
  else
    log "FAIL: unauthenticated /users/protected expected 401/403, got $code"
    exit 1
  fi
fi

# 4) Unknown user → 404
code="$(http_code GET "$BASE_URL/users/99999999")"
assert_status "GET /users/99999999 (not found)" "404" "$code"

# 5) File download missing file → 404
code="$(http_code GET "$BASE_URL/files/download/does-not-exist-ci.txt")"
assert_status "GET /files/download/... (missing)" "404" "$code"

# 6) Web crawl (optional — needs network + CRAWLING_URL)
code="$(http_code GET "$BASE_URL/webcrawl/news?page=1&limit=2")"
if [[ "$code" == "200" ]]; then
  log "OK:   GET /webcrawl/news → HTTP 200"
else
  # network may be blocked in some CI environments; don't hard-fail the whole job
  log "WARN: GET /webcrawl/news → HTTP $code (non-fatal if offline). Body: $(cat /tmp/ci_body.json)"
fi

log "========== All required checks passed =========="
# trap cleanup will stop the server and exit 0
exit 0
