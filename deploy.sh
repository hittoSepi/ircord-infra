#!/bin/bash

# IRCord Infrastructure Deployment Script
# Usage: ./deploy.sh [dev|prod]

set -e

ENV=${1:-dev}
COMPOSE_FILE="docker-compose.yml"

echo "======================================"
echo "IRCord Infrastructure Deployment"
echo "Environment: $ENV"
echo "======================================"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Error: Docker Compose is not installed"
    exit 1
fi

# Create necessary directories
mkdir -p nginx/ssl
mkdir -p data

echo ""
echo "Pulling latest changes..."
git pull || echo "Not a git repository, skipping pull"

echo ""
echo "Building and starting services..."

if [ "$ENV" = "prod" ] || [ "$ENV" = "production" ]; then
    # Production deployment
    echo "Production mode with nginx reverse proxy"
    
    # Check if SSL certificates exist
    if [ ! -f "nginx/ssl/directory.ircord.dev.crt" ] || [ ! -f "nginx/ssl/web.ircord.dev.crt" ]; then
        echo ""
        echo "WARNING: SSL certificates not found in nginx/ssl/"
        echo "Place your certificates there or use Let's Encrypt:"
        echo "  nginx/ssl/directory.ircord.dev.crt"
        echo "  nginx/ssl/directory.ircord.dev.key"
        echo "  nginx/ssl/web.ircord.dev.crt"
        echo "  nginx/ssl/web.ircord.dev.key"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    docker-compose --profile production down
    docker-compose --profile production pull
    docker-compose --profile production up -d --build
    
    echo ""
    echo "Production services started:"
    echo "  Directory API: https://directory.ircord.dev"
    echo "  Web Client:    https://web.ircord.dev"
else
    # Development deployment
    echo "Development mode"
    
    docker-compose down
    docker-compose pull
    docker-compose up -d --build
    
    echo ""
    echo "Development services started:"
    echo "  Directory API: http://localhost:3000"
    echo "  Web Client:    http://localhost:8080"
fi

echo ""
echo "Checking service health..."
sleep 2

# Health checks
if curl -s http://localhost:3000/api/health > /dev/null 2>&1 || \
   curl -s https://directory.ircord.dev/api/health > /dev/null 2>&1; then
    echo "✓ Directory service is healthy"
else
    echo "✗ Directory service health check failed"
fi

echo ""
echo "View logs: docker-compose logs -f"
echo "Stop:      docker-compose down"
echo "======================================"
