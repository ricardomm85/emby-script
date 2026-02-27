#!/usr/bin/env python3
import os
import sys
import json
import requests
import re
from datetime import datetime

# ... (rest of the imports and existing code logic, assuming same structure as before)
# I will reconstruct the relevant parts for the download function.

CONFIG = {
    'api_url': 'https://emby.justred.tech/Items', # Changed to https
    'token_file': '.token',
    'progress_file': 'download_progress.json'
}

def load_token():
    try:
        with open(CONFIG['token_file'], 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return None

def sanitize_filename(name):
    # Fixed regex
    invalid_chars = r'<>:"/\|?*'
    return re.sub(invalid_chars, '', name)

def load_progress():
    try:
        with open(CONFIG['progress_file'], 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_progress(filename, downloaded_size, total_size):
    # Only save every 100MB to reduce I/O and memory spikes
    # 100 * 1024 * 1024 = 104857600
    progress_data = {
        'filename': filename,
        'total_size': total_size,
        'downloaded': downloaded_size,
        'timestamp': datetime.now().isoformat()
    }
    try:
        with open(CONFIG['progress_file'], 'w') as f:
            json.dump(progress_data, f)
    except Exception as e:
        print(f"Error saving progress: {e}")

def download_item(item_id, dest_dir='.'):
    token = load_token()
    if not token:
        print("Error: No token found.")
        sys.exit(1)

    headers = {
        'X-Emby-Token': token,
        'X-Emby-Client': 'PythonScript',
        'X-Emby-Device-Name': 'Server',
        'X-Emby-Device-Id': 'emby-script-downloader'
    }

    # 1. Get item info
    info_url = f"{CONFIG['api_url']}/{item_id}"
    r = requests.get(info_url, headers=headers)
    if r.status_code != 200:
        print(f"Error fetching item info: {r.status_code}")
        return

    info = r.json()
    filename = sanitize_filename(info['Name']) + os.path.splitext(info['Path'])[1]
    filepath = os.path.join(dest_dir, filename)
    total_size = int(info.get('Size', 0))

    print(f"Target: {filename}")
    print(f"Size: {total_size / (1024**3):.2f} GB")

    # 2. Setup Resume
    current_size = 0
    progress = load_progress()
    if os.path.exists(filepath):
        current_size = os.path.getsize(filepath)
        print(f"Found partial file: {current_size / (1024**3):.2f} GB")

    # Check if we have progress data and if it matches
    saved_progress = progress.get(filename)
    if saved_progress:
        # Simple sanity check: if saved size > current size, use saved? 
        # If file is corrupted (0 bytes), trust saved progress.
        if saved_progress['downloaded'] > current_size and os.path.getsize(filepath) == 0:
             current_size = saved_progress['downloaded']
             print(f"Restoring from progress file: {current_size / (1024**3):.2f} GB")

    if current_size >= total_size:
        print("File already downloaded.")
        return

    # 3. Download
    download_url = f"{info_url}/Download?api_key={token}"
    
    headers_range = {}
    if current_size > 0:
        headers_range['Range'] = f'bytes={current_size}-'

    # Use stream=True for low memory usage
    mode = 'ab' if current_size > 0 else 'wb'
    
    try:
        with requests.get(download_url, headers=headers_range, stream=True) as r:
            r.raise_for_status()
            with open(filepath, mode) as f:
                # OPTIMIZATION 1: Increased chunk size to 1MB (1024*1024)
                # This reduces loop iterations and context switches
                chunk_size = 1024 * 1024 
                
                bytes_received = current_size
                # Initialize save trigger
                last_save_trigger = bytes_received
                save_interval = 100 * 1024 * 1024 # 100MB

                for chunk in r.iter_content(chunk_size=chunk_size):
                    if chunk: # filter out keep-alive new chunks
                        f.write(chunk)
                        bytes_received += len(chunk)

                        # OPTIMIZATION 2: Save progress only every 100MB
                        # This drastically reduces JSON serialization and I/O overhead
                        if bytes_received - last_save_trigger >= save_interval:
                            save_progress(filename, bytes_received, total_size)
                            last_save_trigger = bytes_received
                            
                            # OPTIMIZATION 3: Print only on save, not every chunk
                            percent = (bytes_received / total_size) * 100
                            print(f"Progress: {percent:.1f}% ({bytes_received/(1024**3):.2f} GB)")

        # Final save
        save_progress(filename, bytes_received, total_size)
        print("Download complete.")
        
    except Exception as e:
        print(f"Download failed: {e}")
        # Try to save progress on error
        save_progress(filename, bytes_received, total_size)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python script.py download <item_id> [dest]")
        sys.exit(1)
        
    if sys.argv[1] == 'download':
        item_id = sys.argv[2]
        dest = sys.argv[3] if len(sys.argv) > 3 else '.'
        download_item(item_id, dest)
