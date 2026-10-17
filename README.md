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

## iPhone app: download through your Mac

The iPhone app downloads through `server.py` running on your Mac, reachable over a
secure ngrok address. Every request must carry a secret key (`X-API-Key` header),
otherwise the server answers 401. The server only listens on localhost; ngrok forwards to it.

### Easiest: the Mac app does it

1. Sign up at ngrok.com (free), install it with `brew install ngrok`, and copy your
   authtoken and free static domain from the ngrok dashboard.
2. In the Mac app, open **iPhone Access**, paste the authtoken and domain, and press
   **Start Sharing**. Turn on "Start automatically" if you like.
3. Scan the QR code with the iPhone camera. The iPhone app opens and saves the
   address and key.

The Mac app needs Python 3 with `yt-dlp` and `certifi` installed
(`python3 -m pip install yt-dlp certifi`), plus `ffmpeg` and `node` from Homebrew.

### Without the Mac app: start_tunnel.command

Double-click `start_tunnel.command`. It creates the Python environment on first run,
creates a key in `tunnel.conf`, starts the backend, checks it answers, then opens a
tunnel and prints the address and key to enter in the iPhone app.

For an address that never changes, copy `tunnel.conf.example` to `tunnel.conf` and set
`NGROK_DOMAIN` (or a Cloudflare named tunnel). Without it, a temporary
`trycloudflare.com` address is used, which changes on every run.

### Building

`apple/upload_to_testflight.sh` regenerates the Xcode project with XcodeGen (needed,
because new files like `ServerManager.swift` and the bundled `server.py` are listed in
`project.yml`), then archives and uploads both apps.
