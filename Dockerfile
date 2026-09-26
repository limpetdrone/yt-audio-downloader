FROM python:3.11-slim

# Install ffmpeg, nodejs, and certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    nodejs \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend server code
COPY server.py .

ENV PORT=10000
EXPOSE 10000

CMD ["python", "server.py"]
