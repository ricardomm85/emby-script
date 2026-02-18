#!/usr/bin/env python3
"""
Emby Download Manager (Fixed)
Arreglado para evitar OOM (Out Of Memory) al guardar progreso demasiado seguido.
"""

import argparse
import json
import os
import sys
import time
import requests
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any

# Configuración
CONFIG_FILE = Path(__file__).parent / "emby.conf"
PROGRESS_FILE = Path(__file__).parent / "download_progress.json"
DEFAULT_TIMEOUT = 300  # 5 minutos
CHUNK_SIZE = 8192  # 8 KB chunks para streaming
# NUEVO: Guardar progreso cada 10 MB descargados (en lugar de cada 8 KB)
SAVE_INTERVAL_BYTES = 10 * 1024 * 1024  # 10 MB

class EmbyClient:
    """Cliente para conectar con servidor Emby/Jellyfin"""

    def __init__(self):
        self.load_config()

    def load_config(self):
        """Cargar configuración desde emby.conf"""
        if not CONFIG_FILE.exists():
            raise FileNotFoundError(f"No existe: {CONFIG_FILE}")

        config = {}
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    config[key.strip()] = value.strip().strip('"')

        self.host = config.get("EMBY_HOST")
        self.port = config.get("EMBY_PORT", "8096")
        self.token = config.get("EMBY_TOKEN")
        self.user_id = config.get("EMBY_USER_ID")

        if not all([self.host, self.token, self.user_id]):
            raise ValueError("Configuración incompleta en emby.conf")

        self.base_url = f"http://{self.host}:{self.port}/emby"

    def search(self, query: str, year: Optional[int] = None) -> List[Dict]:
        """Buscar películas o series"""
        url = f"{self.base_url}/Users/{self.user_id}/Items"
        params = {
            "searchTerm": query,
            "includeItemTypes": "Movie,Series",
            "recursive": True,
            "api_key": self.token
        }
        if year:
            params["years"] = year

        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()

        results = []
        for item in data.get("Items", []):
            results.append({
                "id": item["Id"],
                "name": item["Name"],
                "type": item["Type"],
                "year": item.get("ProductionYear"),
                "size": item.get("Size", 0)
            })

        return results

    def get_item(self, item_id: str) -> Dict:
        """Obtener detalles de un item"""
        url = f"{self.base_url}/Users/{self.user_id}/Items/{item_id}"
        params = {"api_key": self.token}

        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        return response.json()

    def get_stream_url(self, item_id: str) -> str:
        """Obtener URL de descarga/streaming"""
        return f"{self.base_url}/Videos/{item_id}/stream?static=true&api_key={self.token}"


class DownloadManager:
    """Gestor de descargas con estado persistente"""

    def __init__(self):
        self.client = EmbyClient()
        self.progress = self.load_progress()

    def load_progress(self) -> Dict:
        """Cargar estado de descargas desde JSON"""
        if PROGRESS_FILE.exists():
            with open(PROGRESS_FILE) as f:
                return json.load(f)
        return {"downloads": {}}

    def save_progress(self):
        """Guardar estado de descargas"""
        # NOTA: Ahora solo se llama periódicamente, no en cada chunk
        try:
            with open(PROGRESS_FILE, "w") as f:
                # Usamos indent para legibilidad, pero es menos frecuente ahora
                json.dump(self.progress, f, indent=2)
        except Exception as e:
            print(f"\n⚠️  Error guardando progreso: {e}", file=sys.stderr)

    def add_download(self, item_id: str, dest: str) -> str:
        """Agregar nueva descarga a la cola"""
        item = self.client.get_item(item_id)

        download_id = f"{item_id}_{int(time.time())}"
        filename = f"{self.clean_filename(item['Name'])}.{item.get('Container', 'mkv')}"
        temp_path = Path(dest) / f"{filename}.download"
        final_path = Path(dest) / filename

        self.progress["downloads"][download_id] = {
            "item_id": item_id,
            "name": item["Name"],
            "dest": dest,
            "filename": filename,
            "temp_path": str(temp_path),
            "final_path": str(final_path),
            "total_bytes": item.get("Size", 0),
            "downloaded_bytes": 0,
            "status": "pending",
            "created_at": datetime.now().isoformat(),
            "completed_at": None
        }

        self.save_progress()
        return download_id

    def clean_filename(self, name: str) -> str:
        """Limpiar nombre de archivo"""
        invalid_chars = '<>:"/\|?*'
        for char in invalid_chars:
            name = name.replace(char, "_")
        return name

    def download(self, download_id: str):
        """Ejecutar descarga con resume capability"""
        if download_id not in self.progress["downloads"]:
            raise ValueError(f"Descarga no encontrada: {download_id}")

        dl = self.progress["downloads"][download_id]
        dl["status"] = "downloading"

        url = self.client.get_stream_url(dl["item_id"])
        temp_path = Path(dl["temp_path"])
        final_path = Path(dl["final_path"])

        # Crear directorio destino
        temp_path.parent.mkdir(parents=True, exist_ok=True)

        # Comprobar si existe archivo parcial (resume)
        downloaded = 0
        if temp_path.exists():
            downloaded = temp_path.stat().st_size

        headers = {}
        if downloaded > 0:
            headers["Range"] = f"bytes={downloaded}-"

        # Obtener tamaño total si no lo tenemos
        if dl["total_bytes"] == 0:
            try:
                response = requests.head(url, headers=headers, timeout=30)
                dl["total_bytes"] = int(response.headers.get("Content-Length", 0))
            except Exception as e:
                print(f"\n⚠️  No se pudo obtener tamaño total: {e}")

        dl["downloaded_bytes"] = downloaded
        self.save_progress()

        # Descargar
        mode = "ab" if downloaded > 0 else "wb"

        try:
            # Aumentar timeout para archivos grandes
            # requests.get mantiene la conexión abierta con timeout. Si el servidor tarda mucho en enviar un byte, corta.
            # 300 segundos es bastante, pero para 56GB es razonable.
            with requests.get(url, headers=headers, stream=True, timeout=DEFAULT_TIMEOUT) as r:
                r.raise_for_status()

                total = dl["total_bytes"]
                next_save = downloaded + SAVE_INTERVAL_BYTES  # Próximo momento para guardar

                with open(temp_path, mode) as f:
                    for chunk in r.iter_content(chunk_size=CHUNK_SIZE):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                            
                            # Actualizar progreso en memoria (rápido)
                            dl["downloaded_bytes"] = downloaded
                            dl["progress"] = (downloaded / total * 100) if total > 0 else 0

                            # Guardar progreso en disco SOLO si pasa el intervalo (ahorrando RAM y Disco)
                            if downloaded >= next_save or downloaded >= total:
                                self.save_progress()
                                next_save = downloaded + SAVE_INTERVAL_BYTES

                            # Mostrar progreso (limitar frecuencia de print no afecta tanto, pero visualmente es mejor)
                            # Opcional: Solo imprimir cada 1% o cada MB para no saturar stdout
                            if (downloaded % (1024 * 1024)) == 0: # Cada 1 MB
                                print(f"\r  {dl['name']}: {dl['progress']:.1f}% ({downloaded}/{total} bytes)", end="", flush=True)

            # Completar descarga
            temp_path.rename(final_path)
            dl["status"] = "completed"
            dl["completed_at"] = datetime.now().isoformat()
            self.save_progress()  # Guardado final obligatorio

            size_gb = final_path.stat().st_size / (1024**3)
            print(f"\n✓  Descargado: {final_path} ({size_gb:.2f} GB)")

        except requests.exceptions.Timeout:
            dl["status"] = "error"
            dl["error"] = "Timeout de conexión"
            self.save_progress()
            print(f"\n✗  Error: Timeout de conexión (el servidor tardó demasiado en enviar datos)")
            raise
        except Exception as e:
            dl["status"] = "error"
            dl["error"] = str(e)
            self.save_progress()
            print(f"\n✗  Error: {e}")
            raise

    def status(self, download_id: Optional[str] = None):
        """Mostrar estado de descargas"""
        if download_id:
            if download_id not in self.progress["downloads"]:
                print(f"Descarga no encontrada: {download_id}")
                return
            downloads = [self.progress["downloads"][download_id]]
        else:
            downloads = list(self.progress["downloads"].values())

        if not downloads:
            print("No hay descargas en progreso o completadas.")
            return

        print("\n📥  Descargas:")
        print("-" * 80)

        for dl in downloads:
            status_icon = {
                "pending": "⏳",
                "downloading": "⬇️",
                "completed": "✓",
                "error": "✗"
            }.get(dl["status"], "?")

            progress = dl.get("progress", 0)
            total_gb = dl["total_bytes"] / (1024**3) if dl["total_bytes"] else 0

            print(f"{status_icon}  {dl['name']}")
            print(f"   Estado: {dl['status']}")
            print(f"   Progreso: {progress:.1f}% ({total_gb:.2f} GB)")
            print(f"   Destino: {dl['final_path']}")

            if dl["status"] == "downloading":
                downloaded_gb = dl["downloaded_bytes"] / (1024**3)
                print(f"   Descargado: {downloaded_gb:.2f} GB")

            if dl["status"] == "error":
                print(f"   Error: {dl.get('error', 'Unknown')}")

            print()

    def resume(self, download_id: str):
        """Reanudar descarga interrumpida"""
        if download_id not in self.progress["downloads"]:
            raise ValueError(f"Descarga no encontrada: {download_id}")

        dl = self.progress["downloads"][download_id]

        if dl["status"] == "completed":
            print(f"La descarga ya está completada: {dl['name']}")
            return

        if dl["status"] == "pending":
            print(f"La descarga aún no ha comenzado: {dl['name']}")
            return

        print(f"Reanudando descarga: {dl['name']}")
        self.download(download_id)

    def list_downloads(self):
        """Listar todas las descargas con IDs"""
        downloads = self.progress["downloads"]

        if not downloads:
            print("No hay descargas registradas.")
            return

        print("\n📥  Descargas registradas:")
        print("-" * 80)

        for dl_id, dl in downloads.items():
            status_icon = {
                "pending": "⏳",
                "downloading": "⬇️",
                "completed": "✓",
                "error": "✗"
            }.get(dl["status"], "?")

            print(f"{status_icon}  [{dl_id[:12]}...] {dl['name']} ({dl['status']})")

        print()


def main():
    parser = argparse.ArgumentParser(description="Emby Download Manager (Fixed)")
    subparsers = parser.add_subparsers(dest="command", help="Comando a ejecutar")

    # Search
    search_parser = subparsers.add_parser("search", help="Buscar películas o series")
    search_parser.add_argument("query", help="Término de búsqueda")
    search_parser.add_argument("--year", type=int, help="Filtrar por año")
    search_parser.add_argument("--json", action="store_true", help="Salida JSON")

    # Download
    download_parser = subparsers.add_parser("download", help="Iniciar descarga")
    download_parser.add_argument("item_id", help="ID del item")
    download_parser.add_argument("--dest", "-d", default=".", help="Directorio destino")

    # Status
    status_parser = subparsers.add_parser("status", help="Ver estado de descargas")
    status_parser.add_argument("--id", help="ID específico de descarga")

    # Resume
    resume_parser = subparsers.add_parser("resume", help="Reanudar descarga")
    resume_parser.add_argument("download_id", help="ID de descarga")

    # List
    list_parser = subparsers.add_parser("list", help="Listar descargas registradas")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    manager = DownloadManager()

    try:
        if args.command == "search":
            results = manager.client.search(args.query, args.year)

            if args.json:
                print(json.dumps(results, indent=2))
            else:
                if not results:
                    print(f"No se encontraron resultados para: {args.query}")
                    return

                print(f"\n📺  Resultados para '{args.query}':")
                print("-" * 80)

                for item in results:
                    size_gb = item["size"] / (1024**3) if item["size"] else 0
                    print(f"  [{item['id']}] {item['name']} ({item.get('year', 'N/A')})")
                    print(f"      Tipo: {item['type']} | Tamaño: {size_gb:.2f} GB")
                    print()

        elif args.command == "download":
            download_id = manager.add_download(args.item_id, args.dest)
            print(f"\nDescarga iniciada: {download_id}")
            manager.download(download_id)

        elif args.command == "status":
            manager.status(getattr(args, "id", None))

        elif args.command == "resume":
            manager.resume(args.download_id)

        elif args.command == "list":
            manager.list_downloads()

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
