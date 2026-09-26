#!/usr/bin/env python3
"""
YouTube MP3 Downloader GUI
A clean and intuitive desktop application to download audio from YouTube videos in MP3 format.
"""

import os
import sys
import re
import ssl
import shutil
import threading
import subprocess
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

# Handle macOS SSL certificates automatically
try:
    import certifi
    os.environ['SSL_CERT_FILE'] = certifi.where()
    os.environ['REQUESTS_CA_BUNDLE'] = certifi.where()
    _ssl_context = ssl.create_default_context(cafile=certifi.where())
    ssl._create_default_https_context = lambda: _ssl_context
except Exception:
    pass

import yt_dlp

class YoutubeMp3DownloaderApp:
    def __init__(self, root):
        self.root = root
        self.root.title("YouTube MP3 Downloader")
        self.root.geometry("620x460")
        self.root.minsize(580, 420)

        # Enhance styling for macOS
        self.style = ttk.Style()
        try:
            self.style.theme_use('aqua')
        except Exception:
            pass

        # Variables
        self.url_var = tk.StringVar()
        self.save_dir_var = tk.StringVar(value=str(Path.home() / "Downloads"))
        self.quality_var = tk.StringVar(value="320")
        self.status_var = tk.StringVar(value="Paste a YouTube link above to get started.")
        self.last_download_path = self.save_dir_var.get()
        self.is_downloading = False

        self._find_ffmpeg()
        self._build_ui()

    def _find_ffmpeg(self):
        """Find the ffmpeg executable on the system."""
        self.ffmpeg_path = shutil.which("ffmpeg")
        if not self.ffmpeg_path:
            # Common macOS paths (Homebrew / MacPorts)
            for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]:
                if os.path.exists(path):
                    self.ffmpeg_path = path
                    break

    def _build_ui(self):
        main_frame = ttk.Frame(self.root, padding="20 20 20 20")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Header and description
        title_label = ttk.Label(main_frame, text="🎵 YouTube MP3 Downloader", font=("Helvetica", 18, "bold"))
        title_label.pack(anchor="w", pady=(0, 4))
        subtitle_label = ttk.Label(main_frame, text="Download music, podcasts, or talks directly into high-quality MP3 files.", foreground="gray")
        subtitle_label.pack(anchor="w", pady=(0, 16))

        # 1. URL Section
        url_frame = ttk.LabelFrame(main_frame, text=" 1. YouTube Video URL ", padding="10 10 10 10")
        url_frame.pack(fill=tk.X, pady=(0, 12))

        url_input_box = ttk.Frame(url_frame)
        url_input_box.pack(fill=tk.X)

        self.url_entry = ttk.Entry(url_input_box, textvariable=self.url_var, font=("Helvetica", 12))
        self.url_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        self.url_entry.focus()

        paste_btn = ttk.Button(url_input_box, text="📋 Paste", command=self._paste_clipboard)
        paste_btn.pack(side=tk.RIGHT)

        # 2. Settings Section (Output directory + Audio quality)
        settings_frame = ttk.LabelFrame(main_frame, text=" 2. Settings ", padding="10 10 10 10")
        settings_frame.pack(fill=tk.X, pady=(0, 12))

        # Output folder
        dir_label = ttk.Label(settings_frame, text="Save directory:")
        dir_label.grid(row=0, column=0, sticky="w", pady=4)

        dir_box = ttk.Frame(settings_frame)
        dir_box.grid(row=0, column=1, sticky="ew", padx=(8, 0), pady=4)
        settings_frame.columnconfigure(1, weight=1)

        self.dir_entry = ttk.Entry(dir_box, textvariable=self.save_dir_var, state="readonly")
        self.dir_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))

        browse_btn = ttk.Button(dir_box, text="Browse...", command=self._browse_directory)
        browse_btn.pack(side=tk.RIGHT)

        # Quality
        quality_label = ttk.Label(settings_frame, text="Audio quality:")
        quality_label.grid(row=1, column=0, sticky="w", pady=4)

        quality_combobox = ttk.Combobox(
            settings_frame,
            textvariable=self.quality_var,
            values=["320", "256", "192", "128"],
            state="readonly",
            width=15
        )
        quality_combobox.grid(row=1, column=1, sticky="w", padx=(8, 0), pady=4)
        quality_hint = ttk.Label(settings_frame, text="kbps (320 kbps = best quality)", foreground="gray")
        quality_hint.grid(row=1, column=1, sticky="w", padx=(140, 0), pady=4)

        # 3. Progress and Status Section
        status_frame = ttk.Frame(main_frame)
        status_frame.pack(fill=tk.X, pady=(4, 12))

        self.status_label = ttk.Label(status_frame, textvariable=self.status_var, wraplength=560, font=("Helvetica", 11))
        self.status_label.pack(anchor="w", pady=(0, 6))

        self.progress_bar = ttk.Progressbar(status_frame, orient="horizontal", mode="determinate")
        self.progress_bar.pack(fill=tk.X)

        # 4. Action Buttons (Download + Open folder)
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=(8, 0))

        self.download_btn = ttk.Button(
            btn_frame,
            text="⬇️ Download Audio (MP3)",
            command=self._start_download_thread
        )
        self.download_btn.pack(side=tk.LEFT, ipady=4, expand=True, fill=tk.X, padx=(0, 8))

        self.open_folder_btn = ttk.Button(
            btn_frame,
            text="📂 Open Download Folder",
            command=self._open_target_folder,
            state="normal"
        )
        self.open_folder_btn.pack(side=tk.RIGHT, ipady=4)

        # Check FFmpeg availability
        if not self.ffmpeg_path:
            self.status_var.set("⚠️ Warning: FFmpeg was not detected! It is required for MP3 conversion.")

    def _paste_clipboard(self):
        """Paste clipboard content into the URL input."""
        try:
            clipboard_text = self.root.clipboard_get()
            if clipboard_text:
                self.url_var.set(clipboard_text.strip())
        except Exception:
            pass

    def _browse_directory(self):
        """Open a directory picker dialog."""
        selected_dir = filedialog.askdirectory(initialdir=self.save_dir_var.get())
        if selected_dir:
            self.save_dir_var.set(selected_dir)
            self.last_download_path = selected_dir

    def _open_target_folder(self):
        """Open the target directory in macOS Finder or default OS file manager."""
        path = self.last_download_path
        if not os.path.exists(path):
            path = self.save_dir_var.get()
        if os.path.exists(path):
            if sys.platform == "darwin":
                subprocess.run(["open", path])
            elif sys.platform == "win32":
                os.startfile(path)
            else:
                subprocess.run(["xdg-open", path])
        else:
            messagebox.showinfo("Information", "The specified folder does not exist yet.")

    def _start_download_thread(self):
        """Start the download process in a background thread to keep the UI responsive."""
        url = self.url_var.get().strip()
        if not url:
            messagebox.showwarning("Missing URL", "Please enter or paste a valid YouTube URL!")
            return

        if not (url.startswith("http://") or url.startswith("https://")):
            messagebox.showwarning("Invalid URL", "The entered text is not a valid web URL!")
            return

        if self.is_downloading:
            return

        self.is_downloading = True
        self.download_btn.config(state="disabled")
        self.progress_bar["value"] = 0
        self.progress_bar.config(mode="indeterminate")
        self.progress_bar.start(10)
        self.status_var.set("Fetching video metadata...")

        thread = threading.Thread(target=self._run_download, args=(url,), daemon=True)
        thread.start()

    def _progress_hook(self, d):
        """yt-dlp progress hook to update UI progress bar and status."""
        status = d.get('status')
        if status == 'downloading':
            self.root.after(0, self._handle_downloading_progress, d)
        elif status == 'finished':
            self.root.after(0, self._handle_post_processing)

    def _handle_downloading_progress(self, d):
        if self.progress_bar["mode"] != "determinate":
            self.progress_bar.stop()
            self.progress_bar.config(mode="determinate")

        total_bytes = d.get('total_bytes') or d.get('total_bytes_estimate') or 0
        downloaded = d.get('downloaded_bytes', 0)
        
        if total_bytes > 0:
            percentage = (downloaded / total_bytes) * 100
            self.progress_bar["value"] = percentage
            speed_str = d.get('_speed_str', '')
            eta_str = d.get('_eta_str', '')
            self.status_var.set(f"Downloading: {percentage:.1f}% ({speed_str} - ETA: {eta_str})")
        else:
            self.status_var.set("Downloading audio stream...")

    def _handle_post_processing(self):
        self.progress_bar.config(mode="indeterminate")
        self.progress_bar.start(10)
        self.status_var.set("Converting to MP3 and embedding metadata (FFmpeg)...")

    def _run_download(self, url):
        """Execute download and audio extraction in background."""
        save_dir = self.save_dir_var.get()
        quality = self.quality_var.get()

        ydl_opts = {
            'format': 'bestaudio/best',
            'outtmpl': os.path.join(save_dir, '%(title)s.%(ext)s'),
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
            'progress_hooks': [self._progress_hook],
            'noplaylist': True,
            'quiet': True,
            'no_warnings': True,
        }

        # Enable Node.js runtime if available
        node_path = shutil.which("node") or "/opt/homebrew/bin/node"
        if os.path.exists(node_path):
            ydl_opts['js_runtimes'] = {'node': {'path': node_path}}

        if self.ffmpeg_path:
            ydl_opts['ffmpeg_location'] = os.path.dirname(self.ffmpeg_path)

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                title = info.get('title', 'Audio')
            
            self.root.after(0, self._on_download_success, title)
        except Exception as e:
            error_message = str(e)
            self.root.after(0, self._on_download_error, error_message)

    def _on_download_success(self, title):
        self.is_downloading = False
        self.progress_bar.stop()
        self.progress_bar.config(mode="determinate")
        self.progress_bar["value"] = 100
        self.download_btn.config(state="normal")
        self.status_var.set(f"✅ Download complete: {title}")
        messagebox.showinfo("Success!", f"The audio was successfully downloaded as an MP3 file!\n\nTitle: {title}")

    def _on_download_error(self, error_message):
        self.is_downloading = False
        self.progress_bar.stop()
        self.progress_bar.config(mode="determinate")
        self.progress_bar["value"] = 0
        self.download_btn.config(state="normal")

        # Strip ANSI escape codes
        clean_msg = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', error_message)
        clean_first_line = clean_msg.split('\n')[0]

        self.status_var.set(f"❌ Error: {clean_first_line}")
        messagebox.showerror("Download Error", f"Failed to download audio:\n\n{clean_msg}")


def main():
    root = tk.Tk()
    app = YoutubeMp3DownloaderApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
