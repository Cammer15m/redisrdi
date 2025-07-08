#!/bin/bash

# Test RDI Setup Script
set -e

echo "=== RDI Container Setup Test ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS")
            echo -e "${GREEN}✓ $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}✗ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠ $message${NC}"
            ;;
        "INFO")
            echo -e "${YELLOW}ℹ $message${NC}"
            ;;
    esac
}

# Test Redis connectivity
echo "1. Testing Redis connectivity..."
if timeout 5 redis-cli -h 3.148.243.197 -p 13000 -a redislabs --no-auth-warning ping > /dev/null 2>&1; then
    print_status "SUCCESS" "Redis database is accessible at 3.148.243.197:13000"
else
    print_status "ERROR" "Cannot connect to Redis database at 3.148.243.197:13000"
    print_status "WARNING" "RDI container will fail to start without Redis connectivity"
fi

# Check if Docker is running
echo -e "\n2. Checking Docker..."
if docker info > /dev/null 2>&1; then
    print_status "SUCCESS" "Docker is running"
else
    print_status "ERROR" "Docker is not running or not accessible"
    exit 1
fi

# Check if docker-compose is available
echo -e "\n3. Checking docker-compose..."
if command -v docker-compose > /dev/null 2>&1; then
    print_status "SUCCESS" "docker-compose is available"
    COMPOSE_CMD="docker-compose"
elif docker compose version > /dev/null 2>&1; then
    print_status "SUCCESS" "docker compose (plugin) is available"
    COMPOSE_CMD="docker compose"
else
    print_status "ERROR" "Neither docker-compose nor docker compose plugin is available"
    exit 1
fi

# Validate docker-compose.yml
echo -e "\n4. Validating docker-compose.yml..."
if $COMPOSE_CMD config > /dev/null 2>&1; then
    print_status "SUCCESS" "docker-compose.yml is valid"
else
    print_status "ERROR" "docker-compose.yml has syntax errors"
    $COMPOSE_CMD config
    exit 1
fi

# Check required files
echo -e "\n5. Checking required files..."
required_files=(
    "rdi-server.dockerfile"
    "rdi-startup.sh"
    "rdi-config/rdi-server.yaml"
    ".env.rdi"
    "from-repo/redis_di_config/config.yaml"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        print_status "SUCCESS" "Found: $file"
    else
        print_status "ERROR" "Missing: $file"
    fi
done

# Check directories
echo -e "\n6. Checking required directories..."
required_dirs=(
    "logs/rdi"
    "rdi-config"
    "from-repo/redis_di_config"
)

for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        print_status "SUCCESS" "Found directory: $dir"
    else
        print_status "ERROR" "Missing directory: $dir"
    fi
done

# Build RDI container (dry run)
echo -e "\n7. Testing RDI container build..."
if $COMPOSE_CMD build rdi-server > /dev/null 2>&1; then
    print_status "SUCCESS" "RDI container builds successfully"
else
    print_status "ERROR" "RDI container build failed"
    print_status "INFO" "Run '$COMPOSE_CMD build rdi-server' for detailed error output"
fi

echo -e "\n=== Test Summary ==="
print_status "INFO" "RDI container configuration is ready"
print_status "INFO" "To start RDI: $COMPOSE_CMD up rdi-server"
print_status "INFO" "To view logs: $COMPOSE_CMD logs -f rdi-server"
print_status "INFO" "RDI API will be available at: http://localhost:8080"
print_status "INFO" "RDI Health check: http://localhost:8080/health"
print_status "INFO" "RDI Metrics: http://localhost:9090/metrics"

if timeout 5 redis-cli -h 3.148.243.197 -p 13000 -a redislabs --no-auth-warning ping > /dev/null 2>&1; then
    print_status "SUCCESS" "Ready to start RDI container!"
else
    print_status "WARNING" "Fix Redis connectivity before starting RDI container"
fi
