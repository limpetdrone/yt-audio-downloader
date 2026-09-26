#!/bin/bash
# 🎵 YouTube Audio Downloader - Cloudflare Tunnel Launcher

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "========================================================"
echo "  🎵 Starting YouTube Audio Downloader Backend + Tunnel "
echo "========================================================"

# Check if server is running on port 8000
if ! lsof -i :8000 > /dev/null; then
    echo "[1/2] Starting local Python backend on port 8000..."
    "$DIR/venv/bin/python" "$DIR/server.py" &
    sleep 2
else
    echo "[1/2] Local Python backend is already running on port 8000."
fi

echo "[2/2] Starting Cloudflare Tunnel..."
echo "--------------------------------------------------------"
echo "👉 Note: Copy the https://....trycloudflare.com URL below"
echo "   and paste it into your iPhone app if it changes."
echo "--------------------------------------------------------"

cloudflared tunnel --url http://localhost:8000
