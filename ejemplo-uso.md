# Ejemplo de Uso: Buscar y Descargar

## Paso 1: Ejecutar el script

```bash
./emby-manager.sh
```

## Paso 2: Buscar contenido

Selecciona la opción **1** (Buscar películas o series)

```
Selecciona una opción: 1

Ingresa el término de búsqueda: toy story toons

¿Qué quieres buscar?
1) Películas
2) Series
3) Ambos
Opción: 1
```

**Resultado:**
```
═══════════════════════════════════════════════════════════════
Resultados encontrados: 3
═══════════════════════════════════════════════════════════════

ID: 443061
Título: Toy Story Toons: Fiestasaurio Rex
Tipo: Movie
Año: N/A
Duración: 6 minutos
───────────────────────────────────────────────────────────────
ID: 443062
Título: Toy Story Toons: Pequeño gran Buzz
Tipo: Movie
Año: N/A
Duración: 7 minutos
───────────────────────────────────────────────────────────────
ID: 443063
Título: Toy Story Toons: Vacaciones en Hawái
Tipo: Movie
Año: N/A
Duración: 5 minutos
───────────────────────────────────────────────────────────────
```

## Paso 3: Copiar el ID

Copia el **ID** del contenido que quieres descargar. Por ejemplo: `443061`

## Paso 4: Descargar

Selecciona la opción **5** (Descargar contenido)

```
Selecciona una opción: 5

═══════════════════════════════════════════════════════════════
Ingresa el ID del item:
═══════════════════════════════════════════════════════════════
> 443061
```

**IMPORTANTE**: Escribe el ID después del símbolo `>` y presiona Enter

**Proceso de descarga:**
```
[INFO] Obteniendo información del archivo...
[INFO] Descargando: Toy Story Toons: Fiestasaurio Rex
Formato: mkv
Archivo: Toy_Story_Toons__Fiestasaurio_Rex.mkv

######################################################################## 100.0%

[OK] Descarga completada: Toy_Story_Toons__Fiestasaurio_Rex.mkv (44M)
```

## Notas importantes

### Películas vs Series

- **Películas**: Se descargan directamente
- **Series**: Te preguntará si quieres:
  1. Todos los episodios
  2. Un episodio específico
  3. Cancelar

### Formato de archivo

El script detecta automáticamente el formato del archivo (mkv, mp4, avi, etc.) y lo guarda con la extensión correcta.

### Nombres de archivo

Los caracteres especiales en los nombres se reemplazan por guiones bajos (_) para evitar problemas en el sistema de archivos.

Ejemplo:
- `¡A Ganar! (2018)` → `_A_Ganar___2018_.mkv`

### Ubicación de descargas

Los archivos se guardan en el directorio actual desde donde ejecutas el script.

## Tips

1. **Busca primero**: Usa la búsqueda o listado para encontrar el ID del contenido
2. **Copia el ID**: Anota el ID que aparece en los resultados
3. **Descarga**: Usa el ID en la opción de descarga
4. **Ver información**: Antes de descargar, puedes usar la opción 4 para ver información detallada

## Solución de problemas

### La descarga se queda parada
- ✅ **SOLUCIONADO**: Ahora usa el endpoint correcto de streaming
- Los archivos grandes pueden tardar dependiendo de tu conexión

### No encuentra el contenido
- Verifica que el término de búsqueda sea correcto
- Prueba buscando en "Ambos" (películas y series)
- Usa la opción 2 o 3 para listar toda la biblioteca

### El archivo no tiene la extensión correcta
- ✅ **SOLUCIONADO**: Ahora detecta automáticamente el formato del servidor
