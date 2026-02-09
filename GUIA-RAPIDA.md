# Guía Rápida - Script Emby

## ¿Cómo descargar una película o serie?

### 1️⃣ Ejecuta el script
```bash
./emby-manager.sh
```

### 2️⃣ Busca el contenido (Opción 1)
```
Selecciona una opción: 1

Ingresa el término de búsqueda: matrix
```

### 3️⃣ Copia el ID que aparece en los resultados
```
═══════════════════════════════════════════════════════════════
Resultados encontrados: 13
═══════════════════════════════════════════════════════════════

ID: 514548 | Matrix (1999) - Movie     👈 ESTE ES EL ID
   Tamaño: 4.52 GB | Duración: 136 min
```

### 4️⃣ Descarga con el ID (Opción 5)
```
Selecciona una opción: 5

═══════════════════════════════════════════════════════════════
Ingresa el ID del item:
═══════════════════════════════════════════════════════════════
> 514548            👈 ESCRIBE EL ID AQUÍ Y PRESIONA ENTER
```

### 5️⃣ Espera a que se descargue
```
[INFO] Obteniendo información del archivo...
[INFO] Descargando: Matrix
Formato: mkv
Archivo: Matrix.mkv

######################################################################## 100.0%

[OK] Descarga completada: Matrix.mkv (4.9G)
```

## 🔍 Ver información antes de descargar (Opción 4)

Usa la opción 4 con el mismo ID para ver información detallada:

```
Selecciona una opción: 4

═══════════════════════════════════════════════════════════════
Ingresa el ID del item:
═══════════════════════════════════════════════════════════════
> 514548

═══════════════════════════════════════════════════════════════
Información Detallada
═══════════════════════════════════════════════════════════════
Título: Matrix
Tipo: Movie
Año: 1999
Clasificación: R
Duración: 136 minutos
Géneros: Acción, Ciencia ficción
───────────────────────────────────────────────────────────────
Descripción:
Thomas Anderson lleva una doble vida: por el día es programador
en una importante empresa de software, y por la noche un hacker
informático llamado Neo...
═══════════════════════════════════════════════════════════════
```

## 📋 Listar todo el contenido

- **Opción 2**: Lista todas las películas (primeras 50)
- **Opción 3**: Lista todas las series (primeras 50)

## ⚡ Tips

✅ **Primero busca** → Obtén el ID
✅ **Luego descarga** → Usa el ID en opción 5
✅ **Películas** → Se guardan en el directorio actual
✅ **Series** → Se organizan automáticamente:
   - Carpeta por serie
   - Subcarpeta por temporada (Temporada_1, Temporada_2, etc.)
   - Episodios con número: `Episodio_01_NombreDelEpisodio.mkv`
✅ **Descarga inteligente** → Si el archivo ya existe, se salta automáticamente
✅ **Reanudar descargas** → Puedes volver a ejecutar el mismo comando sin problema

## ❌ Errores comunes

### "Debes ingresar un ID"
- No escribiste ningún ID
- Escribe el número del ID y presiona Enter

### "No se pudo obtener información del item"
- El ID es incorrecto
- Verifica que copiaste bien el ID

### "Error al descargar el archivo"
- Problema de conexión
- Verifica tu conexión a Internet
- Intenta de nuevo más tarde

## 🎯 Ejemplo completo

```bash
# 1. Ejecutar script
./emby-manager.sh

# 2. Opción 1 → Buscar "avengers"
# 3. Copiar ID: 123456
# 4. Opción 5 → Ingresar: 123456
# 5. Esperar descarga
# 6. Archivo guardado: Avengers.mkv
```

¡Así de simple!
