#!/usr/bin/env bash
# =============================================================================
#  devpods — local dev infrastructure via Podman pods
#  Gist: https://gist.github.com/<you>/devpods.sh
#
#  Usage (one-liner):
#    curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash
#    curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash -s -- up pg
#    curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash -s -- down all
#    curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash -s -- status
#    curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash -s -- reset mongo
#
#  Subcommands:  up [pod|all]   down [pod|all]   status   reset [pod|all]
#  Pod aliases:  pg  mongo  redis  mail  seq  rmq  nats  (or "all")
#
#  Data lives in: ~/.devpods/<pod-name>/
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ─── version ─────────────────────────────────────────────────────────────────
DEVPODS_VERSION="1.0.0"

# ─── colour palette ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RED='\033[0;31m'    C_GRN='\033[0;32m'    C_YLW='\033[1;33m'
  C_BLU='\033[0;34m'    C_CYN='\033[0;36m'    C_MAG='\033[0;35m'
  C_GRY='\033[0;90m'    C_WHT='\033[1;37m'     C_RST='\033[0m'
  C_BLD='\033[1m'
else
  C_RED='' C_GRN='' C_YLW='' C_BLU='' C_CYN='' C_MAG='' C_GRY='' C_WHT='' C_RST='' C_BLD=''
fi

# ─── logging helpers ─────────────────────────────────────────────────────────
banner() { echo -e "\n${C_BLD}${C_CYN}╔══════════════════════════════════════════╗${C_RST}"; \
           printf "${C_BLD}${C_CYN}║${C_RST}  %-42s${C_BLD}${C_CYN}║${C_RST}\n" "$*"; \
           echo -e "${C_BLD}${C_CYN}╚══════════════════════════════════════════╝${C_RST}"; }
info()   { echo -e "  ${C_BLU}→${C_RST}  $*"; }
ok()     { echo -e "  ${C_GRN}✔${C_RST}  $*"; }
warn()   { echo -e "  ${C_YLW}⚠${C_RST}  $*"; }
err()    { echo -e "  ${C_RED}✖${C_RST}  $*" >&2; }
die()    { err "$*"; exit 1; }
section(){ echo -e "\n${C_MAG}▸ $*${C_RST}"; }
dim()    { echo -e "  ${C_GRY}$*${C_RST}"; }

# ─── data root ───────────────────────────────────────────────────────────────
DATA_ROOT="${HOME}/.devpods"

# ─── pod definitions (name => port mappings) ─────────────────────────────────
# Format: "host:container ..."
declare -A POD_PORTS=(
  [dev-pg-pod]="5432:5432 8081:8081"
  [dev-mongo-pod]="27017:27017 8082:8081"
  [dev-redis-pod]="6379:6379 8083:8081"
  [dev-mail-pod]="1025:1025 8025:8025"
  [dev-seq-pod]="5341:80"
  [dev-rmq-pod]="5672:5672 15672:15672"
  [dev-nats-pod]="4222:4222 8222:8222 6222:6222"
)

# alias → pod name
declare -A ALIAS_MAP=(
  [pg]=dev-pg-pod   [postgres]=dev-pg-pod
  [mongo]=dev-mongo-pod  [mongodb]=dev-mongo-pod
  [redis]=dev-redis-pod
  [mail]=dev-mail-pod    [mailpit]=dev-mail-pod
  [seq]=dev-seq-pod
  [rmq]=dev-rmq-pod      [rabbitmq]=dev-rmq-pod
  [nats]=dev-nats-pod
)

ALL_PODS=(dev-pg-pod dev-mongo-pod dev-redis-pod dev-mail-pod dev-seq-pod dev-rmq-pod dev-nats-pod)

# ─── env / credentials (override via ~/.devpods/.env) ────────────────────────
_load_env() {
  [[ -f "${DATA_ROOT}/.env" ]] && source "${DATA_ROOT}/.env"
  PG_USER="${PG_USER:-devuser}"
  PG_PASS="${PG_PASS:-devpass}"
  PG_DB="${PG_DB:-devdb}"
  REDIS_PASS="${REDIS_PASS:-devredis}"
  RMQ_USER="${RMQ_USER:-devuser}"
  RMQ_PASS="${RMQ_PASS:-devpass}"
  MONGO_RS="${MONGO_RS:-rs0}"
  ME_USER="${ME_USER:-admin}"
  ME_PASS="${ME_PASS:-admin}"
}

# ─── system readiness checks ──────────────────────────────────────────────────
_check_system() {
  section "System readiness"

  # OS detection
  local os; os="$(uname -s)"
  case "${os}" in
    Linux)  ok "OS: Linux" ;;
    Darwin) ok "OS: macOS" ;;
    *)      die "Unsupported OS: ${os}" ;;
  esac

  # macOS: podman machine must be running
  if [[ "${os}" == "Darwin" ]]; then
    if ! podman machine list 2>/dev/null | grep -q "Currently running"; then
      warn "No running Podman machine found — attempting to start …"
      if podman machine list 2>/dev/null | grep -q "dev\|podman-machine-default"; then
        podman machine start 2>/dev/null || die "Failed to start Podman machine. Run: podman machine init && podman machine start"
        ok "Podman machine started."
      else
        warn "No Podman machine exists. Initialising a default one …"
        podman machine init --cpus 4 --memory 4096 --disk-size 60 2>/dev/null \
          && podman machine start \
          || die "Could not init/start Podman machine. Please run it manually."
        ok "Podman machine initialised and started."
      fi
    else
      ok "Podman machine: running"
    fi
  fi

  # Podman binary
  if ! command -v podman &>/dev/null; then
    die "Podman not found. Install it: https://podman.io/docs/installation"
  fi

  local pv; pv="$(podman --version | awk '{print $3}')"
  local pmaj; pmaj="$(echo "${pv}" | cut -d. -f1)"
  if [[ "${pmaj}" -lt 4 ]]; then
    die "Podman >= 4.0 required (found ${pv}). Please upgrade."
  fi
  ok "Podman ${pv}"

  # socket / service (Linux rootless)
  if [[ "${os}" == "Linux" ]]; then
    if ! podman info &>/dev/null; then
      warn "Podman socket not responding — trying to start user service …"
      systemctl --user start podman.socket 2>/dev/null \
        || warn "Could not start podman.socket (may not be needed on this distro)."
    fi
    ok "Podman daemon: responding"
  fi

  # Data root
  mkdir -p "${DATA_ROOT}"
  ok "Data root: ${DATA_ROOT}"

  # Write sample .env if missing
  if [[ ! -f "${DATA_ROOT}/.env" ]]; then
    cat > "${DATA_ROOT}/.env" <<'ENV'
# devpods credentials — edit freely
PG_USER=devuser
PG_PASS=devpass
PG_DB=devdb
REDIS_PASS=devredis
RMQ_USER=devuser
RMQ_PASS=devpass
MONGO_RS=rs0
ME_USER=admin
ME_PASS=admin
ENV
    ok "Created ${DATA_ROOT}/.env (defaults)"
  fi
}

# ─── pod lifecycle helpers ────────────────────────────────────────────────────
_pod_exists()   { podman pod exists "$1" 2>/dev/null; }
_pod_running()  { [[ "$(podman pod inspect "$1" --format '{{.State}}' 2>/dev/null)" == "Running" ]]; }

_ensure_pod() {
  local pod="$1"; shift
  local ports=("$@")
  if _pod_exists "${pod}"; then
    if _pod_running "${pod}"; then
      warn "Pod ${C_BLD}${pod}${C_RST}${C_YLW} already running — skipping creation."; return 0
    else
      info "Pod ${pod} exists but is not running — removing stale pod …"
      podman pod rm -f "${pod}" >/dev/null 2>&1
    fi
  fi
  local pub_args=()
  for p in "${ports[@]}"; do pub_args+=("--publish" "${p}"); done
  podman pod create --name "${pod}" "${pub_args[@]}" >/dev/null
}

_wait_healthy() {
  local container="$1" retries="${2:-30}" delay="${3:-2}"
  local i=0
  while (( i < retries )); do
    local state; state="$(podman inspect --format '{{.State.Health.Status}}' "${container}" 2>/dev/null || true)"
    [[ "${state}" == "healthy" ]] && return 0
    # fallback: just check running
    state="$(podman inspect --format '{{.State.Status}}' "${container}" 2>/dev/null || true)"
    [[ "${state}" == "running" ]] && return 0
    sleep "${delay}"; (( i++ ))
  done
  warn "Container ${container} did not become healthy in time — continuing anyway."
}

_stop_pod() {
  local pod="$1"
  if _pod_exists "${pod}"; then
    info "Stopping pod ${C_BLD}${pod}${C_RST} …"
    podman pod stop "${pod}" >/dev/null 2>&1 || true
    podman pod rm   "${pod}" >/dev/null 2>&1 || true
    ok "Removed ${pod}"
  else
    dim "Pod ${pod} not found — nothing to do."
  fi
}

_reset_pod() {
  local pod="$1"
  local data_dir="${DATA_ROOT}/${pod}"
  _stop_pod "${pod}"
  if [[ -d "${data_dir}" ]]; then
    warn "Deleting data at ${data_dir} …"
    rm -rf "${data_dir}"
    ok "Data cleared for ${pod}"
  fi
}

# ─── pod launchers ────────────────────────────────────────────────────────────

_up_pg() {
  section "dev-pg-pod  (PostgreSQL 16 + pgweb)"
  local pod="dev-pg-pod"
  local data="${DATA_ROOT}/${pod}"
  mkdir -p "${data}/postgres"

  _ensure_pod "${pod}" "5432:5432" "8081:8081"

  # PostgreSQL
  if ! podman container exists "${pod}-postgres" 2>/dev/null; then
    info "Starting PostgreSQL …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-postgres" \
      --health-cmd "pg_isready -U ${PG_USER}" \
      --health-interval 5s \
      --health-retries 10 \
      -e POSTGRES_USER="${PG_USER}" \
      -e POSTGRES_PASSWORD="${PG_PASS}" \
      -e POSTGRES_DB="${PG_DB}" \
      -v "${data}/postgres:/var/lib/postgresql/data:Z" \
      docker.io/library/postgres:16-alpine >/dev/null
    ok "PostgreSQL container started."
  else
    dim "PostgreSQL container already exists."
  fi

  _wait_healthy "${pod}-postgres"

  # pgweb
  if ! podman container exists "${pod}-pgweb" 2>/dev/null; then
    info "Starting pgweb …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-pgweb" \
      -e DATABASE_URL="postgres://${PG_USER}:${PG_PASS}@localhost:5432/${PG_DB}?sslmode=disable" \
      docker.io/sosedoff/pgweb:latest >/dev/null
    ok "pgweb started → http://localhost:8081"
  else
    dim "pgweb container already exists."
  fi
}

_up_mongo() {
  section "dev-mongo-pod  (MongoDB 7 RS + mongo-express)"
  local pod="dev-mongo-pod"
  local data="${DATA_ROOT}/${pod}"
  mkdir -p "${data}/mongodb"

  _ensure_pod "${pod}" "27017:27017" "8082:8081"

  # MongoDB
  if ! podman container exists "${pod}-mongodb" 2>/dev/null; then
    info "Starting MongoDB …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-mongodb" \
      --health-cmd "mongosh --quiet --eval \"db.adminCommand('ping').ok\" | grep -q 1" \
      --health-interval 5s \
      --health-retries 15 \
      -v "${data}/mongodb:/data/db:Z" \
      docker.io/library/mongo:7 \
      --replSet "${MONGO_RS}" --bind_ip_all >/dev/null
    ok "MongoDB container started."
  else
    dim "MongoDB container already exists."
  fi

  # Wait then initiate RS
  info "Waiting for MongoDB to be ready …"
  local attempts=0
  until podman exec "${pod}-mongodb" mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
    sleep 2; (( attempts++ ))
    (( attempts > 30 )) && die "MongoDB did not become ready in time."
  done

  podman exec "${pod}-mongodb" mongosh --quiet --eval "
    try { rs.status(); print('RS already initialised'); }
    catch(e) {
      rs.initiate({ _id: '${MONGO_RS}', members: [{ _id: 0, host: 'localhost:27017' }] });
      print('RS initiated');
    }
  " >/dev/null 2>&1 && ok "Replica set: ${MONGO_RS}" || warn "RS init non-zero (may already be set)"

  # mongo-express
  if ! podman container exists "${pod}-mongoexpress" 2>/dev/null; then
    info "Starting mongo-express …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-mongoexpress" \
      -e ME_CONFIG_MONGODB_URL="mongodb://localhost:27017/?replicaSet=${MONGO_RS}" \
      -e ME_CONFIG_BASICAUTH_USERNAME="${ME_USER}" \
      -e ME_CONFIG_BASICAUTH_PASSWORD="${ME_PASS}" \
      -e ME_CONFIG_MONGODB_ENABLE_ADMIN=true \
      -e ME_CONFIG_OPTIONS_EDITORTHEME="dracula" \
      docker.io/library/mongo-express:latest >/dev/null
    ok "mongo-express started → http://localhost:8082  (${ME_USER}/${ME_PASS})"
  else
    dim "mongo-express container already exists."
  fi
}

_up_redis() {
  section "dev-redis-pod  (Redis 7 + RedisInsight)"
  local pod="dev-redis-pod"
  local data="${DATA_ROOT}/${pod}"
  mkdir -p "${data}/redis" "${data}/redisinsight"

  _ensure_pod "${pod}" "6379:6379" "8083:8001"

  # Redis
  if ! podman container exists "${pod}-redis" 2>/dev/null; then
    info "Starting Redis …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-redis" \
      --health-cmd "redis-cli -a ${REDIS_PASS} ping | grep -q PONG" \
      --health-interval 5s \
      -v "${data}/redis:/data:Z" \
      docker.io/library/redis:7-alpine \
      redis-server --requirepass "${REDIS_PASS}" --appendonly yes >/dev/null
    ok "Redis started."
  else
    dim "Redis container already exists."
  fi

  # RedisInsight
  if ! podman container exists "${pod}-redisinsight" 2>/dev/null; then
    info "Starting RedisInsight …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-redisinsight" \
      -v "${data}/redisinsight:/data:Z" \
      docker.io/redis/redisinsight:latest >/dev/null
    ok "RedisInsight started → http://localhost:8083"
  else
    dim "RedisInsight container already exists."
  fi
}

_up_mail() {
  section "dev-mail-pod  (Mailpit)"
  local pod="dev-mail-pod"

  _ensure_pod "${pod}" "1025:1025" "8025:8025"

  if ! podman container exists "${pod}-mailpit" 2>/dev/null; then
    info "Starting Mailpit …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-mailpit" \
      docker.io/axllent/mailpit:latest >/dev/null
    ok "Mailpit started → SMTP: localhost:1025  UI: http://localhost:8025"
  else
    dim "Mailpit container already exists."
  fi
}

_up_seq() {
  section "dev-seq-pod  (Seq)"
  local pod="dev-seq-pod"
  local data="${DATA_ROOT}/${pod}"
  mkdir -p "${data}/seq"

  _ensure_pod "${pod}" "5341:80"

  if ! podman container exists "${pod}-seq" 2>/dev/null; then
    info "Starting Seq …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-seq" \
      -e ACCEPT_EULA=Y \
      -v "${data}/seq:/data:Z" \
      docker.io/datalust/seq:latest >/dev/null
    ok "Seq started → http://localhost:5341"
  else
    dim "Seq container already exists."
  fi
}

_up_rmq() {
  section "dev-rmq-pod  (RabbitMQ 3)"
  local pod="dev-rmq-pod"
  local data="${DATA_ROOT}/${pod}"
  mkdir -p "${data}/rabbitmq"

  _ensure_pod "${pod}" "5672:5672" "15672:15672"

  if ! podman container exists "${pod}-rabbitmq" 2>/dev/null; then
    info "Starting RabbitMQ …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-rabbitmq" \
      --health-cmd "rabbitmq-diagnostics -q ping" \
      --health-interval 10s \
      --health-retries 10 \
      -e RABBITMQ_DEFAULT_USER="${RMQ_USER}" \
      -e RABBITMQ_DEFAULT_PASS="${RMQ_PASS}" \
      -v "${data}/rabbitmq:/var/lib/rabbitmq:Z" \
      docker.io/library/rabbitmq:3-management-alpine >/dev/null
    ok "RabbitMQ started → AMQP: localhost:5672  UI: http://localhost:15672  (${RMQ_USER}/${RMQ_PASS})"
  else
    dim "RabbitMQ container already exists."
  fi
}

_up_nats() {
  section "dev-nats-pod  (NATS 2 + JetStream)"
  local pod="dev-nats-pod"
  local data="${DATA_ROOT}/${pod}"
  mkdir -p "${data}/nats"

  _ensure_pod "${pod}" "4222:4222" "8222:8222" "6222:6222"

  # Write NATS config inline
  local nats_conf="${data}/nats/server.conf"
  cat > "${nats_conf}" <<'NATSCONF'
port:      4222
http_port: 8222

jetstream {
  store_dir:        /data
  max_memory_store: 512mb
  max_file_store:   4gb
}

debug: false
logtime: true
NATSCONF

  if ! podman container exists "${pod}-nats" 2>/dev/null; then
    info "Starting NATS …"
    podman run -d \
      --pod "${pod}" \
      --name "${pod}-nats" \
      -v "${data}/nats:/data:Z" \
      docker.io/library/nats:2-alpine \
      -c /data/server.conf >/dev/null
    ok "NATS started → nats://localhost:4222  Monitor: http://localhost:8222"
  else
    dim "NATS container already exists."
  fi
}

# ─── pod name resolver ────────────────────────────────────────────────────────
_resolve_pods() {
  local input="$1"
  if [[ "${input}" == "all" ]]; then
    echo "${ALL_PODS[@]}"
    return
  fi
  local resolved="${ALIAS_MAP[${input}]:-}"
  [[ -z "${resolved}" ]] && die "Unknown pod alias '${input}'. Valid: ${!ALIAS_MAP[*]} all"
  echo "${resolved}"
}

_launch_pod() {
  local pod="$1"
  case "${pod}" in
    dev-pg-pod)    _up_pg    ;;
    dev-mongo-pod) _up_mongo ;;
    dev-redis-pod) _up_redis ;;
    dev-mail-pod)  _up_mail  ;;
    dev-seq-pod)   _up_seq   ;;
    dev-rmq-pod)   _up_rmq   ;;
    dev-nats-pod)  _up_nats  ;;
    *) die "No launcher for pod '${pod}'" ;;
  esac
}

# ─── status table ─────────────────────────────────────────────────────────────
_status() {
  section "devpods status"
  printf "\n  ${C_BLD}%-20s %-12s %s${C_RST}\n" "POD" "STATE" "ENDPOINTS"
  printf "  %s\n" "──────────────────────────────────────────────────────────────────"

  declare -A ENDPOINTS=(
    [dev-pg-pod]="postgres://localhost:5432  pgweb→http://localhost:8081"
    [dev-mongo-pod]="mongodb://localhost:27017/?replicaSet=${MONGO_RS}  mongo-express→http://localhost:8082"
    [dev-redis-pod]="redis://localhost:6379  RedisInsight→http://localhost:8083"
    [dev-mail-pod]="SMTP→localhost:1025  UI→http://localhost:8025"
    [dev-seq-pod]="http://localhost:5341"
    [dev-rmq-pod]="amqp://localhost:5672  UI→http://localhost:15672"
    [dev-nats-pod]="nats://localhost:4222  monitor→http://localhost:8222"
  )

  for pod in "${ALL_PODS[@]}"; do
    local state="stopped"
    local colour="${C_RED}"
    if _pod_exists "${pod}"; then
      if _pod_running "${pod}"; then
        state="running"; colour="${C_GRN}"
      else
        state="degraded"; colour="${C_YLW}"
      fi
    fi
    printf "  ${C_BLD}%-20s${C_RST} ${colour}%-12s${C_RST} ${C_GRY}%s${C_RST}\n" \
      "${pod}" "${state}" "${ENDPOINTS[${pod}]}"
  done
  echo ""
}

# ─── usage ────────────────────────────────────────────────────────────────────
_usage() {
  cat <<EOF

${C_BLD}${C_CYN}devpods${C_RST} v${DEVPODS_VERSION} — local dev infrastructure via Podman pods

${C_BLD}Usage:${C_RST}
  devpods [command] [pod|all]

${C_BLD}Commands:${C_RST}
  up     [pod|all]    Start pod(s)              (default: all)
  down   [pod|all]    Stop and remove pod(s)
  reset  [pod|all]    Stop + wipe data for pod(s)
  status              Show state of all pods
  help                This message

${C_BLD}Pod aliases:${C_RST}
  pg       → dev-pg-pod      (PostgreSQL + pgweb)
  mongo    → dev-mongo-pod   (MongoDB RS + mongo-express)
  redis    → dev-redis-pod   (Redis + RedisInsight)
  mail     → dev-mail-pod    (Mailpit)
  seq      → dev-seq-pod     (Seq)
  rmq      → dev-rmq-pod     (RabbitMQ)
  nats     → dev-nats-pod    (NATS + JetStream)

${C_BLD}One-liner (curl | bash):${C_RST}
  curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash
  curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash -s -- up pg
  curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash -s -- down all
  curl -fsSL https://gist.githubusercontent.com/<you>/devpods.sh/raw | bash -s -- status

${C_BLD}Data root:${C_RST} ~/.devpods/
${C_BLD}Credentials:${C_RST} ~/.devpods/.env  (auto-created with defaults on first run)

EOF
}

# ─── summary card ─────────────────────────────────────────────────────────────
_summary() {
  echo -e "\n${C_BLD}${C_CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RST}"
  echo -e "${C_BLD}  devpods — Connection Cheatsheet${C_RST}"
  echo -e "${C_BLD}${C_CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RST}"
  printf "  ${C_BLD}%-14s${C_RST} %s\n" "PostgreSQL"  "postgresql://${PG_USER}:${PG_PASS}@localhost:5432/${PG_DB}"
  printf "  ${C_GRY}%-14s${C_RST} ${C_GRY}%s${C_RST}\n" "pgweb"       "http://localhost:8081"
  printf "  ${C_BLD}%-14s${C_RST} %s\n" "MongoDB"     "mongodb://localhost:27017/?replicaSet=${MONGO_RS}"
  printf "  ${C_GRY}%-14s${C_RST} ${C_GRY}%s${C_RST}\n" "mongo-express" "http://localhost:8082  (${ME_USER}/${ME_PASS})"
  printf "  ${C_BLD}%-14s${C_RST} %s\n" "Redis"       "redis://:${REDIS_PASS}@localhost:6379"
  printf "  ${C_GRY}%-14s${C_RST} ${C_GRY}%s${C_RST}\n" "RedisInsight" "http://localhost:8083"
  printf "  ${C_BLD}%-14s${C_RST} %s\n" "Mailpit SMTP" "localhost:1025"
  printf "  ${C_GRY}%-14s${C_RST} ${C_GRY}%s${C_RST}\n" "Mailpit UI"  "http://localhost:8025"
  printf "  ${C_BLD}%-14s${C_RST} %s\n" "Seq"         "http://localhost:5341"
  printf "  ${C_BLD}%-14s${C_RST} %s\n" "RabbitMQ"    "amqp://${RMQ_USER}:${RMQ_PASS}@localhost:5672"
  printf "  ${C_GRY}%-14s${C_RST} ${C_GRY}%s${C_RST}\n" "RMQ Mgmt"   "http://localhost:15672  (${RMQ_USER}/${RMQ_PASS})"
  printf "  ${C_BLD}%-14s${C_RST} %s\n" "NATS"        "nats://localhost:4222"
  printf "  ${C_GRY}%-14s${C_RST} ${C_GRY}%s${C_RST}\n" "NATS Monitor" "http://localhost:8222"
  echo -e "${C_BLD}${C_CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RST}"
  echo -e "  ${C_GRY}Credentials live in: ~/.devpods/.env${C_RST}"
  echo -e "  ${C_GRY}Tear down:  bash devpods.sh down all${C_RST}"
  echo ""
}

# ─── entrypoint ───────────────────────────────────────────────────────────────
main() {
  banner "devpods v${DEVPODS_VERSION}"

  local cmd="${1:-up}"
  local target="${2:-all}"

  _check_system
  _load_env

  case "${cmd}" in
    up)
      local pods
      IFS=' ' read -ra pods <<< "$(_resolve_pods "${target}")"
      for p in "${pods[@]}"; do _launch_pod "${p}"; done
      _summary
      ;;
    down)
      section "Stopping pods"
      local pods
      IFS=' ' read -ra pods <<< "$(_resolve_pods "${target}")"
      for p in "${pods[@]}"; do _stop_pod "${p}"; done
      ok "Done."
      ;;
    reset)
      section "Resetting pods (stop + wipe data)"
      warn "This will DELETE all data for the selected pod(s). Ctrl-C to abort …"
      sleep 3
      local pods
      IFS=' ' read -ra pods <<< "$(_resolve_pods "${target}")"
      for p in "${pods[@]}"; do _reset_pod "${p}"; done
      ok "Reset complete. Re-run 'up' to recreate."
      ;;
    status)
      _status
      ;;
    help|--help|-h)
      _usage
      ;;
    *)
      err "Unknown command: ${cmd}"
      _usage
      exit 1
      ;;
  esac
}

main "$@"
