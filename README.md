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
