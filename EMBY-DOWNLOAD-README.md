# Emby Download Manager

Script en Python para descargar películas y series de Jellyfin/Emby con soporte para pausar y reanudar descargas.

## Características

- ✅ **Descarga con resume** - Si se corta, continúa desde donde se quedó
- ✅ **Estado persistente** - Guarda progreso en `download_progress.json`
- ✅ **Multi-cola** - Gestiona varias descargas
- ✅ **Progreso en tiempo real** - Muestra porcentaje y bytes descargados
- ✅ **CLI completa** - Buscar, descargar, comprobar estado, reanudar

## Requisitos

```bash
pip install requests
```

## Uso

### Buscar películas/series

```bash
./emby-download.py search "matrix"
./emby-download.py search "downfall" --year 2004
./emby-download.py search "breaking bad" --json
```

### Iniciar descarga

```bash
./emby-download.py download <item_id> --dest /path/to/destination
```

Ejemplo:
```bash
./emby-download.py download 258628 --dest /home/ricardo/jellyfin/movies
```

### Ver estado de descargas

```bash
# Todas las descargas
./emby-download.py status

# Descarga específica
./emby-download.py status --id <download_id>
```

### Listar descargas con IDs

```bash
./emby-download.py list
```

### Reanudar descarga interrumpida

```bash
./emby-download.py resume <download_id>
```

## Estado de descargas

Los estados posibles son:

- **pending** - En cola, aún no comenzada
- **downloading** - Descargando
- **completed** - Completada correctamente
- **error** - Error en la descarga

## Archivos

- `emby.conf` - Configuración del servidor Jellyfin
- `emby-download.py` - Script principal
- `download_progress.json` - Estado de descargas (se crea automáticamente)

## Ejemplo de flujo completo

```bash
# 1. Buscar la película
./emby-download.py search "el hundimiento" --year 2004

# 2. Iniciar descarga (usando el ID devuelto)
./emby-download.py download 258628 --dest /home/ricardo/jellyfin/movies

# 3. (Opcional) Comprobar estado en otra terminal
./emby-download.py status

# 4. (Opcional) Si se corta, reanudar
./emby-download.py list  # Obtener el ID de descarga
./emby-download.py resume <download_id>
```

## Ventajas sobre emby-cli.sh

1. **Resume automático** - HTTP Range para continuar descargas parciales
2. **Estado en JSON** - Fácil de consultar programáticamente
3. **Python requests** - Más robusto que curl para descargas largas
4. **Progreso granular** - Actualización en tiempo real del progreso
5. **Multi-cola** - Puedes gestionar varias descargas simultáneamente

## Troubleshooting

### Error "Configuración incompleta en emby.conf"

Verifica que `emby.conf` tenga:
- `EMBY_HOST`
- `EMBY_PORT`
- `EMBY_TOKEN`
- `EMBY_USER_ID`

### La descarga se corta frecuentemente

- El script guarda el progreso en cada chunk (8 KB)
- Simplemente ejecuta `resume <download_id>` para continuar
- No pierdes el progreso acumulado

### Verificar progreso manual

El archivo `download_progress.json` contiene toda la información:

```json
{
  "downloads": {
    "258628_1234567890": {
      "status": "downloading",
      "progress": 23.5,
      "downloaded_bytes": 1234567890,
      "total_bytes": 60000000000,
      ...
    }
  }
}
```
