#!/bin/bash
# Double-click to rebuild Deletable from this folder and reinstall it in /Applications.
cd "$(dirname "$0")" && ./build.sh --install
echo; echo "Done — you can close this window."
