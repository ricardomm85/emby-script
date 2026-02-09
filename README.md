# Gestor de Servidor Emby

Script en Bash para conectarse a un servidor Emby y gestionar contenido multimedia (películas y series).

## Requisitos

Este script requiere las siguientes herramientas:

- `curl` - Para hacer peticiones HTTP
- `jq` - Para procesar JSON

### Instalación de dependencias

En Ubuntu/Debian:
```bash
sudo apt install curl jq
```

## Configuración

Copia el archivo de ejemplo y edítalo con tus datos:

```bash
cp emby.conf.example emby.conf
nano emby.conf
```

Edita `emby.conf` con tus credenciales:

```bash
EMBY_HOST="tu-servidor-emby.com"
EMBY_PORT="8096"
EMBY_EMAIL="tu-email@ejemplo.com"
EMBY_PASSWORD="tu-contraseña"
```

El token de acceso se genera automáticamente al autenticarse por primera vez.

**Importante**: El archivo `emby.conf` contiene credenciales sensibles. No lo compartas ni lo subas a repositorios públicos.

## Uso

Ejecuta el script:

```bash
./emby-manager.sh
```

## Funcionalidades

### 1. Buscar películas o series
- Busca contenido por nombre
- Filtra por tipo (películas, series, o ambos)
- Muestra resultados con ID, título, año y duración

### 2. Listar todas las películas
- Lista las primeras 50 películas de la biblioteca
- Ordenadas alfabéticamente
- Muestra ID y título con año

### 3. Listar todas las series
- Lista las primeras 50 series de la biblioteca
- Ordenadas alfabéticamente
- Muestra ID y título con año

### 4. Ver información detallada
- Solicita el ID del item
- Muestra información completa: título, año, duración, géneros, clasificación y descripción

### 5. Descargar contenido
- Solicita el ID del item
- Para películas: descarga directamente
- Para series: permite elegir entre:
  - Descargar todos los episodios
  - Descargar un episodio específico
- Muestra barra de progreso durante la descarga

### 6. Salir
- Cierra el programa

## Cómo obtener el ID de un item

1. Usa la opción de búsqueda (opción 1) o listado (opciones 2 o 3)
2. Copia el ID que aparece junto al contenido que quieres descargar
3. Usa ese ID en las opciones 4 o 5

## Ejemplo de uso

```bash
$ ./emby-manager.sh

╔═══════════════════════════════════════════════════════════════╗
║           GESTOR DE SERVIDOR EMBY                             ║
╚═══════════════════════════════════════════════════════════════╝

1) Buscar películas o series
2) Listar todas las películas
3) Listar todas las series
4) Ver información detallada (por ID)
5) Descargar contenido (por ID)
6) Salir

Selecciona una opción: 1

Ingresa el término de búsqueda: Matrix

¿Qué quieres buscar?
1) Películas
2) Series
3) Ambos
Opción: 1

[INFO] Buscando: Matrix

═══════════════════════════════════════════════════════════════
Resultados encontrados: 3
═══════════════════════════════════════════════════════════════

ID: abc123 | The Matrix (1999) - Movie
   Tamaño: 4.52 GB | Duración: 136 min

ID: def456 | The Matrix Reloaded (2003) - Movie
   Tamaño: 5.87 GB | Duración: 138 min
```

## Notas importantes

- El script se autentica automáticamente al iniciar
- El token de acceso se guarda en `emby.conf` para sesiones futuras
- **Películas**: Se descargan en el directorio actual con el nombre sanitizado
- **Series**: Se organizan automáticamente en carpetas:
  - `NombreSerie/Temporada_1/Episodio_01_NombreEpisodio.mkv`
  - `NombreSerie/Temporada_2/Episodio_01_NombreEpisodio.mkv`
- Los nombres de archivo se sanitizan automáticamente (caracteres especiales se reemplazan por guiones bajos)
- El formato del archivo (mkv, mp4, avi, etc.) se detecta automáticamente del servidor
- Las descargas muestran barra de progreso en tiempo real
- **Descarga inteligente**: Si un archivo ya existe, se salta automáticamente (útil para reanudar descargas interrumpidas)
- Los archivos grandes pueden tardar dependiendo de tu conexión a Internet

## Solución de problemas

### Error de autenticación
Verifica que las credenciales en `emby.conf` sean correctas.

### No se encuentra el servidor
Verifica que el host y puerto sean correctos y que tengas conexión a Internet.

### Falta jq o curl
Instala las dependencias necesarias:
```bash
sudo apt install curl jq
```

## Seguridad

- El archivo `emby.conf` contiene credenciales sensibles
- No compartas este archivo
- Asegúrate de que tenga permisos restrictivos:
  ```bash
  chmod 600 emby.conf
  ```
