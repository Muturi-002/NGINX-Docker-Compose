# Blue/Green Deployment with NGINX and Docker Compose

*HNG13 DevOps Stage-2 task*

A robust Blue/Green deployment implementation using NGINX as a load balancer with automatic failover capabilities.

## Quick Start

1. **Setup Environment**
   ```bash
   cp .env.example .env
   # Edit .env with your Docker images
   ```

2. **Deploy Services**
   ```bash
   ./manage.sh deploy
   ```

3. **Test Deployment**
   ```bash
   ./test.sh all
   ```

4. **Switch Between Blue/Green**
   ```bash
   ./manage.sh switch
   ```

## Monitoring

- **Main Service**: http://localhost:8080/version
- **Blue Direct**: http://localhost:8081/version  
- **Green Direct**: http://localhost:8082/version

## Chaos Testing

```bash
# Start chaos on active pool
./manage.sh chaos-start

# Monitor traffic routing
watch -n 1 'curl -s http://localhost:8080/version | grep X-App-Pool'

# Stop chaos
./manage.sh chaos-stop
```

## Troubleshooting

- Check service status: `./manage.sh status`
- View logs: `./manage.sh logs [service]`
- Test endpoints: `./manage.sh test`

## Features

- Automatic failover from Blue to Green
- Zero downtime deployments
- Health-based routing
- Header preservation
- Chaos engineering support
- Comprehensive testing suite

## Test Script

Below is the complete test script for validating the Blue/Green deployment:

```bash
#!/bin/bash

# Blue/Green Testing Script
# This script tests the Blue/Green deployment functionality

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MAIN_URL="http://localhost:8080"
BLUE_URL="http://localhost:8081"
GREEN_URL="http://localhost:8082"
TEST_DURATION=10  # seconds
REQUEST_INTERVAL=0.5  # seconds

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

# Test baseline functionality (Blue active by default)
test_baseline() {
    log_info "Testing baseline (Blue active by default)..."
    
    local response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$MAIN_URL/version")
    local http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')
    
    if [[ "$http_code" == "200" ]]; then
        log_success "Baseline test passed (HTTP $http_code)"
        
        # Get headers separately
        local headers=$(curl -s -I "$MAIN_URL/version")
        
        # Check if Blue is responding (should be the case normally)
        if echo "$headers" | grep -q "X-App-Pool: blue"; then
            log_success "Traffic routed to Blue (primary)"
        elif echo "$headers" | grep -q "X-App-Pool: green"; then
            log_warning "Traffic routed to Green - may indicate Blue is down"
        else
            log_warning "X-App-Pool header not found"
        fi
        
        echo "Response body: $body"
    else
        log_error "Baseline test failed (HTTP $http_code)"
        return 1
    fi
}

# Test chaos engineering - Blue failure should trigger automatic failover to Green
test_chaos() {
    log_info "Testing chaos engineering and automatic failover..."
    
    # Start chaos on Blue (always the primary)
    log_warning "Starting chaos on Blue service (primary)..."
    curl -s -X POST "$BLUE_URL/chaos/start?mode=error" > /dev/null
    
    sleep 2  # Give some time for chaos to take effect and NGINX to detect failure
    
    # Test automatic failover to Green
    local success_count=0
    local total_count=0
    local green_responses=0
    
    log_info "Testing automatic failover for $TEST_DURATION seconds..."
    local end_time=$((SECONDS + TEST_DURATION))
    
    while [[ $SECONDS -lt $end_time ]]; do
        local response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$MAIN_URL/version" 2>/dev/null || echo "HTTPSTATUS:000")
        local http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
        local body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')
        
        ((total_count++))
        
        if [[ "$http_code" == "200" ]]; then
            ((success_count++))
            
            # Check headers to see which pool is responding
            local headers=$(curl -s -I "$MAIN_URL/version" 2>/dev/null)
            if echo "$headers" | grep -q "X-App-Pool: green"; then
                ((green_responses++))
            fi
        else
            log_warning "Non-200 response: $http_code"
        fi
        
        sleep "$REQUEST_INTERVAL"
    done
    
    # Stop chaos
    log_info "Stopping chaos..."
    curl -s -X POST "$BLUE_URL/chaos/stop" > /dev/null
    curl -s -X POST "$GREEN_URL/chaos/stop" > /dev/null
    
    # Calculate success rate
    local success_rate=$((success_count * 100 / total_count))
    local green_rate=$((green_responses * 100 / total_count))
    
    log_info "Failover Test Results:"
    echo "  Total requests: $total_count"
    echo "  Successful requests: $success_count"
    echo "  Success rate: $success_rate%"
    echo "  Responses from Green: $green_responses"
    echo "  Green response rate: $green_rate%"
    
    # Validate results per markdown requirements
    if [[ $success_rate -eq 100 ]]; then
        log_success "Zero failed requests during failover (required: 0 non-200s)"
    else
        log_error "Found failed requests during failover"
        return 1
    fi
    
    if [[ $green_rate -ge 95 ]]; then
        log_success ">=95% responses from Green after failover (required: >=95%)"
    else
        log_warning "Only $green_rate% responses from Green (required: >=95%)"
        return 1
    fi
}

# Test header preservation
test_headers() {
    log_info "Testing header preservation..."
    
    local response=$(curl -s -i "$MAIN_URL/version")
    
    if echo "$response" | grep -q "X-App-Pool:"; then
        log_success "X-App-Pool header preserved"
    else
        log_error "X-App-Pool header missing"
        return 1
    fi
    
    if echo "$response" | grep -q "X-Release-Id:"; then
        log_success "X-Release-Id header preserved"
    else
        log_error "X-Release-Id header missing"
        return 1
    fi
}

# Test direct access to services
test_direct_access() {
    log_info "Testing direct access to Blue and Green services..."
    
    # Test Blue
    local blue_response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$BLUE_URL/version")
    local blue_code=$(echo "$blue_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    
    if [[ "$blue_code" == "200" ]]; then
        log_success "Blue service accessible on port 8081"
    else
        log_error "Blue service not accessible (HTTP $blue_code)"
    fi
    
    # Test Green
    local green_response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$GREEN_URL/version")
    local green_code=$(echo "$green_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    
    if [[ "$green_code" == "200" ]]; then
        log_success "Green service accessible on port 8082"
    else
        log_error "Green service not accessible (HTTP $green_code)"
    fi
}

# Run all tests
run_all_tests() {
    log_info "Starting Blue/Green Deployment Tests..."
    echo "=========================================="
    
    local test_failed=false
    
    # Run tests
    test_direct_access || test_failed=true
    echo ""
    
    test_baseline || test_failed=true
    echo ""
    
    test_headers || test_failed=true
    echo ""
    
    test_chaos || test_failed=true
    echo ""
    
    # Final results
    echo "=========================================="
    if [[ "$test_failed" == "true" ]]; then
        log_error "Some tests failed"
        exit 1
    else
        log_success "All tests passed!"
    fi
}

# Command handling
case "${1:-all}" in
    "baseline")
        test_baseline
        ;;
    "chaos")
        test_chaos
        ;;
    "headers")
        test_headers
        ;;
    "direct")
        test_direct_access
        ;;
    "all")
        run_all_tests
        ;;
    *)
        echo "Blue/Green Testing Script"
        echo ""
        echo "Usage: $0 {baseline|chaos|headers|direct|all}"
        echo ""
        echo "Commands:"
        echo "  baseline - Test basic functionality"
        echo "  chaos    - Test chaos engineering and failover"
        echo "  headers  - Test header preservation"
        echo "  direct   - Test direct access to services"
        echo "  all      - Run all tests (default)"
        exit 1
        ;;
esac
```

### How to Use the Test Script

1. **Save the script** to a file named `test.sh`
2. **Make it executable**: `chmod +x test.sh`
3. **Run all tests**: `./test.sh all`
4. **Run individual tests**: `./test.sh baseline`, `./test.sh chaos`, etc.
