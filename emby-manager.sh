#!/bin/bash

# Script para gestionar servidor Emby
# Permite buscar, listar y descargar películas y series

# Colores para la interfaz
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# Archivo de configuración
CONFIG_FILE="$(dirname "$0")/emby.conf"

# Variables globales
EMBY_HOST=""
EMBY_PORT=""
EMBY_EMAIL=""
EMBY_PASSWORD=""
EMBY_TOKEN=""
EMBY_USER_ID=""
BASE_URL=""

#===========================================
# FUNCIONES DE UTILIDAD
#===========================================

# Mostrar mensaje de error
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Mostrar mensaje de éxito
success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Mostrar mensaje de info
info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Mostrar mensaje de advertencia
warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

# Validar dependencias
check_dependencies() {
    local missing_deps=()

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Faltan las siguientes dependencias: ${missing_deps[*]}"
        info "Instala con: sudo apt install ${missing_deps[*]}"
        exit 1
    fi
}

# Cargar configuración
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "No se encuentra el archivo de configuración: $CONFIG_FILE"
        exit 1
    fi

    source "$CONFIG_FILE"

    if [ -z "$EMBY_HOST" ] || [ -z "$EMBY_PORT" ]; then
        error "Configuración incompleta en $CONFIG_FILE"
        exit 1
    fi

    BASE_URL="http://${EMBY_HOST}:${EMBY_PORT}/emby"
}

# Guardar token en el archivo de configuración
save_token() {
    local token="$1"
    local user_id="$2"

    # Actualizar variables en el archivo
    sed -i "s|^EMBY_TOKEN=.*|EMBY_TOKEN=\"$token\"|" "$CONFIG_FILE"
    sed -i "s|^EMBY_USER_ID=.*|EMBY_USER_ID=\"$user_id\"|" "$CONFIG_FILE"

    # Actualizar variables en memoria
    EMBY_TOKEN="$token"
    EMBY_USER_ID="$user_id"
}

#===========================================
# AUTENTICACIÓN
#===========================================

# Autenticarse con el servidor Emby
authenticate() {
    info "Conectando al servidor Emby en ${EMBY_HOST}:${EMBY_PORT}..."

    # Preparar payload de autenticación
    local payload=$(jq -n \
        --arg user "$EMBY_EMAIL" \
        --arg pass "$EMBY_PASSWORD" \
        '{Username: $user, Pw: $pass, Password: $pass}')

    # Realizar petición de autenticación
    local response=$(curl -s -X POST "${BASE_URL}/Users/AuthenticateByName" \
        -H "Content-Type: application/json" \
        -H "X-Emby-Authorization: MediaBrowser Client=\"EmbyManager\", Device=\"Bash Script\", DeviceId=\"bash-$(hostname)\", Version=\"1.0\"" \
        -d "$payload")

    # Verificar respuesta
    if [ -z "$response" ]; then
        error "No se recibió respuesta del servidor"
        return 1
    fi

    # Extraer token y user ID
    local token=$(echo "$response" | jq -r '.AccessToken // empty')
    local user_id=$(echo "$response" | jq -r '.User.Id // empty')
    local user_name=$(echo "$response" | jq -r '.User.Name // empty')

    if [ -z "$token" ] || [ -z "$user_id" ]; then
        error "Autenticación fallida. Verifica tus credenciales."
        echo "$response" | jq -r '.Message // "Error desconocido"'
        return 1
    fi

    # Guardar token
    save_token "$token" "$user_id"

    success "Autenticado correctamente como: ${GREEN}$user_name${NC}"
    return 0
}

# Verificar si hay un token válido
check_auth() {
    if [ -z "$EMBY_TOKEN" ] || [ -z "$EMBY_USER_ID" ]; then
        return 1
    fi

    # Verificar que el token sigue siendo válido
    local response=$(curl -s "${BASE_URL}/Users/${EMBY_USER_ID}" \
        -H "X-Emby-Token: ${EMBY_TOKEN}")

    local id=$(echo "$response" | jq -r '.Id // empty')

    if [ -z "$id" ]; then
        return 1
    fi

    return 0
}

#===========================================
# BÚSQUEDA Y LISTADO
#===========================================

# Buscar contenido
search_content() {
    local search_term="$1"
    local item_type="$2"  # Movie, Series, o vacío para ambos

    info "Buscando: $search_term"

    # Codificar espacios en el término de búsqueda
    local encoded_term=$(echo "$search_term" | sed 's/ /%20/g')

    local url="${BASE_URL}/Users/${EMBY_USER_ID}/Items?Recursive=true&searchTerm=${encoded_term}&api_key=${EMBY_TOKEN}&Fields=MediaSources"

    if [ -n "$item_type" ]; then
        url="${url}&IncludeItemTypes=${item_type}"
    else
        url="${url}&IncludeItemTypes=Movie,Series"
    fi

    local response=$(curl -s "$url")

    # Verificar si la respuesta es válida
    if [ -z "$response" ]; then
        error "No se recibió respuesta del servidor"
        return 1
    fi

    # Verificar si hay resultados
    local total=$(echo "$response" | jq -r '.TotalRecordCount // 0' 2>/dev/null)

    # Si total está vacío, asignar 0
    if [ -z "$total" ]; then
        total=0
    fi

    if [ "$total" -eq 0 ]; then
        warning "No se encontraron resultados"
        return 1
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Resultados encontrados: $total${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Mostrar resultados
    echo "$response" | jq -r '.Items[] |
        "\(.Id)|\(.Name)|\(.Type)|\(.ProductionYear // "N/A")|\(.RunTimeTicks // 0)|\(.Size // 0)"' |
    while IFS='|' read -r id name type year ticks size_bytes; do
        # Calcular duración en minutos
        local minutes=$((ticks / 600000000))

        # Convertir tamaño a formato legible
        local size_human=""
        if [ "$size_bytes" -gt 0 ]; then
            if [ "$size_bytes" -ge 1073741824 ]; then
                size_human=$(awk "BEGIN {printf \"%.2f GB\", $size_bytes/1073741824}")
            elif [ "$size_bytes" -ge 1048576 ]; then
                size_human=$(awk "BEGIN {printf \"%.2f MB\", $size_bytes/1048576}")
            else
                size_human=$(awk "BEGIN {printf \"%.2f KB\", $size_bytes/1024}")
            fi
        else
            size_human="N/A"
        fi

        # Línea 1: ID, Título, Año y Tipo
        echo -e "${YELLOW}ID:${NC} $id ${CYAN}|${NC} ${MAGENTA}$name${NC} ${BLUE}($year)${NC} ${CYAN}-${NC} ${GREEN}$type${NC}"

        # Línea 2: Tamaño y Duración (si aplica)
        if [ "$minutes" -gt 0 ]; then
            echo -e "   ${BLUE}Tamaño:${NC} $size_human ${CYAN}|${NC} ${BLUE}Duración:${NC} ${minutes} min"
        else
            echo -e "   ${BLUE}Tamaño:${NC} $size_human"
        fi
    done

    return 0
}

# Listar toda la biblioteca
list_library() {
    local item_type="$1"  # Movie o Series
    local type_name=""

    if [ "$item_type" = "Movie" ]; then
        type_name="Películas"
    else
        type_name="Series"
    fi

    info "Obteniendo lista de $type_name..."

    local response=$(curl -s "${BASE_URL}/Users/${EMBY_USER_ID}/Items?Recursive=true&IncludeItemTypes=${item_type}&SortBy=SortName&api_key=${EMBY_TOKEN}&Limit=50&Fields=MediaSources")

    # Verificar si la respuesta es válida
    if [ -z "$response" ]; then
        error "No se recibió respuesta del servidor"
        return 1
    fi

    local total=$(echo "$response" | jq -r '.TotalRecordCount // 0' 2>/dev/null)

    # Si total está vacío, asignar 0
    if [ -z "$total" ]; then
        total=0
    fi

    if [ "$total" -eq 0 ]; then
        warning "No se encontraron $type_name"
        return 1
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Total de $type_name: $total (mostrando primeras 50)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo "$response" | jq -r '.Items[] |
        "\(.Id)|\(.Name)|\(.ProductionYear // "N/A")|\(.RunTimeTicks // 0)|\(.Size // 0)"' |
    while IFS='|' read -r id name year ticks size_bytes; do
        # Calcular duración en minutos
        local minutes=$((ticks / 600000000))

        # Convertir tamaño a formato legible
        local size_human=""
        if [ "$size_bytes" -gt 0 ]; then
            if [ "$size_bytes" -ge 1073741824 ]; then
                size_human=$(awk "BEGIN {printf \"%.2f GB\", $size_bytes/1073741824}")
            elif [ "$size_bytes" -ge 1048576 ]; then
                size_human=$(awk "BEGIN {printf \"%.2f MB\", $size_bytes/1048576}")
            else
                size_human=$(awk "BEGIN {printf \"%.2f KB\", $size_bytes/1024}")
            fi
        else
            size_human="N/A"
        fi

        # Línea 1: ID, Título y Año
        echo -e "${YELLOW}ID:${NC} $id ${CYAN}|${NC} ${MAGENTA}$name${NC} ${BLUE}($year)${NC}"

        # Línea 2: Tamaño y Duración (si aplica)
        if [ "$minutes" -gt 0 ]; then
            echo -e "   ${BLUE}Tamaño:${NC} $size_human ${CYAN}|${NC} ${BLUE}Duración:${NC} ${minutes} min"
        else
            echo -e "   ${BLUE}Tamaño:${NC} $size_human"
        fi
    done

    return 0
}

#===========================================
# INFORMACIÓN DETALLADA
#===========================================

# Obtener información detallada de un item
get_item_info() {
    local item_id="$1"

    info "Obteniendo información del item..."

    local response=$(curl -s "${BASE_URL}/Users/${EMBY_USER_ID}/Items/${item_id}?api_key=${EMBY_TOKEN}")

    local name=$(echo "$response" | jq -r '.Name // "N/A"')

    if [ "$name" = "N/A" ]; then
        error "No se pudo obtener información del item"
        return 1
    fi

    local type=$(echo "$response" | jq -r '.Type // "N/A"')
    local year=$(echo "$response" | jq -r '.ProductionYear // "N/A"')
    local overview=$(echo "$response" | jq -r '.Overview // "Sin descripción"')
    local ticks=$(echo "$response" | jq -r '.RunTimeTicks // 0')
    local minutes=$((ticks / 600000000))
    local genres=$(echo "$response" | jq -r '.Genres[]? // empty' | tr '\n' ', ' | sed 's/,$//')
    local rating=$(echo "$response" | jq -r '.OfficialRating // "N/A"')

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Información Detallada${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}Título:${NC} $name"
    echo -e "${BLUE}Tipo:${NC} $type"
    echo -e "${BLUE}Año:${NC} $year"
    echo -e "${BLUE}Clasificación:${NC} $rating"
    if [ "$minutes" -gt 0 ]; then
        echo -e "${BLUE}Duración:${NC} ${minutes} minutos"
    fi
    if [ -n "$genres" ]; then
        echo -e "${BLUE}Géneros:${NC} $genres"
    fi
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Descripción:${NC}"
    echo "$overview" | fold -s -w 63
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    return 0
}

#===========================================
# DESCARGA
#===========================================

# Descargar contenido
download_item() {
    local item_id="$1"

    info "Obteniendo información del item para descarga..."

    # Obtener información del item
    local response=$(curl -s "${BASE_URL}/Users/${EMBY_USER_ID}/Items/${item_id}?api_key=${EMBY_TOKEN}")

    local name=$(echo "$response" | jq -r '.Name // "N/A"')
    local type=$(echo "$response" | jq -r '.Type // "N/A"')
    local path=$(echo "$response" | jq -r '.Path // empty')

    if [ "$name" = "N/A" ]; then
        error "No se pudo obtener información del item"
        return 1
    fi

    echo -e "${GREEN}Título:${NC} $name"
    echo -e "${BLUE}Tipo:${NC} $type"

    # Para series, necesitamos manejar episodios
    if [ "$type" = "Series" ]; then
        warning "Este es una serie. Obteniendo episodios..."

        # Crear carpeta principal para la serie
        local series_folder=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')

        # Obtener episodios de la serie
        local episodes_response=$(curl -s "${BASE_URL}/Shows/${item_id}/Episodes?UserId=${EMBY_USER_ID}&api_key=${EMBY_TOKEN}")

        local ep_count=$(echo "$episodes_response" | jq -r '.TotalRecordCount // 0')
        echo -e "${GREEN}Total de episodios: $ep_count${NC}"

        echo ""
        echo "¿Qué deseas descargar?"
        echo "1) Todos los episodios"
        echo "2) Episodio específico"
        echo "3) Cancelar"
        echo -n "Opción: "
        read -r option

        case $option in
            1)
                info "Descargando todos los episodios..."
                echo "$episodes_response" | jq -r '.Items[] | "\(.Id)|\(.Name)|\(.ParentIndexNumber // 1)|\(.IndexNumber // 0)"' |
                while IFS='|' read -r ep_id ep_name season_num ep_num; do
                    download_single_item "$ep_id" "$ep_name" "$series_folder" "$season_num" "$ep_num"
                done
                ;;
            2)
                echo -n "Ingresa el número de episodio: "
                read -r ep_num
                local ep_data=$(echo "$episodes_response" | jq -r ".Items[] | select(.IndexNumber == $ep_num) | \"\(.Id)|\(.Name)|\(.ParentIndexNumber // 1)|\(.IndexNumber // 0)\"")
                if [ -n "$ep_data" ]; then
                    IFS='|' read -r ep_id ep_name season_num ep_number <<< "$ep_data"
                    download_single_item "$ep_id" "$ep_name" "$series_folder" "$season_num" "$ep_number"
                else
                    error "No se encontró el episodio $ep_num"
                fi
                ;;
            *)
                info "Descarga cancelada"
                return 0
                ;;
        esac
    else
        # Para películas, descargar directamente
        download_single_item "$item_id" "$name"
    fi

    return 0
}

# Descargar un solo item (película o episodio)
download_single_item() {
    local item_id="$1"
    local item_name="$2"
    local series_folder="${3:-}"       # Nombre de la serie (opcional)
    local season_num="${4:-}"          # Número de temporada (opcional)
    local episode_num="${5:-}"         # Número de episodio (opcional)

    info "Obteniendo información del archivo..."

    # Obtener información del item para conocer el formato
    local item_info=$(curl -s "${BASE_URL}/Users/${EMBY_USER_ID}/Items/${item_id}?api_key=${EMBY_TOKEN}")
    local container=$(echo "$item_info" | jq -r '.Container // "mkv"')

    # Determinar la ruta y nombre del archivo
    local filename
    local target_dir="."

    if [ -n "$series_folder" ] && [ -n "$season_num" ] && [ -n "$episode_num" ]; then
        # Es un episodio de serie - crear estructura de carpetas
        target_dir="${series_folder}/Temporada_${season_num}"
        mkdir -p "$target_dir"

        # Limpiar nombre del episodio
        local clean_name=$(echo "$item_name" | sed 's/[^a-zA-Z0-9._-]/_/g')

        # Formato: Episodio_01_NombreDelEpisodio.mkv
        filename=$(printf "Episodio_%02d_%s.%s" "$episode_num" "$clean_name" "$container")
    else
        # Es una película - usar directorio actual
        local clean_name=$(echo "$item_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
        filename="${clean_name}.${container}"
    fi

    # Ruta completa del archivo
    local full_path="${target_dir}/${filename}"
    local temp_path="${full_path}.download"

    # Verificar si el archivo ya existe
    if [ -f "$full_path" ] && [ -s "$full_path" ]; then
        local file_size=$(du -h "$full_path" | cut -f1)
        warning "Archivo ya existe: ${full_path} (${file_size})"
        info "Saltando descarga..."
        return 0
    fi

    # Verificar si existe una descarga incompleta
    if [ -f "$temp_path" ]; then
        warning "Existe una descarga incompleta: ${temp_path}"
        info "Reanudando descarga..."
    fi

    # Usar el endpoint de streaming que funciona
    local download_url="${BASE_URL}/Videos/${item_id}/stream?static=true&api_key=${EMBY_TOKEN}"

    info "Descargando: $item_name"
    echo -e "${BLUE}Formato:${NC} $container"
    if [ -n "$season_num" ] && [ -n "$episode_num" ]; then
        echo -e "${BLUE}Temporada:${NC} $season_num ${BLUE}Episodio:${NC} $episode_num"
        echo -e "${BLUE}Carpeta:${NC} $target_dir"
    fi
    echo -e "${BLUE}Archivo:${NC} ${filename}.download → ${filename}"
    echo ""

    # Descargar con barra de progreso al archivo temporal
    curl -# -L -o "${temp_path}" "$download_url" \
        -H "X-Emby-Token: ${EMBY_TOKEN}"

    local exit_code=$?

    echo ""

    if [ $exit_code -eq 0 ]; then
        # Verificar que el archivo se descargó y tiene contenido
        if [ -f "$temp_path" ] && [ -s "$temp_path" ]; then
            # Renombrar archivo temporal al final solo si la descarga fue exitosa
            mv "${temp_path}" "${full_path}"
            local file_size=$(du -h "$full_path" | cut -f1)
            success "Descarga completada: ${full_path} (${file_size})"
        else
            error "El archivo se descargó pero está vacío"
            rm -f "${temp_path}"
            return 1
        fi
    else
        error "Error al descargar el archivo (código: $exit_code)"
        rm -f "${temp_path}"
        return 1
    fi

    return 0
}

#===========================================
# MENÚ PRINCIPAL
#===========================================

show_menu() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}           ${MAGENTA}GESTOR DE SERVIDOR EMBY${NC}                       ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} Buscar películas o series"
    echo -e "${GREEN}2)${NC} Listar todas las películas"
    echo -e "${GREEN}3)${NC} Listar todas las series"
    echo -e "${GREEN}4)${NC} Ver información detallada (por ID)"
    echo -e "${GREEN}5)${NC} Descargar contenido (por ID)"
    echo -e "${GREEN}6)${NC} Salir"
    echo ""
    echo -n "Selecciona una opción: "
}

# Función principal de búsqueda interactiva
interactive_search() {
    echo ""
    echo -n "Ingresa el término de búsqueda: "
    read -r search_term

    if [ -z "$search_term" ]; then
        warning "Debes ingresar un término de búsqueda"
        return
    fi

    echo ""
    echo "¿Qué quieres buscar?"
    echo "1) Películas"
    echo "2) Series"
    echo "3) Ambos"
    echo -n "Opción: "
    read -r option

    case $option in
        1)
            search_content "$search_term" "Movie"
            ;;
        2)
            search_content "$search_term" "Series"
            ;;
        3)
            search_content "$search_term" ""
            ;;
        *)
            warning "Opción inválida"
            ;;
    esac
}

# Solicitar ID de item
ask_for_id() {
    echo "" >&2
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}" >&2
    echo -e "${YELLOW}Ingresa el ID del item:${NC}" >&2
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}" >&2
    echo -n "> " >&2
    read -r item_id

    if [ -z "$item_id" ]; then
        warning "Debes ingresar un ID" >&2
        return 1
    fi

    echo "$item_id"
    return 0
}

#===========================================
# MAIN
#===========================================

main() {
    # Validar dependencias
    check_dependencies

    # Cargar configuración
    load_config

    # Verificar autenticación o autenticar
    if ! check_auth; then
        if ! authenticate; then
            error "No se pudo autenticar. Saliendo..."
            exit 1
        fi
    else
        success "Usando token de autenticación guardado"
    fi

    # Bucle del menú principal
    while true; do
        show_menu
        read -r option

        case $option in
            1)
                interactive_search
                ;;
            2)
                list_library "Movie"
                ;;
            3)
                list_library "Series"
                ;;
            4)
                item_id=$(ask_for_id)
                if [ $? -eq 0 ]; then
                    get_item_info "$item_id"
                fi
                ;;
            5)
                item_id=$(ask_for_id)
                if [ $? -eq 0 ]; then
                    download_item "$item_id"
                fi
                ;;
            6)
                echo ""
                success "¡Hasta luego!"
                exit 0
                ;;
            *)
                warning "Opción inválida"
                ;;
        esac

        # Pausa antes de volver al menú
        echo ""
        echo -n "Presiona Enter para continuar..."
        read -r
    done
}

# Ejecutar script
main
