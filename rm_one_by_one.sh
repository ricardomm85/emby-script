#!/usr/bin/env bash
set -u

BASE_DIR="/home/ricardo/projects/emby-script"
JOBS_DIR="$BASE_DIR/.emby-jobs"
CONF="$BASE_DIR/emby.conf"
PID_FILE="$BASE_DIR/.rm_one_by_one.pid"
LOG_FILE="$BASE_DIR/.rm_one_by_one.log"
LOCK_FILE="$BASE_DIR/.rm_one_by_one.lock"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# shellcheck source=/dev/null
[ -f "$CONF" ] && source "$CONF"

if [ -z "${EMBY_HOST:-}" ] || [ -z "${EMBY_PORT:-}" ] || [ -z "${EMBY_TOKEN:-}" ]; then
  echo "[$(date '+%F %T')] config incompleta" >> "$LOG_FILE"
  exit 1
fi

BASE_URL="http://${EMBY_HOST}:${EMBY_PORT}/emby"

is_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

file_size() {
  local p="$1"
  if [ -f "$p" ]; then
    stat -c%s "$p" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Devuelve lista de jobs de Rick y Morty
mapfile -t JOBS < <(find "$JOBS_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)

ACTIVE=()
PENDING=()

for jf in "${JOBS[@]}"; do
  temp=$(jq -r '.temp_path // ""' "$jf" 2>/dev/null)
  final=$(jq -r '.final_path // ""' "$jf" 2>/dev/null)
  pid=$(jq -r '.pid // 0' "$jf" 2>/dev/null)
  total=$(jq -r '.total_size // 0' "$jf" 2>/dev/null)

  [[ "$temp" == *"/Rick_y_Morty/"* ]] || continue

  # Si ya existe final, no pendiente
  if [ -f "$final" ] && [ -s "$final" ]; then
    continue
  fi

  # Si proceso vivo -> activa
  if [ "$pid" -gt 0 ] 2>/dev/null && is_alive "$pid"; then
    ACTIVE+=("$jf")
    continue
  fi

  # Si proceso muerto pero temp completo, renombrar
  downloaded=$(file_size "$temp")
  if [ "$downloaded" -gt 0 ] 2>/dev/null && [ "$total" -gt 0 ] 2>/dev/null && [ "$downloaded" -ge "$total" ] 2>/dev/null; then
    mv "$temp" "$final" 2>/dev/null || true
    continue
  fi

  # Pendiente para reintentar
  PENDING+=("$jf")
done

# Si hay más de 1 activa, matar extras y dejar la más reciente por mtime
if [ "${#ACTIVE[@]}" -gt 1 ]; then
  # ordenar por mtime desc
  mapfile -t SORTED_ACTIVE < <(ls -1t "${ACTIVE[@]}" 2>/dev/null)
  KEEP="${SORTED_ACTIVE[0]}"
  for jf in "${SORTED_ACTIVE[@]:1}"; do
    pid=$(jq -r '.pid // 0' "$jf" 2>/dev/null)
    if [ "$pid" -gt 0 ] 2>/dev/null && is_alive "$pid"; then
      kill "$pid" 2>/dev/null || true
      echo "[$(date '+%F %T')] killed extra pid=$pid file=$(basename "$jf")" >> "$LOG_FILE"
    fi
  done
  ACTIVE=("$KEEP")
fi

# Si no hay activa, lanzar la siguiente pendiente (la más antigua por mtime)
if [ "${#ACTIVE[@]}" -eq 0 ] && [ "${#PENDING[@]}" -gt 0 ]; then
  mapfile -t SORTED_PENDING < <(ls -1tr "${PENDING[@]}" 2>/dev/null)
  NEXT="${SORTED_PENDING[0]}"

  item_id=$(jq -r '.item_id // ""' "$NEXT" 2>/dev/null)
  temp=$(jq -r '.temp_path // ""' "$NEXT" 2>/dev/null)
  final=$(jq -r '.final_path // ""' "$NEXT" 2>/dev/null)

  if [ -n "$item_id" ] && [ -n "$temp" ] && [ -n "$final" ]; then
    mkdir -p "$(dirname "$temp")"
    download_url="${BASE_URL}/Videos/${item_id}/stream?static=true&api_key=${EMBY_TOKEN}"

    nohup curl -L -C - -o "$temp" "$download_url" -H "X-Emby-Token: ${EMBY_TOKEN}" >/dev/null 2>&1 &
    newpid=$!

    tmpf="${NEXT}.tmp"
    jq --argjson p "$newpid" --arg st "downloading" '.pid=$p | .status=$st' "$NEXT" > "$tmpf" && mv "$tmpf" "$NEXT"

    echo "[$(date '+%F %T')] started pid=$newpid file=$(basename "$NEXT")" >> "$LOG_FILE"
  fi
fi
