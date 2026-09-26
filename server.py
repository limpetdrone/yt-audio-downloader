#!/usr/bin/env python3
"""
Lightweight Downloader Backend Server
Processes YouTube audio extraction and streams MP3s to iOS and macOS apps.
"""

import os
import sys
import json
import shutil
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
import certifi
import yt_dlp

os.environ['SSL_CERT_FILE'] = certifi.where()
os.environ['REQUESTS_CA_BUNDLE'] = certifi.where()

PORT = int(os.environ.get('PORT', 8000))

class DownloadHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, HEAD, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

    def do_GET(self):
        if self.path == '/health' or self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "service": "YT Audio Cloud Backend"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/download':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode('utf-8'))
                video_url = data.get('url', '').strip()
                quality = data.get('quality', '320')

                media_type = data.get('type', 'audio')

                if not video_url:
                    self.send_error(400, "Missing URL")
                    return

                print(f"[Backend] Starting download for: {video_url} (Type: {media_type}, Quality: {quality} kbps)")

                with tempfile.TemporaryDirectory() as tmpdir:
                    out_template = os.path.join(tmpdir, '%(title)s.%(ext)s')
                    
                    if media_type == 'video':
                        ydl_opts = {
                            'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
                            'outtmpl': out_template,
                            'nocheckcertificate': True,
                            'quiet': True,
                            'no_warnings': True,
                        }
                    else:
                        ydl_opts = {
                            'format': 'bestaudio/best',
                            'outtmpl': out_template,
                            'nocheckcertificate': True,
                            'postprocessors': [
                                {
                                    'key': 'FFmpegExtractAudio',
                                    'preferredcodec': 'mp3',
                                    'preferredquality': quality,
                                },
                                {
                                    'key': 'FFmpegMetadata',
                                    'add_metadata': True,
                                }
                            ],
                            'quiet': True,
                            'no_warnings': True,
                        }

                    ffmpeg_path = shutil.which("ffmpeg") or "/usr/bin/ffmpeg" or "/opt/homebrew/bin/ffmpeg"
                    if os.path.exists(ffmpeg_path):
                        ydl_opts['ffmpeg_location'] = os.path.dirname(ffmpeg_path)

                    node_path = shutil.which("node") or "/usr/bin/node" or "/opt/homebrew/bin/node"
                    if os.path.exists(node_path):
                        ydl_opts['js_runtimes'] = {'node': {'path': node_path}}

                    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                        info = ydl.extract_info(video_url, download=True)
                        title = info.get('title', 'media')

                    # Find generated file
                    ext = '.mp4' if media_type == 'video' else '.mp3'
                    mime = 'video/mp4' if media_type == 'video' else 'audio/mpeg'
                    matched_files = [f for f in os.listdir(tmpdir) if f.endswith(ext)]
                    if not matched_files:
                        self.send_response(500)
                        self.send_header('Content-Type', 'application/json; charset=utf-8')
                        self.send_header('Access-Control-Allow-Origin', '*')
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": f"{ext.upper()} file generation failed"}).encode('utf-8'))
                        return

                    file_path = os.path.join(tmpdir, matched_files[0])
                    file_size = os.path.getsize(file_path)

                    self.send_response(200)
                    self.send_header('Content-Type', mime)
                    self.send_header('Content-Length', str(file_size))
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.send_header('Access-Control-Expose-Headers', 'X-Track-Title, X-Media-Type')
                    self.send_header('X-Track-Title', title.encode('ascii', 'ignore').decode('ascii'))
                    self.send_header('X-Media-Type', media_type)
                    self.end_headers()

                    with open(file_path, 'rb') as f:
                        shutil.copyfileobj(f, self.wfile)

                    print(f"[Backend] Successfully served {media_type}: {title} ({file_size} bytes)")

            except Exception as e:
                err_msg = str(e)
                print(f"[Backend] Error: {err_msg}")
                self.send_response(500)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"error": err_msg}).encode('utf-8'))
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Endpoint not found"}).encode('utf-8'))

def run():
    server = HTTPServer(('0.0.0.0', PORT), DownloadHandler)
    print(f"🎵 YT Audio Cloud Backend running on http://0.0.0.0:{PORT}")
    server.serve_forever()

if __name__ == '__main__':
    run()
