#!/usr/bin/env python3
"""Create a made-up home folder for Deletable screenshots.

    python3 scripts/make-demo.py ~/deletable-demo
    open --env DELETABLE_DEMO_HOME=$HOME/deletable-demo /Applications/Deletable.app

Then use Home Folder on the start screen. Uses about 1.6 GB of real disk space
(files are filled with zeros); delete the folder when you're done.
"""
import os
import sys

MB = 1024 * 1024

# path: (total MB, number of files)
TREE = {
    "Library/Caches/com.spotify.client": (90, 12),
    "Library/Caches/com.google.Chrome": (60, 20),
    "Library/Caches/com.apple.Safari": (20, 10),
    "Library/Caches/Homebrew/downloads": (45, 6),
    "Library/Developer/Xcode/DerivedData/MyApp-fkqzbwhy/Build": (110, 30),
    "Library/Developer/Xcode/DerivedData/Widgets-dlpqrtme/Index.noindex": (30, 12),
    "Library/Developer/CoreSimulator/Devices/7F3A0C21/data": (75, 18),
    "Library/Application Support/Slack": (35, 9),
    "Library/Application Support/Code/User": (25, 8),
    "Library/Logs/DiagnosticReports": (8, 14),
    ".cache/huggingface/hub/models--mistralai--Mistral-7B/blobs": (130, 3),
    ".cache/huggingface/hub/models--openai--whisper-small/blobs": (40, 2),
    ".cache/uv/archive-v0": (70, 25),
    ".cache/pip/http": (15, 10),
    ".npm/_cacache/content-v2": (30, 40),
    "Movies/Holiday 2025": (120, 2),
    "Movies/Timelapse": (45, 3),
    "Pictures/Photos Library.photoslibrary/originals": (100, 40),
    "Downloads": (0, 0),
    "Documents/Thesis": (20, 12),
    "Documents/Invoices": (3, 15),
    "Projects/web-app/node_modules": (55, 60),
    "Projects/web-app/src": (1, 20),
    "Projects/web-app/.git/objects": (8, 15),
    "Projects/ml-experiments/.venv/lib": (45, 30),
    "Projects/ml-experiments/data": (30, 4),
    "Music/Music Library": (40, 20),
}

# Single files: path -> MB
FILES = {
    "Downloads/Xcode_16.xip": 90,
    "Downloads/Docker.dmg": 35,
    "Downloads/Blender-4.2.dmg": 30,
    "Downloads/annual-report.pdf": 2,
    "Movies/Holiday 2025/beach.mov": 60,
}

EXT = {"Movies": ".mov", "Pictures": ".heic", "Music": ".m4a", "Documents": ".pdf"}


def write(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    chunk = b"\0" * MB
    with open(path, "wb") as f:
        left = size
        while left > 0:
            n = min(left, MB)
            f.write(chunk[:n])
            left -= n


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = os.path.abspath(os.path.expanduser(sys.argv[1]))
    if os.path.exists(root) and os.listdir(root):
        sys.exit(f"{root} already exists and isn't empty")
    for rel, (total_mb, count) in TREE.items():
        folder = os.path.join(root, rel)
        os.makedirs(folder, exist_ok=True)
        ext = EXT.get(rel.split("/")[0], ".bin")
        for i in range(count):
            # Uneven sizes so the map looks like real data.
            weight = (count - i) ** 1.6
            norm = sum((count - j) ** 1.6 for j in range(count))
            write(os.path.join(folder, f"item-{i + 1:03d}{ext}"), int(total_mb * MB * weight / norm))
    for rel, mb in FILES.items():
        write(os.path.join(root, rel), mb * MB)
    print(f"Demo folder ready: {root}")


if __name__ == "__main__":
    main()
