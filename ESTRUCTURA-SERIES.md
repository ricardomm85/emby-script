# Estructura de Organización para Series

## 📁 Ejemplo de estructura generada

Cuando descargas una serie completa, el script crea automáticamente esta estructura:

```
Breaking_Bad/
├── Temporada_1/
│   ├── Episodio_01_Pilot.mkv
│   ├── Episodio_02_Cat_s_in_the_Bag___.mkv
│   ├── Episodio_03____and_the_Bag_s_in_the_River.mkv
│   ├── Episodio_04_Cancer_Man.mkv
│   ├── Episodio_05_Gray_Matter.mkv
│   ├── Episodio_06_Crazy_Handful_of_Nothin_.mkv
│   └── Episodio_07_A_No_Rough_Stuff_Type_Deal.mkv
│
├── Temporada_2/
│   ├── Episodio_01_Seven_Thirty_Seven.mkv
│   ├── Episodio_02_Grilled.mkv
│   ├── Episodio_03_Bit_by_a_Dead_Bee.mkv
│   └── ...
│
└── Temporada_3/
    ├── Episodio_01_No_Mas.mkv
    ├── Episodio_02_Caballo_Sin_Nombre.mkv
    └── ...
```

## 🎯 Ventajas de esta organización

✅ **Orden perfecto**: Los episodios siempre aparecen en orden numérico
✅ **Fácil navegación**: Puedes ir directamente a la temporada que quieres ver
✅ **Compatible**: Funciona con Plex, Jellyfin, Kodi y otros media servers
✅ **Limpio**: Cada serie en su propia carpeta

## 🔄 Descarga inteligente

Si interrumpes una descarga y la vuelves a ejecutar:

```
[AVISO] Archivo ya existe: Breaking_Bad/Temporada_1/Episodio_01_Pilot.mkv (1.2G)
[INFO] Saltando descarga...
[INFO] Descargando: Cat's in the Bag...
```

El script **automáticamente**:
- ✅ Detecta archivos ya descargados
- ✅ Muestra el tamaño del archivo existente
- ✅ Salta al siguiente episodio
- ✅ Solo descarga lo que falta

## 📝 Formato de nombres

### Para episodios:
```
Episodio_[NÚMERO]_[NOMBRE].mkv
```

Ejemplos:
- `Episodio_01_Pilot.mkv`
- `Episodio_15_The_One_Where_Everybody_Finds_Out.mkv`

### Para películas:
```
[NOMBRE].mkv
```

Ejemplos:
- `The_Matrix.mkv`
- `Avengers_Endgame.mkv`

## 🎬 Ejemplo de descarga de serie completa

```bash
./emby-manager.sh

# Selecciona opción 1 (Buscar)
Ingresa el término de búsqueda: breaking bad
Opción: 2  # Series

# Copia el ID de Breaking Bad
ID: 123456

# Selecciona opción 5 (Descargar)
Ingresa el ID del item: 123456

# Elige descargar todos los episodios
¿Qué deseas descargar?
1) Todos los episodios
Opción: 1

# El script descargará TODOS los episodios organizados automáticamente
```

## 💡 Tip para series largas

Para series con muchas temporadas, puedes:
1. Descargar episodio por episodio (opción 2 cuando te pregunte)
2. Pausar con `Ctrl+C` y reanudar después
3. Los archivos descargados se conservan y no se vuelven a descargar

## 🔍 Verificar lo descargado

```bash
# Ver estructura creada
tree Breaking_Bad/

# Ver tamaño total
du -sh Breaking_Bad/

# Ver tamaño por temporada
du -sh Breaking_Bad/Temporada_*/
```
