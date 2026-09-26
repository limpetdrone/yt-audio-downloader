#!/usr/bin/env python3
"""
Lightweight Downloader Backend Server
Processes YouTube audio extraction and video downloads with live progress tracking.
"""

import os
import sys
import json
import shutil
import tempfile
import uuid
import threading
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
import certifi
import yt_dlp

os.environ['SSL_CERT_FILE'] = certifi.where()
os.environ['REQUESTS_CA_BUNDLE'] = certifi.where()

PORT = int(os.environ.get('PORT', 8000))

# Active download jobs
jobs = {}
job_dirs = {}

def run_download_job(job_id, video_url, quality, media_type):
    tmpdir = tempfile.mkdtemp()
    job_dirs[job_id] = tmpdir
    out_template = os.path.join(tmpdir, '%(title)s.%(ext)s')

    def hook(d):
        if d['status'] == 'downloading':
            total = d.get('total_bytes') or d.get('total_bytes_estimate') or 0
            dl = d.get('downloaded_bytes', 0)
            pct = (dl / total) if total else 0
            speed = (d.get('speed') or 0) / (1024 * 1024)
            eta = d.get('eta') or 0
            jobs[job_id].update({
                'status': 'downloading',
                'progress': min(0.90, max(0.05, pct * 0.88)),
                'speed': round(speed, 1),
                'eta': int(eta),
                'message': f"Downloading: {pct*100:.1f}% ({speed:.1f} MB/s • {int(eta)}s remaining)"
            })
        elif d['status'] == 'finished':
            jobs[job_id].update({
                'status': 'converting',
                'progress': 0.92,
                'message': "Finalizing & converting with FFmpeg..."
            })

    if media_type == 'video':
        ydl_opts = {
            'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
            'outtmpl': out_template,
            'nocheckcertificate': True,
            'progress_hooks': [hook],
            'quiet': True,
            'no_warnings': True,
        }
    else:
        ydl_opts = {
            'format': 'bestaudio/best',
            'outtmpl': out_template,
            'nocheckcertificate': True,
            'progress_hooks': [hook],
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

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=True)
            title = info.get('title', 'media')

        ext = '.mp4' if media_type == 'video' else '.mp3'
        mime = 'video/mp4' if media_type == 'video' else 'audio/mpeg'
        matched_files = [f for f in os.listdir(tmpdir) if f.endswith(ext)]
        if not matched_files:
            jobs[job_id].update({'status': 'error', 'error': f"{ext.upper()} file generation failed"})
            return

        file_path = os.path.join(tmpdir, matched_files[0])
        file_size = os.path.getsize(file_path)

        jobs[job_id].update({
            'status': 'ready',
            'progress': 1.0,
            'message': f"Ready: {title}",
            'title': title,
            'file_path': file_path,
            'file_size': file_size,
            'mime': mime,
            'media_type': media_type,
            'filename': os.path.basename(file_path),
        })
        print(f"[Backend] Job {job_id} ready: {title} ({file_size} bytes)")
    except Exception as e:
        err_msg = str(e)
        print(f"[Backend] Job {job_id} error: {err_msg}")
        jobs[job_id].update({'status': 'error', 'error': err_msg, 'message': f"Error: {err_msg}"})


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
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if path == '/health' or path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "service": "YT Audio Cloud Backend"}).encode())

        elif path == '/download/progress':
            job_id = query.get('id', [''])[0]
            job = jobs.get(job_id)
            if not job:
                self.send_response(404)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "not_found", "error": "Job not found"}).encode())
                return

            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            safe_job = {
                'status': job.get('status'),
                'progress': job.get('progress', 0.0),
                'speed': job.get('speed', 0.0),
                'eta': job.get('eta', 0),
                'message': job.get('message', ''),
                'title': job.get('title', ''),
                'error': job.get('error'),
                'media_type': job.get('media_type', 'audio')
            }
            self.wfile.write(json.dumps(safe_job).encode('utf-8'))

        elif path == '/download/file':
            job_id = query.get('id', [''])[0]
            job = jobs.get(job_id)
            if not job or job.get('status') != 'ready':
                self.send_response(404)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"error": "File not ready or job not found"}).encode())
                return

            file_path = job['file_path']
            file_size = job['file_size']
            title = job['title']
            mime = job['mime']
            media_type = job['media_type']

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

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/download/start':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode('utf-8'))
                video_url = data.get('url', '').strip()
                quality = data.get('quality', '320')
                media_type = data.get('type', 'audio')

                if not video_url:
                    self.send_response(400)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "Missing URL"}).encode('utf-8'))
                    return

                job_id = str(uuid.uuid4())
                jobs[job_id] = {
                    'status': 'starting',
                    'progress': 0.05,
                    'speed': 0.0,
                    'eta': 0,
                    'message': "Starting download...",
                    'media_type': media_type
                }

                print(f"[Backend] Started background job {job_id} for {video_url} ({media_type})")
                thread = threading.Thread(target=run_download_job, args=(job_id, video_url, quality, media_type), daemon=True)
                thread.start()

                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"job_id": job_id}).encode('utf-8'))

            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))

        elif self.path == '/download':
            # Synchronous download fallback
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode('utf-8'))
                video_url = data.get('url', '').strip()
                quality = data.get('quality', '320')
                media_type = data.get('type', 'audio')

                job_id = str(uuid.uuid4())
                jobs[job_id] = {'status': 'starting', 'progress': 0.0, 'message': 'Downloading...'}
                run_download_job(job_id, video_url, quality, media_type)

                job = jobs.get(job_id)
                if not job or job.get('status') != 'ready':
                    self.send_response(500)
                    self.send_header('Content-Type', 'application/json; charset=utf-8')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": job.get('error', 'Download failed')}).encode('utf-8'))
                    return

                file_path = job['file_path']
                file_size = job['file_size']
                title = job['title']
                mime = job['mime']

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

            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def run():
    server = HTTPServer(('0.0.0.0', PORT), DownloadHandler)
    print(f"🎵 YT Audio Cloud Backend running on http://0.0.0.0:{PORT}")
    server.serve_forever()

if __name__ == '__main__':
    run()
