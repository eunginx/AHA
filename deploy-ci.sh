#!/bin/bash

# deploy-ci.sh - TeamCity-ready deployment for Obsidian + OAuth2 proxy
# Usage: ./deploy-ci.sh [deploy|build|stop|start|restart|status|logs|health|validate]

set -euo pipefail

# ---------------------------------------------------------------------------
# Detect compose command (v2 vs legacy)
# ---------------------------------------------------------------------------
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

# ---------------------------------------------------------------------------
# Colors & TeamCity service messages
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TC_IS_TEAMCITY=${TEAMCITY_VERSION:-}

log_raw()  { echo -e "$1"; }
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1";  tc_progress "$1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1";  tc_status NORMAL "$1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; tc_status WARNING "$1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1";   tc_status FAILURE "$1"; }
log_debug()   { [[ "${DEBUG:-}" == "true" ]] && echo -e "${CYAN}[DBG]${NC}  $1" || true; }

# TeamCity helpers
tc_progress() { [[ -n "$TC_IS_TEAMCITY" ]] && echo "##teamcity[progressMessage '$1']"; true; }
tc_status()   { [[ -n "$TC_IS_TEAMCITY" ]] && echo "##teamcity[buildStatus text='{build.status.text} | $2']"; true; }
tc_block_open()  { [[ -n "$TC_IS_TEAMCITY" ]] && echo "##teamcity[blockOpened name='$1']"; true; }
tc_block_close() { [[ -n "$TC_IS_TEAMCITY" ]] && echo "##teamcity[blockClosed name='$1']"; true; }

# ---------------------------------------------------------------------------
# Fail-safe: capture logs + artifact on error
# ---------------------------------------------------------------------------
DEPLOY_LOG_DIR="${DEPLOY_LOG_DIR:-./deploy-logs}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FAILURE_ARTIFACT="$DEPLOY_LOG_DIR/failure_$TIMESTAMP.log"

cleanup_on_error() {
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        mkdir -p "$DEPLOY_LOG_DIR"
        {
            echo "===== DEPLOYMENT FAILED | exit=$rc | $(date -Iseconds) ====="
            echo ""
            echo "--- docker-compose.yml validation ---"
            $COMPOSE_CMD config 2>&1 || true
            echo ""
            echo "--- container status ---"
            $COMPOSE_CMD ps 2>&1 || true
            echo ""
            echo "--- obsidian logs (last 100 lines) ---"
            $COMPOSE_CMD logs --tail=100 obsidian 2>&1 || true
            echo ""
            echo "--- oauth2-proxy logs (last 100 lines) ---"
            $COMPOSE_CMD logs --tail=100 oauth2-proxy 2>&1 || true
            echo ""
            echo "--- full env (sanitised) ---"
            env | grep -v -E 'SECRET|TOKEN|PASSWORD|KEY' | sort || true
        } > "$FAILURE_ARTIFACT"
        log_error "Deployment failed (exit=$rc). Full diagnostics written to: $FAILURE_ARTIFACT"
        tc_status FAILURE "Deployment failed - see $FAILURE_ARTIFACT"
    fi
}
trap cleanup_on_error EXIT

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
check_dependencies() {
    tc_block_open "dependencies"
    log_info "Checking Docker / Compose ..."

    # Skip dependency checks if containers are already running
    if $COMPOSE_CMD ps -q 2>/dev/null | grep -q .; then
        log_info "Containers already running, skipping dependency checks"
        tc_block_close "dependencies"
        return 0
    fi

    if ! command -v docker &>/dev/null; then
        log_error "Docker not found in PATH"
        return 1
    fi

    if ! $COMPOSE_CMD version &>/dev/null 2>&1; then
        log_error "'$COMPOSE_CMD' not available"
        return 1
    fi

    # Ensure daemon is reachable
    if ! docker info &>/dev/null; then
        log_error "Docker daemon unreachable"
        return 1
    fi

    log_success "Docker OK ($COMPOSE_CMD)"
    tc_block_close "dependencies"
}

validate_compose() {
    tc_block_open "validate_compose"
    log_info "Validating docker-compose.yml ..."

    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $(pwd)"
        return 1
    fi

    # Expand env and check syntax
    if ! $COMPOSE_CMD config >/dev/null 2>&1; then
        log_error "docker-compose.yml validation failed"
        $COMPOSE_CMD config 2>&1 || true
        return 1
    fi

    # Warn if referenced images are missing locally (CI usually needs explicit pulls)
    local images
    images=$($COMPOSE_CMD config | grep -E "^\s+image:" | awk '{print $2}' | sort -u)
    for img in $images; do
        if ! docker image inspect "$img" &>/dev/null; then
            log_warn "Image '$img' not present locally; will be pulled"
        fi
    done

    log_success "docker-compose.yml is valid"
    tc_block_close "validate_compose"
}

check_env_vars() {
    tc_block_open "env_check"
    log_info "Checking environment variables ..."

    if [[ ! -f ".env" ]]; then
        log_error ".env file missing. Copy from .env.example: cp .env.example .env"
        return 1
    fi

    # Source without exporting to validate values
    set -a
    source .env
    set +a

    local required=(
        PUID PGID TZ CONFIG_PATH SHM_SIZE
        OBSIDIAN_IMAGE OBSIDIAN_CONTAINER_NAME HTTP_PORT
        OAUTH2_PROVIDER OAUTH2_CLIENT_ID OAUTH2_CLIENT_SECRET
        OAUTH2_OIDC_ISSUER_URL OAUTH2_REDIRECT_URL
        OAUTH2_COOKIE_SECRET OAUTH2_EMAIL_DOMAIN
    )
    local missing=()
    for var in "${required[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        printf '  - %s\n' "${missing[@]}"
        return 1
    fi

    log_success "All required environment variables set"
    tc_block_close "env_check"
}

# ---------------------------------------------------------------------------
# Build / Pull phase
# ---------------------------------------------------------------------------
build_images() {
    tc_block_open "build"
    log_info "Pulling images ..."
    $COMPOSE_CMD pull --quiet 2>&1 | while read -r line; do log_debug "$line"; done

    # Only build if there is a build: section
    if $COMPOSE_CMD config 2>/dev/null | grep -q "build:"; then
        log_info "Building custom images ..."
        $COMPOSE_CMD build --parallel 2>&1 | while read -r line; do log_debug "$line"; done
    fi

    log_success "Images ready"
    tc_block_close "build"
}

# ---------------------------------------------------------------------------
# Lifecycle operations (only what docker-compose.yml defines)
# ---------------------------------------------------------------------------
stop_containers() {
    tc_block_open "stop"
    log_info "Stopping obsidian and oauth2-proxy containers and removing related volumes/networks ..."

    # Stop specific containers
    if $COMPOSE_CMD ps -q obsidian 2>/dev/null | grep -q .; then
        log_info "Stopping obsidian container ..."
        $COMPOSE_CMD stop obsidian 2>&1 | while read -r line; do log_debug "$line"; done
        $COMPOSE_CMD rm -v obsidian 2>&1 | while read -r line; do log_debug "$line"; done
    fi

    if $COMPOSE_CMD ps -q oauth2-proxy 2>/dev/null | grep -q .; then
        log_info "Stopping oauth2-proxy container ..."
        $COMPOSE_CMD stop oauth2-proxy 2>&1 | while read -r line; do log_debug "$line"; done
        $COMPOSE_CMD rm -v oauth2-proxy 2>&1 | while read -r line; do log_debug "$line"; done
    fi

    # Remove obsidian-specific network
    if docker network ls | grep -q "obsidian-net"; then
        log_info "Removing obsidian-net network ..."
        docker network rm obsidian-net 2>&1 | while read -r line; do log_debug "$line"; done
    fi

    # Remove obsidian-specific volumes (named volumes from compose)
    log_info "Removing obsidian volumes ..."
    docker volume ls -q | grep -E "obsidian" | xargs -r docker volume rm 2>&1 | while read -r line; do log_debug "$line"; done

    log_success "Obsidian and oauth2-proxy containers stopped, related volumes and networks removed"
    tc_block_close "stop"
}

start_containers() {
    tc_block_open "start"
    log_info "Starting containers (detached) with rebuild ..."
    $COMPOSE_CMD up -d --build --remove-orphans 2>&1 | while read -r line; do log_debug "$line"; done
    log_success "Containers started and rebuilt"
    tc_block_close "start"
}

# ---------------------------------------------------------------------------
# Health checks
# ---------------------------------------------------------------------------
wait_for_health() {
    tc_block_open "healthcheck"
    log_info "Waiting for services to be healthy ..."

    local max_wait="${HEALTH_MAX_WAIT:-300}"
    local interval="${HEALTH_INTERVAL:-10}"
    local elapsed=0
    local obs_ok=0
    local oauth_ok=0

    while [[ $elapsed -lt $max_wait ]]; do
        # Check Obsidian (has explicit healthcheck)
        if [[ $obs_ok -eq 0 ]]; then
            if $COMPOSE_CMD ps obsidian 2>/dev/null | grep -q "healthy"; then
                log_success "Obsidian is healthy"
                obs_ok=1
            fi
        fi

        # Check oauth2-proxy (no native healthcheck; verify Up + port response)
        if [[ $oauth_ok -eq 0 ]]; then
            if $COMPOSE_CMD ps oauth2-proxy 2>/dev/null | grep -q "Up"; then
                if docker exec oauth2-proxy wget -qO- http://localhost:4180/ping --timeout=3 &>/dev/null || \
                   curl -sf http://localhost:${HTTP_PORT:-3000}/ping &>/dev/null; then
                    log_success "OAuth2 proxy is responding"
                    oauth_ok=1
                fi
            fi
        fi

        if [[ $obs_ok -eq 1 && $oauth_ok -eq 1 ]]; then
            tc_block_close "healthcheck"
            return 0
        fi

        log_info "Waiting ... obs=$obs_ok oauth=$oauth_ok (${elapsed}/${max_wait}s)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    # Timeout — show diagnostics before failing
    log_error "Health check timeout (${max_wait}s)"
    echo ""
    echo "--- Container status ---"
    $COMPOSE_CMD ps
    echo ""
    echo "--- Obsidian last 50 lines ---"
    $COMPOSE_CMD logs --tail=50 obsidian 2>&1 || true
    echo ""
    echo "--- OAuth2-proxy last 50 lines ---"
    $COMPOSE_CMD logs --tail=50 oauth2-proxy 2>&1 || true
    tc_block_close "healthcheck"
    return 1
}

# ---------------------------------------------------------------------------
# Status / reporting
# ---------------------------------------------------------------------------
show_status() {
    tc_block_open "status"
    echo ""
    echo "========== DEPLOYMENT STATUS =========="
    $COMPOSE_CMD ps
    echo ""
    echo "--- Services ---"
    echo "  Obsidian (via OAuth2): http://localhost:${HTTP_PORT:-3000}"
    echo "  OAuth2 Proxy internal:  http://oauth2-proxy:4180"
    echo ""
    tc_block_close "status"
}

# ---------------------------------------------------------------------------
# Main deploy pipeline
# ---------------------------------------------------------------------------
deploy() {
    tc_block_open "deploy"
    log_info "Starting deployment pipeline ..."

    check_dependencies || exit 1
    validate_compose   || exit 1
    check_env_vars     || exit 1
    build_images       || exit 1
    stop_containers
    start_containers   || exit 1
    wait_for_health    || exit 1
    show_status

    log_success "Deployment completed successfully!"
    tc_block_close "deploy"
    tc_status NORMAL "Deployment succeeded"
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
CMD="${1:-deploy}"

log_info "Compose command: $COMPOSE_CMD"
log_info "Command: $CMD"

case "$CMD" in
    "deploy")
        deploy
        ;;
    "build")
        check_dependencies || exit 1
        validate_compose   || exit 1
        check_env_vars     || exit 1
        build_images
        ;;
    "validate")
        check_dependencies || exit 1
        validate_compose   || exit 1
        check_env_vars     || exit 1
        log_success "Validation passed"
        ;;
    "stop")
        stop_containers
        ;;
    "start")
        start_containers
        ;;
    "restart")
        stop_containers
        start_containers || exit 1
        wait_for_health  || exit 1
        show_status
        ;;
    "status")
        show_status
        ;;
    "logs")
        $COMPOSE_CMD logs -f --tail=100
        ;;
    "health")
        wait_for_health
        ;;
    *)
        log_raw "Usage: $0 {deploy|build|validate|stop|start|restart|status|logs|health}"
        log_raw ""
        log_raw "Commands:"
        log_raw "  deploy   - Full deployment (default)"
        log_raw "  build    - Pull / build images only"
        log_raw "  validate - Validate compose + env without deploying"
        log_raw "  stop     - Stop containers"
        log_raw "  start    - Start containers"
        log_raw "  restart  - Restart containers"
        log_raw "  status   - Show container status"
        log_raw "  logs     - Tail container logs"
        log_raw "  health   - Wait for services to be healthy"
        exit 1
        ;;
esac
