#!/bin/bash

# Blue/Green Deployment Management Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
NGINX_CONTAINER="nginx-lb"

# Helper functions
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

# Check if environment file exists
check_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file $ENV_FILE not found!"
        log_info "Please copy .env.example to .env and configure it"
        exit 1
    fi
}

# Get current active pool from environment
get_active_pool() {
    if [[ -f "$ENV_FILE" ]]; then
        grep "^ACTIVE_POOL=" "$ENV_FILE" | cut -d'=' -f2
    else
        echo "blue"  # Default to blue as per requirements
    fi
}

# Simulate chaos on Blue (active pool) - Blue fails, traffic goes to Green
chaos_start() {
    log_warning "Starting chaos on Blue service (active pool)..."
    curl -X POST "http://localhost:8081/chaos/start?mode=error"
    log_warning "Chaos started on Blue. NGINX should automatically failover to Green."
    log_info "Monitor traffic routing with: watch -n 1 'curl -s http://localhost:8080/version | grep X-App-Pool'"
}

# Deploy services
deploy() {
    log_info "Deploying Blue/Green services..."
    check_env
    
    docker-compose -f "$COMPOSE_FILE" up -d
    
    log_success "Deployment completed"
    show_status
}

# Stop services
stop() {
    log_info "Stopping all services..."
    docker-compose -f "$COMPOSE_FILE" down
    log_success "All services stopped"
}

# Show service status
show_status() {
    log_info "Service Status:"
    echo "=================="
    
    local active_pool=$(get_active_pool)
    echo "Active Pool: blue (primary), green (backup)"
    echo ""
    
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    log_info "Endpoints:"
    echo "- Main Service (NGINX): http://localhost:8080"
    echo "- Blue Direct Access: http://localhost:8081"
    echo "- Green Direct Access: http://localhost:8082"
}

# Test endpoints
test_endpoints() {
    log_info "Testing endpoints..."
    
    echo "Testing main service (via NGINX):"
    curl -s -w "Status: %{http_code}\n" http://localhost:8080/version || log_warning "Main service not responding"
    
    echo ""
    echo "Testing Blue service directly:"
    curl -s -w "Status: %{http_code}\n" http://localhost:8081/version || log_warning "Blue service not responding"
    
    echo ""
    echo "Testing Green service directly:"
    curl -s -w "Status: %{http_code}\n" http://localhost:8082/version || log_warning "Green service not responding"
}

# Stop chaos
chaos_stop() {
    log_info "Stopping chaos on both pools..."
    curl -X POST "http://localhost:8081/chaos/stop" 2>/dev/null || true
    curl -X POST "http://localhost:8082/chaos/stop" 2>/dev/null || true
    log_success "Chaos stopped"
}

# Show logs
show_logs() {
    local service=${1:-}
    if [[ -n "$service" ]]; then
        docker-compose -f "$COMPOSE_FILE" logs -f "$service"
    else
        docker-compose -f "$COMPOSE_FILE" logs -f
    fi
}

# Main command handling
case "${1:-}" in
    "deploy")
        deploy
        ;;
    "stop")
        stop
        ;;
    "status")
        show_status
        ;;
    "test")
        test_endpoints
        ;;
    "chaos-start")
        chaos_start
        ;;
    "chaos-stop")
        chaos_stop
        ;;
    "logs")
        show_logs "${2:-}"
        ;;
    *)
        echo "Blue/Green Deployment Management Script"
        echo ""
        echo "Usage: $0 {deploy|stop|status|test|chaos-start|chaos-stop|logs}"
        echo ""
        echo "Commands:"
        echo "  deploy      - Deploy all services (Blue active, Green backup)"
        echo "  stop        - Stop all services"
        echo "  status      - Show service status"
        echo "  test        - Test all endpoints"
        echo "  chaos-start - Start chaos engineering on Blue (active pool)"
        echo "  chaos-stop  - Stop chaos engineering"
        echo "  logs [svc]  - Show logs (optionally for specific service)"
        echo ""
        echo "Note: Blue is always active, Green is backup as per requirements"
        echo ""
        echo "Examples:"
        echo "  $0 deploy"
        echo "  $0 chaos-start  # Triggers failover to Green"
        echo "  $0 logs nginx"
        exit 1
        ;;
esac