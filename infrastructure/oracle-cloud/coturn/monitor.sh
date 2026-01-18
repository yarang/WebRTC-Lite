#!/bin/bash
###############################################################################
# Coturn TURN Server Health Check and Monitoring Script
#
# This script monitors the Coturn service health and provides metrics
# for integration with monitoring systems (Prometheus, etc.)
#
# Usage:
#   ./monitor.sh [--metrics|--health|--verbose]
#
# Requirements: REQ-U004, REQ-S003
###############################################################################

set -euo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

COTURN_SERVICE="coturn"
TURN_API_SERVICE="turn-api"
LOG_FILE="/var/log/turnserver.log"
HEALTH_LOG="/var/log/turn-health.log"
MAX_LOG_SIZE=10485760  # 10MB

###############################################################################
# COLOR OUTPUT
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

###############################################################################
# HEALTH CHECK FUNCTIONS
###############################################################################

check_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo "✓ $service is running"
        return 0
    else
        echo "✗ $service is NOT running"
        return 1
    fi
}

check_listening_ports() {
    local ports=("3478" "5349" "8080")
    local all_ok=true

    for port in "${ports[@]}"; do
        if netstat -ulnp 2>/dev/null | grep -q ":$port "; then
            echo "✓ Port $port is listening"
        else
            echo "✗ Port $port is NOT listening"
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        return 0
    else
        return 1
    fi
}

check_tls_certificate() {
    local domain="${DOMAIN:-turn.example.com}"
    local cert_file="/etc/letsencrypt/live/$domain/fullchain.pem"

    if [ -f "$cert_file" ]; then
        local expiry
        expiry=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
        local expiry_epoch
        expiry_epoch=$(date -d "$expiry" +%s)
        local current_epoch
        current_epoch=$(date +%s)
        local days_left
        days_left=$(( (expiry_epoch - current_epoch) / 86400 ))

        if [ "$days_left" -gt 30 ]; then
            echo "✓ TLS certificate valid ($days_left days remaining)"
            return 0
        else
            echo "✗ TLS certificate expiring soon ($days_left days remaining)"
            return 1
        fi
    else
        echo "✗ TLS certificate not found"
        return 1
    fi
}

check_log_file_size() {
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)

        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            echo "⚠ Log file size exceeds threshold ($(numfmt --to=iec "$size"))"
            return 1
        else
            echo "✓ Log file size OK ($(numfmt --to=iec "$size"))"
            return 0
        fi
    else
        echo "⚠ Log file not found"
        return 1
    fi
}

check_api_health() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null)

    if [ "$response" = "200" ]; then
        echo "✓ TURN API is healthy"
        return 0
    else
        echo "✗ TURN API is not responding (HTTP $response)"
        return 1
    fi
}

###############################################################################
# METRICS FUNCTIONS (PROMETHEUS FORMAT)
###############################################################################

get_connection_metrics() {
    # Parse connection count from logs
    local connections
    connections=$(grep -c "session allocated" "$LOG_FILE" 2>/dev/null || echo "0")

    # Parse active allocations
    local active
    active=$(netstat -anp 2>/dev/null | grep :3478 | grep ESTABLISHED | wc -l)

    cat << METRICS
# HELP turn_connections_total Total number of TURN connections
# TYPE turn_connections_total gauge
turn_connections_total $connections

# HELP turn_connections_active Currently active TURN connections
# TYPE turn_connections_active gauge
turn_connections_active $active

# HELP turn_uptime_seconds TURN server uptime in seconds
# TYPE turn_uptime_seconds gauge
turn_uptime_seconds $(systemctl show coturn -p ExecMainStartTimestamp --value | awk '{print $1,$2}' | xargs -I {} date -d {} +%s 2>/dev/null || echo "0")
METRICS
}

get_system_metrics() {
    # CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d% -f1)

    # Memory usage
    local mem_usage
    mem_usage=$(free | grep Mem | awk '{printf "%.2f", ($3/$2) * 100.0}')

    # Disk usage
    local disk_usage
    disk_usage=$(df -h /var/log | tail -1 | awk '{print $5}' | sed 's/%//')

    cat << METRICS
# HELP turn_cpu_usage_percent CPU usage percentage
# TYPE turn_cpu_usage_percent gauge
turn_cpu_usage_percent $cpu_usage

# HELP turn_memory_usage_percent Memory usage percentage
# TYPE turn_memory_usage_percent gauge
turn_memory_usage_percent $mem_usage

# HELP turn_disk_usage_percent Disk usage percentage
# TYPE turn_disk_usage_percent gauge
turn_disk_usage_percent $disk_usage
METRICS
}

get_error_metrics() {
    # Count errors in last hour
    local error_count
    error_count=$(tail -n 1000 "$LOG_FILE" 2>/dev/null | grep -c "error\|Error\|ERROR" || echo "0")

    # Count authentication failures
    local auth_failures
    auth_failures=$(tail -n 1000 "$LOG_FILE" 2>/dev/null | grep -c "401\|unauthorized\|Forbidden" || echo "0")

    cat << METRICS
# HELP turn_errors_total Total errors in log
# TYPE turn_errors_total gauge
turn_errors_total $error_count

# HELP turn_auth_failures_total Authentication failures
# TYPE turn_auth_failures_total gauge
turn_auth_failures_total $auth_failures
METRICS
}

###############################################################################
# DIAGNOSTIC FUNCTIONS
###############################################################################

run_diagnostics() {
    echo "=== Coturn Diagnostics ==="
    echo ""

    echo "--- Service Status ---"
    systemctl status coturn --no-pager -l
    echo ""

    echo "--- Listening Ports ---"
    netstat -tulpn | grep -E "3478|5349|8080"
    echo ""

    echo "--- Recent Errors (last 20) ---"
    tail -n 100 "$LOG_FILE" 2>/dev/null | grep -i "error\|Error\|ERROR" | tail -20 || echo "No errors found"
    echo ""

    echo "--- TLS Certificate ---"
    check_tls_certificate
    echo ""

    echo "--- Recent Connections ---"
    tail -n 50 "$LOG_FILE" 2>/dev/null | grep "session allocated" | tail -10 || echo "No connections found"
}

###############################################################################
# MAIN SCRIPT
###############################################################################

show_usage() {
    cat << USAGE
Usage: $0 [OPTIONS]

Options:
  --health         Run health checks only (exit 0 if healthy)
  --metrics        Output Prometheus metrics
  --diagnostics    Run full diagnostics
  --verbose        Show detailed output
  --help           Show this help message

Examples:
  $0 --health          # Check if TURN server is healthy
  $0 --metrics         # Get Prometheus metrics
  $0 --diagnostics     # Run full diagnostics
USAGE
}

main() {
    local mode="default"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --health)
                mode="health"
                shift
                ;;
            --metrics)
                mode="metrics"
                shift
                ;;
            --diagnostics)
                mode="diagnostics"
                shift
                ;;
            --verbose)
                set -x
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Execute based on mode
    case "$mode" in
        health)
            local exit_code=0
            check_service_status "$COTURN_SERVICE" || exit_code=1
            check_service_status "$TURN_API_SERVICE" || exit_code=1
            check_listening_ports || exit_code=1
            check_tls_certificate || exit_code=1
            check_api_health || exit_code=1
            exit "$exit_code"
            ;;
        metrics)
            echo "# Coturn TURN Server Metrics"
            echo "# Generated at: $(date -Iseconds)"
            echo ""
            get_connection_metrics
            echo ""
            get_system_metrics
            echo ""
            get_error_metrics
            ;;
        diagnostics)
            run_diagnostics
            ;;
        default)
            echo "=== Coturn Health Check ==="
            echo ""
            check_service_status "$COTURN_SERVICE"
            check_service_status "$TURN_API_SERVICE"
            check_listening_ports
            check_tls_certificate
            check_log_file_size
            check_api_health
            echo ""
            echo "For detailed diagnostics, run: $0 --diagnostics"
            echo "For Prometheus metrics, run: $0 --metrics"
            ;;
    esac
}

main "$@"
