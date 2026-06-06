#!/bin/bash

# deploy-ci.sh - Build and deploy Docker containers for Obsidian with OAuth2 proxy
# This script builds and deploys the Docker containers defined in docker-compose.yml

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if required environment variables are set
check_env_vars() {
    log_info "Checking environment variables..."
    
    # Required variables from .env
    local required_vars=(
        "PUID"
        "PGID" 
        "TZ"
        "CONFIG_PATH"
        "SHM_SIZE"
        "OBSIDIAN_IMAGE"
        "OBSIDIAN_CONTAINER_NAME"
        "HTTP_PORT"
        "HTTPS_PORT"
        "OAUTH2_PROVIDER"
        "OAUTH2_CLIENT_ID"
        "OAUTH2_CLIENT_SECRET"
        "OAUTH2_OIDC_ISSUER_URL"
        "OAUTH2_REDIRECT_URL"
        "OAUTH2_COOKIE_SECRET"
        "OAUTH2_EMAIL_DOMAIN"
    )
    
    local missing_vars=()
    
    # Check if .env file exists
    if [[ ! -f ".env" ]]; then
        log_error ".env file not found. Please create it from .env.example"
        return 1
    fi
    
    # Source the .env file
    source .env
    
    # Check each required variable
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        return 1
    fi
    
    log_success "All required environment variables are set"
}

# Function to check if Docker and Docker Compose are installed
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed or not in PATH"
        return 1
    fi
    
    log_success "Docker and Docker Compose are available"
}

# Function to build Docker images
build_images() {
    log_info "Building Docker images..."
    
    # Pull latest images
    log_info "Pulling latest images..."
    docker-compose pull
    
    # Build any custom images (if needed)
    if docker-compose config | grep -q "build:"; then
        log_info "Building custom images..."
        docker-compose build
    fi
    
    log_success "Docker images built successfully"
}

# Function to stop existing containers
stop_containers() {
    log_info "Stopping existing containers..."
    
    if docker-compose ps -q | grep -q .; then
        docker-compose down
        log_success "Existing containers stopped"
    else
        log_info "No running containers found"
    fi
}

# Function to start containers
start_containers() {
    log_info "Starting containers..."
    
    # Start containers in detached mode
    docker-compose up -d
    
    log_success "Containers started successfully"
}

# Function to wait for health checks
wait_for_health() {
    log_info "Waiting for services to be healthy..."
    
    local max_wait=300
    local wait_interval=10
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy=true
        
        # Check obsidian container health
        if ! docker-compose ps obsidian | grep -q "healthy"; then
            healthy=false
        fi
        
        # Check oauth2-proxy container (it doesn't have healthcheck, just check if running)
        if ! docker-compose ps oauth2-proxy | grep -q "Up"; then
            healthy=false
        fi
        
        if [[ "$healthy" == true ]]; then
            log_success "All services are healthy"
            return 0
        fi
        
        log_info "Waiting for services... (${elapsed}/${max_wait}s)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log_error "Timeout waiting for services to become healthy"
    return 1
}

# Function to show deployment status
show_status() {
    log_info "Deployment status:"
    echo
    docker-compose ps
    echo
    log_info "Service URLs:"
    echo "  - Obsidian (via OAuth2): http://localhost:${HTTP_PORT}"
    echo "  - Direct Obsidian (if enabled): http://localhost:${HTTPS_PORT}"
}

# Function to cleanup on exit
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed. Check logs with: docker-compose logs"
    fi
}

# Main deployment function
deploy() {
    log_info "Starting deployment..."
    
    # Run checks
    check_dependencies || exit 1
    check_env_vars || exit 1
    
    # Build and deploy
    build_images || exit 1
    stop_containers
    start_containers || exit 1
    wait_for_health || exit 1
    
    # Show final status
    show_status
    log_success "Deployment completed successfully!"
}

# Parse command line arguments
case "${1:-deploy}" in
    "deploy")
        deploy
        ;;
    "build")
        check_dependencies || exit 1
        check_env_vars || exit 1
        build_images
        ;;
    "stop")
        stop_containers
        ;;
    "start")
        start_containers
        ;;
    "restart")
        stop_containers
        start_containers
        ;;
    "status")
        show_status
        ;;
    "logs")
        docker-compose logs -f
        ;;
    "health")
        wait_for_health
        ;;
    *)
        echo "Usage: $0 {deploy|build|stop|start|restart|status|logs|health}"
        echo
        echo "Commands:"
        echo "  deploy  - Full deployment (default)"
        echo "  build   - Build Docker images only"
        echo "  stop    - Stop all containers"
        echo "  start   - Start all containers"
        echo "  restart - Restart all containers"
        echo "  status  - Show container status"
        echo "  logs    - Show container logs"
        echo "  health  - Wait for services to be healthy"
        exit 1
        ;;
esac
