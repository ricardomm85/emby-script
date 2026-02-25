#!/bin/bash

# Emby CLI - Interface para IA y automatización
# Uso: ./emby-cli.sh <comando> [opciones]

set -e

#============================================
# CONFIGURACIÓN
#============================================

CONFIG_FILE="$(dirname "$0")/emby.conf"
OUTPUT_FORMAT="text"  # text | json | compact
TIMEOUT=30
CONNECT_TIMEOUT=10
JOBS_DIR="$(dirname "$0")/.emby-jobs"

# Colores (solo para modo text)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
EMBY_HOST=""
EMBY_PORT=""
EMBY_EMAIL=""
EMBY_PASSWORD=""
EMBY_TOKEN=""
EMBY_USER_ID=""
BASE_URL=""

#============================================
# FUNCIONES DE UTILIDAD
#============================================

# Salida JSON segura
json_escape() {
    local string="$1"
    string="${string//\\/\\\\}"
    string="${string//\"/\\\"}"
    string="${string//$'\n'/\\n}"
    string="${string//$'\r'/\\r}"
    string="${string//$'\t'/\\t}"
    printf '%s' "$string"
}

# Imprimir salida según formato
output() {
    local type="$1"
    local data="$2"

    case "$OUTPUT_FORMAT" in
        json)
            echo "$data"
            ;;
        compact)
            echo "$data" | jq -c '.'
            ;;
        text|*)
            if [ "$type" = "error" ]; then
                echo -e "${RED}ERROR: ${NC}$data" >&2
            elif [ "$type" = "success" ]; then
                echo -e "${GREEN}$data${NC}"
            elif [ "$type" = "warning" ]; then
                echo -e "${YELLOW}$data${NC}" >&2
            else
                echo "$data"
            fi
            ;;
    esac
}

ensure_jobs_dir() {
    mkdir -p "$JOBS_DIR"
}

file_size_bytes() {
    local path="$1"
    [ -f "$path" ] && stat -c%s "$path" 2>/dev/null || echo 0
}

resolve_best_match() {
    local query="$1"
    local item_type="${2:-}"
    local encoded_query
    encoded_query=$(echo "$query" | sed 's/ /%20/g')

    local endpoint="/Users/${EMBY_USER_ID}/Items?Recursive=true&searchTerm=${encoded_query}&Limit=20&Fields=MediaSources"
    [ -n "$item_type" ] && endpoint="${endpoint}&IncludeItemTypes=${item_type}"

    local response
    response=$(api_request "$endpoint")

    echo "$response" | jq -c --arg q "$query" '
      .Items // [] |
      map(select(.Type=="Movie" or .Type=="Series")) |
      ( map(select((.Name|ascii_downcase) == ($q|ascii_downcase))) + . ) |
      unique_by(.Id) |
      .[0] // {}
    ' 2>/dev/null
}

# Cargar configuración
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        output "error" "No existe: $CONFIG_FILE"
        exit 1
    fi

    source "$CONFIG_FILE"

    if [ -z "$EMBY_HOST" ] || [ -z "$EMBY_PORT" ]; then
        output "error" "Configuración incompleta en EMBY_HOST o EMBY_PORT"
        exit 1
    fi

    BASE_URL="http://${EMBY_HOST}:${EMBY_PORT}/emby"
}

# Autenticación (sin interacción)
authenticate() {
    if [ -n "$EMBY_TOKEN" ] && [ -n "$EMBY_USER_ID" ]; then
        # Verificar token existente
        local response=$(curl -s --max-time "$CONNECT_TIMEOUT" \
            "${BASE_URL}/Users/${EMBY_USER_ID}" \
            -H "X-Emby-Token: ${EMBY_TOKEN}" 2>/dev/null || echo "")

        if [ -n "$response" ] && echo "$response" | jq -e '.Id' >/dev/null 2>&1; then
            return 0
        fi
    fi

    # Autenticar con credenciales
    if [ -z "$EMBY_EMAIL" ] || [ -z "$EMBY_PASSWORD" ]; then
        output "error" "Credenciales no configuradas en emby.conf"
        exit 1
    fi

    local payload=$(jq -n \
        --arg user "$EMBY_EMAIL" \
        --arg pass "$EMBY_PASSWORD" \
        '{Username: $user, Pw: $pass, Password: $pass}')

    local response=$(curl -s --max-time "$TIMEOUT" -X POST "${BASE_URL}/Users/AuthenticateByName" \
        -H "Content-Type: application/json" \
        -H "X-Emby-Authorization: MediaBrowser Client=\"EmbyCLI\", Device=\"CLI\", DeviceId=\"cli-$(hostname)\", Version=\"1.0\"" \
        -d "$payload" 2>/dev/null || echo "{}")

    EMBY_TOKEN=$(echo "$response" | jq -r '.AccessToken // empty')
    EMBY_USER_ID=$(echo "$response" | jq -r '.User.Id // empty')

    if [ -z "$EMBY_TOKEN" ]; then
        output "error" "Autenticación fallida"
        exit 1
    fi
}

# Petición genérica a la API
api_request() {
    local endpoint="$1"
    local extra_args="${2:-}"

    local separator="?"
    [[ "$endpoint" == *\?* ]] && separator="&"

    curl -s --max-time "$TIMEOUT" \
        "${BASE_URL}${endpoint}${separator}api_key=${EMBY_TOKEN}${extra_args}" \
        -H "X-Emby-Token: ${EMBY_TOKEN}" 2>/dev/null
}

#============================================
# COMANDOS
#============================================

# COMANDO: help
cmd_help() {
    cat <<'EOF'
Emby CLI - Interface para IA y automatización

USO:
    ./emby-cli.sh <comando> [opciones]

COMANDOS:
    search <término>       Buscar películas o series
    list <tipo>            Listar contenido (movies|series)
    info <id>              Información detallada de un item
    download <id>          Descargar película (foreground)
    episode <id> <ep>      Descargar episodio específico (foreground)
    resolve <texto>        Resolver nombre -> item (Movie/Series)
    download-job <id>      Iniciar descarga en background (película)
    episode-job <id> <ep>  Iniciar descarga episodio en background
    job-status <job_id>    Ver progreso de descarga en background
    seasons <id>           Listar temporadas de una serie
    help                   Mostrar esta ayuda

OPCIONES GLOBALES:
    --format, -f           Salida: text (default), json, compact
    --limit, -l            Límite de resultados (default: 50)
    --quiet, -q            Solo errores, sin output normal
    --timeout, -t          Timeout en segundos (default: 30)

OPCIONES DE SEARCH:
    --type, -t             Tipo: Movie, Series, o vacío para ambos
    --year, -y             Filtrar por año

OPCIONES DE LIST:
    movies                 Listar películas
    series                 Listar series

OPCIONES DE DOWNLOAD:
    --dest, -d             Directorio de destino (default: actual)
    --no-progress          No mostrar barra de progreso

OPCIONES DE EPISODE:
    --season, -s           Número de temporada (default: 1)

EJEMPLOS:
    # Buscar película (salida JSON)
    ./emby-cli.sh search "matrix" --format json

    # Listar series
    ./emby-cli.sh list series --limit 20

    # Info de un item
    ./emby-cli.sh info "12345"

    # Descargar película
    ./emby-cli.sh download "12345" --dest ~/Videos

    # Descargar episodio
    ./emby-cli.sh episode "12345" 5 --season 2

SALIDA JSON:
    Los comandos con --format json devuelven estructuras JSON fáciles de parsear:
    - search: [{"id": "...", "name": "...", "type": "...", "year": ...}]
    - list: [{"id": "...", "name": "...", "year": ...}]
    - info: {"id": "...", "name": "...", "overview": "...", ...}
    - seasons: [{"season": 1, "episodes": [{"id": "...", "number": 1, "name": "..."}]}]

EOF
}

# COMANDO: search
cmd_search() {
    local term="$1"
    shift

    local item_type=""
    local year=""
    local limit=50

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t) item_type="$2"; shift 2 ;;
            --year|-y) year="$2"; shift 2 ;;
            --limit|-l) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local encoded_term=$(echo "$term" | sed 's/ /%20/g')
    local url="/Users/${EMBY_USER_ID}/Items?Recursive=true&searchTerm=${encoded_term}&Limit=${limit}&Fields=MediaSources"

    [ -n "$item_type" ] && url="${url}&IncludeItemTypes=${item_type}"
    [ -n "$year" ] && url="${url}&Years=${year}"

    local response=$(api_request "$url")

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$response" | jq -c '[
            .Items[] | {
                id: .Id,
                name: .Name,
                type: .Type,
                year: .ProductionYear,
                runtime: (.RunTimeTicks / 600000000 | floor),
                size: .Size,
                overview: .Overview
            }
        ]' 2>/dev/null || echo "[]"
    else
        local total=$(echo "$response" | jq -r '.TotalRecordCount // 0')
        echo "Resultados: $total"
        echo ""
        echo "$response" | jq -r '.Items[] | "\(.Id) | \(.Name) | \(.Type) | \(.ProductionYear // "N/A")"' 2>/dev/null | column -t -s '|'
    fi
}

# COMANDO: list
cmd_list() {
    local type="$1"
    shift

    local limit=50
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit|-l) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local item_type=""
    case "$type" in
        movies|movie) item_type="Movie" ;;
        series|serie) item_type="Series" ;;
        *) output "error" "Tipo debe ser: movies o series"; exit 1 ;;
    esac

    local response=$(api_request "/Users/${EMBY_USER_ID}/Items?Recursive=true&IncludeItemTypes=${item_type}&SortBy=SortName&Limit=${limit}&Fields=MediaSources")

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$response" | jq -c '[
            .Items[] | {
                id: .Id,
                name: .Name,
                year: .ProductionYear,
                runtime: (.RunTimeTicks / 600000000 | floor)
            }
        ]' 2>/dev/null || echo "[]"
    else
        echo "$response" | jq -r '.Items[] | "\(.Id) | \(.Name) | \(.ProductionYear // "N/A")"' 2>/dev/null | column -t -s '|'
    fi
}

# COMANDO: info
cmd_info() {
    local item_id="$1"

    local response=$(api_request "/Users/${EMBY_USER_ID}/Items/${item_id}")

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$response" | jq -c '{
            id: .Id,
            name: .Name,
            type: .Type,
            year: .ProductionYear,
            runtime: (.RunTimeTicks / 600000000 | floor),
            genres: [.Genres[]? // empty],
            rating: .OfficialRating,
            overview: .Overview,
            path: .Path
        }' 2>/dev/null || echo "{}"
    else
        echo "$response" | jq -r '
            "ID: \(.Id)",
            "Nombre: \(.Name)",
            "Tipo: \(.Type)",
            "Año: \(.ProductionYear // "N/A")",
            "Duración: \(.RunTimeTicks / 600000000 | floor) min",
            "Géneros: \([.Genres[]? // empty] | join(", "))",
            "Clasificación: \(.OfficialRating // "N/A")",
            "",
            "Sinopsis:",
            (.Overview // "Sin descripción")
        ' 2>/dev/null
    fi
}

# COMANDO: seasons
cmd_seasons() {
    local item_id="$1"

    local response=$(api_request "/Shows/${item_id}/Episodes?UserId=${EMBY_USER_ID}")

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$response" | jq -c '
            [.Items[] | {
                season: .ParentIndexNumber // 1,
                episode: .IndexNumber // 0,
                id: .Id,
                name: .Name
            }] | group_by(.season) | map({season: .[0].season, episodes: .})
        ' 2>/dev/null || echo "[]"
    else
        echo "$response" | jq -r '.Items[] | "S\(.ParentIndexNumber // 1)E\(.IndexNumber // 0) | \(.Id | .[0:8])... | \(.Name)"' 2>/dev/null
    fi
}

# COMANDO: download
cmd_download() {
    local item_id="$1"
    shift

    local dest="."
    local no_progress=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dest|-d) dest="$2"; shift 2 ;;
            --no-progress) no_progress=true; shift ;;
            *) shift ;;
        esac
    done

    # Obtener info del item
    local info=$(api_request "/Users/${EMBY_USER_ID}/Items/${item_id}")
    local name=$(echo "$info" | jq -r '.Name // empty')
    local type=$(echo "$info" | jq -r '.Type // empty')

    if [ -z "$name" ]; then
        output "error" "Item no encontrado: $item_id"
        exit 1
    fi

    if [ "$type" = "Series" ]; then
        output "error" "Usa 'episode' para series. Item: $name"
        exit 1
    fi

    local container=$(echo "$info" | jq -r '.Container // "mkv"')
    local clean_name=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local filename="${clean_name}.${container}"
    local full_path="${dest}/${filename}"
    local temp_path="${full_path}.download"

    mkdir -p "$dest"

    if [ -f "$full_path" ] && [ -s "$full_path" ]; then
        if [ "$OUTPUT_FORMAT" = "json" ]; then
            echo "{\"status\": \"exists\", \"path\": \"${full_path}\"}"
        else
            output "warning" "Archivo ya existe: $full_path"
        fi
        exit 0
    fi

    local download_url="${BASE_URL}/Videos/${item_id}/stream?static=true&api_key=${EMBY_TOKEN}"

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "{\"status\": \"downloading\", \"name\": \"${name}\", \"temp_path\": \"${temp_path}\"}"
    fi

    local curl_opts="-L -s"
    [ "$no_progress" = false ] && curl_opts="-L -#"

    curl $curl_opts -o "${temp_path}" "$download_url" \
        -H "X-Emby-Token: ${EMBY_TOKEN}"

    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -s "$temp_path" ]; then
        mv "${temp_path}" "${full_path}"
        local size=$(du -h "$full_path" | cut -f1)

        if [ "$OUTPUT_FORMAT" = "json" ]; then
            echo "{\"status\": \"completed\", \"path\": \"${full_path}\", \"size\": \"${size}\"}"
        else
            output "success" "Descargado: $full_path ($size)"
        fi
    else
        rm -f "${temp_path}"
        if [ "$OUTPUT_FORMAT" = "json" ]; then
            echo "{\"status\": \"error\", \"code\": ${exit_code}}" >&2
        else
            output "error" "Fallo descarga (código: $exit_code)"
        fi
        exit 1
    fi
}

# COMANDO: episode
cmd_episode() {
    local series_id="$1"
    local episode_num="$2"
    shift 2

    local season=1
    local dest="."
    local no_progress=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --season|-s) season="$2"; shift 2 ;;
            --dest|-d) dest="$2"; shift 2 ;;
            --no-progress) no_progress=true; shift ;;
            *) shift ;;
        esac
    done

    # Buscar episodio
    local response=$(api_request "/Shows/${series_id}/Episodes?UserId=${EMBY_USER_ID}")

    local ep_data=$(echo "$response" | jq -r --argjson ep "$episode_num" --argjson ssn "$season" \
        '.Items[] | select(.IndexNumber == $ep and (.ParentIndexNumber // 1) == $ssn) |
         {id: .Id, name: .Name, series: .SeriesName, container: (.Container // "mkv")}' 2>/dev/null)

    if [ -z "$ep_data" ]; then
        output "error" "Episodio S${season}E${episode_num} no encontrado"
        exit 1
    fi

    local ep_id=$(echo "$ep_data" | jq -r '.id')
    local ep_name=$(echo "$ep_data" | jq -r '.name')
    local series_name=$(echo "$ep_data" | jq -r '.series')
    local container=$(echo "$ep_data" | jq -r '.container')

    local clean_series=$(echo "$series_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local clean_name=$(echo "$ep_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local filename=$(printf "S%02dE%02d_%s.%s" "$season" "$episode_num" "$clean_name" "$container")
    local full_path="${dest}/${filename}"
    local temp_path="${full_path}.download"

    mkdir -p "$dest"

    if [ -f "$full_path" ] && [ -s "$full_path" ]; then
        if [ "$OUTPUT_FORMAT" = "json" ]; then
            echo "{\"status\": \"exists\", \"path\": \"${full_path}\"}"
        else
            output "warning" "Archivo ya existe: $full_path"
        fi
        exit 0
    fi

    local download_url="${BASE_URL}/Videos/${ep_id}/stream?static=true&api_key=${EMBY_TOKEN}"

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "{\"status\": \"downloading\", \"episode\": \"S${season}E${episode_num}\", \"temp_path\": \"${temp_path}\"}"
    fi

    local curl_opts="-L -s"
    [ "$no_progress" = false ] && curl_opts="-L -#"

    curl $curl_opts -o "${temp_path}" "$download_url" \
        -H "X-Emby-Token: ${EMBY_TOKEN}"

    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -s "$temp_path" ]; then
        mv "${temp_path}" "${full_path}"
        local size=$(du -h "$full_path" | cut -f1)

        if [ "$OUTPUT_FORMAT" = "json" ]; then
            echo "{\"status\": \"completed\", \"path\": \"${full_path}\", \"size\": \"${size}\"}"
        else
            output "success" "Descargado: $full_path ($size)"
        fi
    else
        rm -f "${temp_path}"
        if [ "$OUTPUT_FORMAT" = "json" ]; then
            echo "{\"status\": \"error\", \"code\": ${exit_code}}" >&2
        else
            output "error" "Fallo descarga (código: $exit_code)"
        fi
        exit 1
    fi
}

# COMANDO: resolve
cmd_resolve() {
    local query="$1"
    shift || true

    local item_type=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t) item_type="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local best
    best=$(resolve_best_match "$query" "$item_type")

    if [ -z "$best" ] || [ "$best" = "{}" ]; then
        [ "$OUTPUT_FORMAT" = "json" ] && echo "{}" || output "warning" "Sin resultados para: $query"
        return 1
    fi

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$best" | jq -c '{id: .Id, name: .Name, type: .Type, year: .ProductionYear}'
    else
        echo "$best" | jq -r '"\(.Type) | \(.Id) | \(.Name) (\(.ProductionYear // "N/A"))"'
    fi
}

# COMANDO: download-job
cmd_download_job() {
    local item_id="$1"
    shift
    local dest="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dest|-d) dest="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    ensure_jobs_dir

    local info name type container clean_name filename full_path temp_path total_size download_url
    info=$(api_request "/Users/${EMBY_USER_ID}/Items/${item_id}")
    name=$(echo "$info" | jq -r '.Name // empty')
    type=$(echo "$info" | jq -r '.Type // empty')
    container=$(echo "$info" | jq -r '.Container // "mkv"')
    total_size=$(echo "$info" | jq -r '.Size // 0')

    if [ -z "$name" ]; then output "error" "Item no encontrado: $item_id"; exit 1; fi
    if [ "$type" = "Series" ]; then output "error" "Usa episode-job para series"; exit 1; fi

    mkdir -p "$dest"
    clean_name=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')
    filename="${clean_name}.${container}"
    full_path="${dest}/${filename}"
    temp_path="${full_path}.download"
    download_url="${BASE_URL}/Videos/${item_id}/stream?static=true&api_key=${EMBY_TOKEN}"

    local job_id job_file pid
    job_id="job-$(date +%s)-$RANDOM"
    job_file="${JOBS_DIR}/${job_id}.json"

    nohup curl -L -C - -o "$temp_path" "$download_url" -H "X-Emby-Token: ${EMBY_TOKEN}" >/dev/null 2>&1 &
    pid=$!

    cat > "$job_file" <<EOF
{"job_id":"$job_id","pid":$pid,"item_id":"$item_id","name":"$(json_escape "$name")","type":"$type","total_size":$total_size,"temp_path":"$(json_escape "$temp_path")","final_path":"$(json_escape "$full_path")","status":"downloading"}
EOF

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        cat "$job_file"
    else
        output "success" "Descarga iniciada: $name"
        echo "job_id: $job_id"
        echo "archivo: $full_path"
    fi
}

# COMANDO: episode-job
cmd_episode_job() {
    local series_id="$1"
    local episode_num="$2"
    shift 2

    local season=1
    local dest="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --season|-s) season="$2"; shift 2 ;;
            --dest|-d) dest="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local response ep_data ep_id ep_name series_name container filename full_path temp_path download_url total_size ep_info
    response=$(api_request "/Shows/${series_id}/Episodes?UserId=${EMBY_USER_ID}")
    ep_data=$(echo "$response" | jq -r --argjson ep "$episode_num" --argjson ssn "$season" '.Items[] | select(.IndexNumber == $ep and (.ParentIndexNumber // 1) == $ssn) | {id: .Id, name: .Name, series: .SeriesName, container: (.Container // "mkv")}')

    if [ -z "$ep_data" ]; then output "error" "Episodio S${season}E${episode_num} no encontrado"; exit 1; fi

    ep_id=$(echo "$ep_data" | jq -r '.id')
    ep_name=$(echo "$ep_data" | jq -r '.name')
    series_name=$(echo "$ep_data" | jq -r '.series')
    container=$(echo "$ep_data" | jq -r '.container')
    ep_info=$(api_request "/Users/${EMBY_USER_ID}/Items/${ep_id}")
    total_size=$(echo "$ep_info" | jq -r '.Size // 0')

    mkdir -p "$dest"
    filename=$(printf "S%02dE%02d_%s.%s" "$season" "$episode_num" "$(echo "$ep_name" | sed 's/[^a-zA-Z0-9._-]/_/g')" "$container")
    full_path="${dest}/${filename}"
    temp_path="${full_path}.download"
    download_url="${BASE_URL}/Videos/${ep_id}/stream?static=true&api_key=${EMBY_TOKEN}"

    ensure_jobs_dir
    local job_id job_file pid
    job_id="job-$(date +%s)-$RANDOM"
    job_file="${JOBS_DIR}/${job_id}.json"

    nohup curl -L -C - -o "$temp_path" "$download_url" -H "X-Emby-Token: ${EMBY_TOKEN}" >/dev/null 2>&1 &
    pid=$!

    cat > "$job_file" <<EOF
{"job_id":"$job_id","pid":$pid,"item_id":"$ep_id","name":"$(json_escape "$series_name - S${season}E${episode_num} - $ep_name")","type":"Episode","total_size":$total_size,"temp_path":"$(json_escape "$temp_path")","final_path":"$(json_escape "$full_path")","status":"downloading"}
EOF

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        cat "$job_file"
    else
        output "success" "Descarga iniciada: ${series_name} S${season}E${episode_num}"
        echo "job_id: $job_id"
        echo "archivo: $full_path"
    fi
}

# COMANDO: job-status
cmd_job_status() {
    local job_id="$1"
    ensure_jobs_dir
    local job_file="${JOBS_DIR}/${job_id}.json"

    if [ ! -f "$job_file" ]; then
        output "error" "Job no encontrado: $job_id"
        exit 1
    fi

    local pid temp_path final_path total_size name alive downloaded percent status
    pid=$(jq -r '.pid' "$job_file")
    temp_path=$(jq -r '.temp_path' "$job_file")
    final_path=$(jq -r '.final_path' "$job_file")
    total_size=$(jq -r '.total_size // 0' "$job_file")
    name=$(jq -r '.name' "$job_file")

    alive=false
    kill -0 "$pid" 2>/dev/null && alive=true

    if [ -f "$final_path" ] && [ -s "$final_path" ]; then
        status="completed"
        downloaded=$(file_size_bytes "$final_path")
    else
        downloaded=$(file_size_bytes "$temp_path")

        if [ "$alive" = true ]; then
            status="downloading"
        else
            # Proceso terminó: si el temporal está completo (o no tenemos total pero hay datos), finalizar
            if [ "$downloaded" -gt 0 ] 2>/dev/null; then
                if [ "$total_size" -gt 0 ] 2>/dev/null; then
                    if [ "$downloaded" -ge "$total_size" ] 2>/dev/null; then
                        mv "$temp_path" "$final_path" 2>/dev/null || true
                    fi
                else
                    mv "$temp_path" "$final_path" 2>/dev/null || true
                fi
            fi

            if [ -f "$final_path" ] && [ -s "$final_path" ]; then
                status="completed"
                downloaded=$(file_size_bytes "$final_path")
            else
                status="failed"
            fi
        fi
    fi

    percent=0
    if [ "$total_size" -gt 0 ] 2>/dev/null; then
        percent=$(awk -v d="$downloaded" -v t="$total_size" 'BEGIN { if (t>0) printf "%.2f", (d/t)*100; else print 0 }')
    fi

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        jq -n \
          --arg job_id "$job_id" \
          --arg name "$name" \
          --arg status "$status" \
          --argjson pid "$pid" \
          --argjson downloaded "$downloaded" \
          --argjson total "$total_size" \
          --arg percent "$percent" \
          --arg final_path "$final_path" \
          '{job_id:$job_id,name:$name,status:$status,pid:$pid,downloaded_bytes:$downloaded,total_bytes:$total,percent:$percent,final_path:$final_path}'
    else
        echo "Job: $job_id"
        echo "Nombre: $name"
        echo "Estado: $status"
        echo "Progreso: ${percent}% (${downloaded}/${total_size} bytes)"
        echo "Archivo: $final_path"
    fi
}

#============================================
# MAIN
#============================================

main() {
    # Parse opciones globales primero
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format|-f)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --timeout|-t)
                TIMEOUT="$2"
                shift 2
                ;;
            --quiet|-q)
                exec >/dev/null
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    if [ $# -eq 0 ]; then
        cmd_help
        exit 0
    fi

    local command="$1"
    shift

    # Cargar config y autenticar para comandos que lo necesitan
    case "$command" in
        help|--help|-h)
            cmd_help
            exit 0
            ;;
        search|list|info|seasons|download|episode|resolve|download-job|episode-job|job-status)
            load_config
            authenticate
            ;;
        *)
            output "error" "Comando desconocido: $command"
            echo "Usa 'help' para ver comandos disponibles"
            exit 1
            ;;
    esac

    # Ejecutar comando
    case "$command" in
        search)       cmd_search "$@" ;;
        list)         cmd_list "$@" ;;
        info)         cmd_info "$@" ;;
        seasons)      cmd_seasons "$@" ;;
        resolve)      cmd_resolve "$@" ;;
        download)     cmd_download "$@" ;;
        episode)      cmd_episode "$@" ;;
        download-job) cmd_download_job "$@" ;;
        episode-job)  cmd_episode_job "$@" ;;
        job-status)   cmd_job_status "$@" ;;
    esac
}

main "$@"
