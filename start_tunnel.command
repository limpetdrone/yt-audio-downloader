#!/bin/bash
# 🎵 YouTube Audio Downloader - backend + tunnel launcher
#
# Starts server.py on port 8000 and exposes it to the iPhone app.
# For an address that never changes, create tunnel.conf next to this
# script (see tunnel.conf.example). Without it, a temporary
# trycloudflare.com address is used, which changes on every run.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR" || exit 1

PORT=8000
NGROK_DOMAIN=""
CF_TUNNEL_NAME=""
CF_HOSTNAME=""
API_KEY=""
[ -f "$DIR/tunnel.conf" ] && source "$DIR/tunnel.conf"

# Every request from the app must carry this key. Create one on first run.
if [ -z "$API_KEY" ]; then
    API_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
    printf '\n# Secret key the app must send (enter it in the app)\nAPI_KEY="%s"\n' "$API_KEY" >> "$DIR/tunnel.conf"
    echo "🔑 Created a new API key and saved it in tunnel.conf"
fi
export API_KEY
# Only accept connections from this Mac; the tunnel forwards the rest.
export HOST=127.0.0.1
export PORT

echo "========================================================"
echo "  🎵 Starting YouTube Audio Downloader Backend + Tunnel "
echo "========================================================"

# Create the Python environment on first run
if [ ! -x "$DIR/venv/bin/python" ]; then
    echo "[setup] Creating Python environment (first run only)..."
    python3 -m venv "$DIR/venv" || { echo "❌ python3 not found. Install it with: brew install python"; exit 1; }
    "$DIR/venv/bin/pip" install -r "$DIR/requirements.txt" || exit 1
fi

# Start the backend unless it is already running
BACKEND_PID=""
if ! lsof -i :$PORT > /dev/null; then
    echo "[1/2] Starting local Python backend on port $PORT..."
    "$DIR/venv/bin/python" "$DIR/server.py" &
    BACKEND_PID=$!
    sleep 2
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo "❌ Backend failed to start. See the error above."
        exit 1
    fi
else
    echo "[1/2] Local Python backend is already running on port $PORT."
fi

# Stop the backend we started when this window closes
cleanup() { [ -n "$BACKEND_PID" ] && kill "$BACKEND_PID" 2>/dev/null; }
trap cleanup EXIT

if ! curl -fs -H "X-API-Key: $API_KEY" "http://localhost:$PORT/health" > /dev/null; then
    echo "❌ Backend is not answering on http://localhost:$PORT/health"
    exit 1
fi

show_url() {
    echo "--------------------------------------------------------"
    echo "👉 Enter these in the iPhone app:"
    echo ""
    echo "     $1"
    echo ""
    echo "   API key:"
    echo ""
    echo "     $API_KEY"
    echo ""
    echo "--------------------------------------------------------"
}

if [ -n "$NGROK_DOMAIN" ]; then
    command -v ngrok > /dev/null || { echo "❌ ngrok not found. Install it with: brew install ngrok"; exit 1; }
    echo "[2/2] Starting ngrok on your permanent address..."
    show_url "https://$NGROK_DOMAIN"
    ngrok http --url="$NGROK_DOMAIN" $PORT --log=stdout --log-level=warn

elif [ -n "$CF_TUNNEL_NAME" ]; then
    command -v cloudflared > /dev/null || { echo "❌ cloudflared not found. Install it with: brew install cloudflared"; exit 1; }
    echo "[2/2] Starting Cloudflare tunnel '$CF_TUNNEL_NAME'..."
    [ -n "$CF_HOSTNAME" ] && show_url "https://$CF_HOSTNAME"
    cloudflared tunnel run --url "http://localhost:$PORT" "$CF_TUNNEL_NAME"

else
    command -v cloudflared > /dev/null || { echo "❌ cloudflared not found. Install it with: brew install cloudflared"; exit 1; }
    echo "[2/2] Starting temporary Cloudflare tunnel..."
    echo "⚠️  This address changes on every run. Set NGROK_DOMAIN in tunnel.conf for a permanent one."
    cloudflared tunnel --url "http://localhost:$PORT" 2>&1 | while IFS= read -r line; do
        case "$line" in *ERR*) echo "$line" ;; esac
        url=$(echo "$line" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | grep -v '://api\.')
        if [ -n "$url" ]; then
            show_url "$url"
            printf '%s' "$url" | pbcopy 2>/dev/null && echo "📋 Copied to clipboard. Paste it into the app and press Save."
        fi
    done
fi
