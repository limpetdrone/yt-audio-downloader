# YouTube MP3 Downloader (Desktop GUI)

A lightweight and intuitive desktop application to extract and download high-quality MP3 audio tracks directly from YouTube videos.

## Features
- 📋 **One-click Paste**: Quickly paste URLs from clipboard.
- 📁 **Custom Output Folder**: Default is `~/Downloads`, customizable with directory picker.
- 🎚️ **Bitrate Quality Selection**: 320 kbps (best), 256 kbps, 192 kbps, or 128 kbps.
- 📊 **Real-time Progress Indicator**: Shows percentage, download speed, and estimated time remaining.
- ⚡ **Non-blocking UI**: Asynchronous background threading prevents interface freezes.
- 📂 **Direct Finder Access**: Button to immediately reveal the downloaded MP3 in Finder.
- 🔒 **macOS SSL & Runtime Support**: Built-in support for CA certificates and Node.js runtime.

## Quick Start

### 1. From Terminal:
```bash
./run.sh
```

### 2. From macOS Finder:
Simply double-click `start.command`.

## Requirements
- Python 3.9+
- FFmpeg (`brew install ffmpeg`)
- Node.js (`brew install node`)

## iPhone app: backend + tunnel

The iPhone app downloads through `server.py` running on your Mac. Start it with
`start_tunnel.command` (double-click in Finder). The script creates the Python
environment on first run, starts the backend, checks it answers, then opens a tunnel.

### Permanent server address

By default the tunnel is a temporary `trycloudflare.com` address that changes on
every run (the script prints it and copies it to the clipboard). To get an address
that never changes, so you only enter it in the app once:

1. Copy `tunnel.conf.example` to `tunnel.conf`.
2. Fill in one option:
   - **ngrok** (free, no own domain needed): sign up at ngrok.com, run
     `brew install ngrok && ngrok config add-authtoken <token>`, claim the free
     static domain in the ngrok dashboard, and put it in `NGROK_DOMAIN`.
   - **Cloudflare named tunnel** (needs your own domain on Cloudflare): set
     `CF_TUNNEL_NAME` and `CF_HOSTNAME` (setup commands are in the example file).
3. Run `start_tunnel.command`, paste the printed address into the app once and press Save.
