#!/bin/bash

# RDI Server Startup Script
set -e

echo "Starting RDI Server..."
echo "RDI Redis Host: ${RDI_REDIS_HOST:-localhost}"
echo "RDI Redis Port: ${RDI_REDIS_PORT:-6379}"
echo "RDI Redis Username: ${RDI_REDIS_USERNAME:-default}"

# Wait for Redis to be available using Python
echo "Waiting for Redis connection..."
python3 -c "
import socket
import time
import sys

def test_redis_connection():
    host = '${RDI_REDIS_HOST:-localhost}'
    port = int('${RDI_REDIS_PORT:-6379}')
    max_attempts = 30

    for attempt in range(max_attempts):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            result = sock.connect_ex((host, port))
            sock.close()

            if result == 0:
                print(f'Redis connection successful to {host}:{port}')
                return True
            else:
                print(f'Redis connection attempt {attempt + 1}/{max_attempts} failed - sleeping')
                time.sleep(2)
        except Exception as e:
            print(f'Redis connection attempt {attempt + 1}/{max_attempts} failed: {e} - sleeping')
            time.sleep(2)

    print(f'Failed to connect to Redis after {max_attempts} attempts')
    return False

if not test_redis_connection():
    sys.exit(1)
"

echo "Redis is available!"

# Create RDI configuration file
cat > /opt/rdi/config/rdi.conf << EOF
# RDI Configuration
redis.host=${RDI_REDIS_HOST:-localhost}
redis.port=${RDI_REDIS_PORT:-6379}
redis.username=${RDI_REDIS_USERNAME:-default}
redis.password=${RDI_REDIS_PASSWORD}
redis.ssl=false

# RDI Server settings
server.port=8080
server.ssl.port=9443
server.ssl.enabled=false

# Logging
logging.level=INFO
logging.file=/opt/rdi/logs/rdi.log

# Pipeline configuration directory
pipeline.config.dir=/opt/rdi/pipeline-config
EOF

# Initialize RDI if not already initialized
if [ ! -f "/opt/rdi/.initialized" ]; then
    echo "Initializing RDI..."
    
    # Create initial pipeline configuration
    mkdir -p /opt/rdi/pipeline-config/jobs
    
    # Copy default configurations if they don't exist
    if [ ! -f "/opt/rdi/pipeline-config/config.yaml" ]; then
        cat > /opt/rdi/pipeline-config/config.yaml << EOF
connections:
  target:
    type: redis
    host: ${RDI_REDIS_HOST:-localhost}
    port: ${RDI_REDIS_PORT:-6379}
    username: ${RDI_REDIS_USERNAME:-default}
    password: ${RDI_REDIS_PASSWORD}
    ssl: false
EOF
    fi
    
    touch /opt/rdi/.initialized
    echo "RDI initialization complete"
fi

# Create a simple HTTP server for health checks and basic API
echo "Starting RDI management server..."

# Create a simple Python HTTP server for RDI management
cat > /opt/rdi/rdi-http-server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import os
from urllib.parse import urlparse, parse_qs

class RDIHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)

        if parsed_path.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            health_status = {
                "status": "healthy",
                "redis_host": os.environ.get('RDI_REDIS_HOST', 'unknown'),
                "redis_port": os.environ.get('RDI_REDIS_PORT', 'unknown'),
                "timestamp": str(__import__('datetime').datetime.now())
            }
            self.wfile.write(json.dumps(health_status).encode())

        elif parsed_path.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            status = {
                "rdi_version": "0.118.0",
                "config_dir": "/opt/rdi/pipeline-config",
                "redis_connection": {
                    "host": os.environ.get('RDI_REDIS_HOST'),
                    "port": os.environ.get('RDI_REDIS_PORT'),
                    "username": os.environ.get('RDI_REDIS_USERNAME')
                }
            }
            self.wfile.write(json.dumps(status).encode())

        elif parsed_path.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            metrics = """# HELP rdi_status RDI Status
# TYPE rdi_status gauge
rdi_status 1
# HELP rdi_redis_connected Redis Connection Status
# TYPE rdi_redis_connected gauge
rdi_redis_connected 1
"""
            self.wfile.write(metrics.encode())

        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

    def log_message(self, format, *args):
        pass  # Suppress default logging

PORT = 8080
with socketserver.TCPServer(("", PORT), RDIHandler) as httpd:
    print(f"RDI HTTP server running on port {PORT}")
    httpd.serve_forever()
EOF

# Start the HTTP server
exec python3 /opt/rdi/rdi-http-server.py
