#!/usr/bin/env bash

# Record start time for runtime calculation
START_TIME=$(date +%s.%N)

# Uptime Kuma Push Script
# Monitors ping latency and total disk usage, and pushes to Uptime Kuma
# Check if bc is installed
if ! command -v bc &> /dev/null; then
    echo "Error: bc command not found. Please install bc package."
    echo "For Ubuntu/Debian: sudo apt-get install bc"
    echo "For CentOS/RHEL: sudo yum install bc"
    echo "For Alpine: sudo apk add bc"
    exit 1
fi
# Check if curl or wget is available
if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    echo "Error: Neither curl nor wget found. Please install one of them."
    echo "For Ubuntu/Debian: sudo apt-get install curl   OR   sudo apt-get install wget"
    echo "For CentOS/RHEL: sudo yum install curl   OR   sudo yum install wget"
    echo "For Alpine: sudo apk add curl   OR   sudo apk add wget"
    exit 1
fi
# --- Configuration ---
# Base Uptime Kuma Push URL with default parameters
UPTIME_KUMA_PUSH_URL="https://xxx.xxx/api/push/xxxxxxyyyyed"
# DNS servers to ping (multiple for better accuracy)
DNS_SERVERS=(
    "1.1.1.1"      # Cloudflare DNS
    # "1.0.0.1"
    "8.8.8.8"      # Google DNS
    # "8.8.4.4"
    "9.9.9.9"      # IBM DNS
    # "77.88.8.8"    # Yandex DNS
    "94.140.14.14" # AdGuard DNS
    "223.5.5.5"    # Aliyun DNS
    # "223.6.6.6"
    "119.29.29.29" # Tencent DNSPod
    # "119.28.28.28"
    "180.76.76.76" # Baidu DNS
    "180.184.1.1"  # ByteDance DNS
    # "101.226.4.6"  # 360 DNS
)
# Number of ping packets per server
PING_COUNT=3
# Disk usage threshold percentage (if usage >= threshold, status is 'down')
DISK_THRESHOLD="90"

# --- Get Average Ping Latency ---
# Ping multiple DNS servers and calculate weighted average
total_latency=0
successful_servers=0
total_servers=${#DNS_SERVERS[@]}
network_status="ok"
network_message=""

# Function to safely calculate with bc, with fallback
safe_calc() {
    if command -v bc &> /dev/null; then
        echo "$1" | bc -l
    else
        # Fallback to awk for basic calculations
        echo "$1" | awk '{print $0+0}'
    fi
}

for dns in "${DNS_SERVERS[@]}"; do
    echo "Pinging $dns..."
    ping_output=$(ping -c $PING_COUNT $dns 2>&1)
    
    # Check if ping was successful (received responses)
    packets_received=$(echo "$ping_output" | grep -o '[0-9]* received' | awk '{print $1}')
    
    if [[ "$packets_received" =~ ^[0-9]+$ ]] && [ "$packets_received" -gt 0 ]; then
        # Extract average latency
        if [[ "$ping_output" == *"rtt min/avg/max/mdev"* ]]; then
            avg_latency=$(echo "$ping_output" | grep 'rtt min/avg/max/mdev' | awk -F'/' '{print $5}' | awk '{print $1}')
        elif [[ "$ping_output" == *"round-trip min/avg/max"* ]]; then
            avg_latency=$(echo "$ping_output" | grep -E 'round-trip min/avg/max = [0-9.]+/[0-9.]+/[0-9.]+' | awk -F'/' '{print $5}' | awk '{print $1}')
        fi
        
        if [[ -n "$avg_latency" && "$avg_latency" =~ ^[0-9.]+$ ]]; then
            total_latency=$(safe_calc "$total_latency + $avg_latency")
            successful_servers=$((successful_servers + 1))
        fi
    fi
done

# Calculate final average with proper error handling
AVERAGE_PING=0
if [ $successful_servers -gt 0 ]; then
    echo "$total_latency / $successful_servers"
    base_avg=$(safe_calc "scale=2; $total_latency / $successful_servers")
    
    # 负载因子（1.0 = 全部成功，2.0 = 一半成功，5.0 = 1/5成功）
    echo "successful_servers: $total_servers / $successful_servers"
    load_factor=$(safe_calc "scale=2; $total_servers / $successful_servers")
    
    echo "load_factor: $load_factor"
    # 应用负载因子
    AVERAGE_PING=$(safe_calc "scale=2; $base_avg * $load_factor")
    
    # 检查网络健康状态
    if (( $(echo "$load_factor > 2.5" | bc -l 2>/dev/null || echo "0") )) || (( $(echo "$AVERAGE_PING > 5000" | bc -l 2>/dev/null || echo "0") )); then
        network_status="degraded"
        network_message="$successful_servers/$total_servers DNS servers responding (high latency: ${AVERAGE_PING}ms)"
    fi
else
    network_status="failed"
    network_message="All DNS servers unreachable"
fi

# Format ping value
AVERAGE_PING=$(echo "$AVERAGE_PING" | awk '{printf "%.3f", $1}')
if [ -z "$AVERAGE_PING" ] || [ "$(echo "$AVERAGE_PING" | awk '{print $1}')" = "0.000" ]; then
    AVERAGE_PING=0
fi

# --- Get Total Disk Usage ---
# Get root filesystem usage percentage
TOTAL_DISK_USAGE=$(df -P / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

# Check if we got a number
if [[ -z "$TOTAL_DISK_USAGE" || ! "$TOTAL_DISK_USAGE" =~ ^[0-9]+$ ]]; then
    TOTAL_DISK_USAGE=0
fi

# --- Determine Service Status ---
SERVICE_STATUS="up"
STATUS_MESSAGE=""

# Check disk usage first
if [[ "$TOTAL_DISK_USAGE" -ge "$DISK_THRESHOLD" ]]; then
    SERVICE_STATUS="down"
    STATUS_MESSAGE="Disk usage critical: ${TOTAL_DISK_USAGE}% (threshold: ${DISK_THRESHOLD}%)"
fi

# Check network connectivity
if [ "$network_status" = "failed" ] || [ "$network_status" = "degraded" ]; then
    SERVICE_STATUS="down"
    if [ -z "$STATUS_MESSAGE" ]; then
        STATUS_MESSAGE="$network_message"
    else
        STATUS_MESSAGE="${STATUS_MESSAGE}; $network_message"
    fi
fi

# If still up, create a good status message
if [ "$SERVICE_STATUS" = "up" ]; then
    STATUS_MESSAGE="OK: ${AVERAGE_PING}ms avg latency, ${successful_servers}/${total_servers} DNS servers, Disk: ${TOTAL_DISK_USAGE}%"
fi

# --- URL Encoding Function ---
# Fallback URL encoding function if jq is not available
url_encode() {
    local input="$1"
    if command -v jq &> /dev/null; then
        printf '%s' "$input" | jq -sRr @uri
    else
        # Simple URL encoding fallback
        printf '%s' "$input" | sed 's/[^a-zA-Z0-9._~-]/%&/g; s/%\(..\)/\\x\1/g' | xargs -0 printf '%b' 2>/dev/null | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/#/%23/g; s/\$/%24/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/*/%2A/g; s/+/%2B/g; s/,/%2C/g; s/\//%2F/g; s/:/%3A/g; s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g; s/\[/%5B/g; s/\\/%5C/g; s/\]/%5D/g; s/{/%7B/g; s/}/%7D/g'
    fi
}

# --- Execute Curl Command ---
ENCODED_MSG=$(url_encode "$STATUS_MESSAGE")
BASE_URL="${UPTIME_KUMA_PUSH_URL%%\?*}"
FULL_URL="${BASE_URL}?status=${SERVICE_STATUS}&msg=${ENCODED_MSG}&ping=${AVERAGE_PING}&uptime_kuma_cachebuster=$(date +%s%N)"

# Use curl if available, fallback to wget
if command -v curl &> /dev/null; then
    curl --silent --max-time 10 "${FULL_URL}" --header "User-Agent: Uptime-Kuma-Yuhiri/2" -o /dev/null
    CURL_EXIT_CODE=$?
else
    wget --quiet --timeout=10 --header="User-Agent: Uptime-Kuma-Yuhiri/2" "${FULL_URL}" -O /dev/null
    CURL_EXIT_CODE=$?
fi

# Calculate and display runtime
END_TIME=$(date +%s.%N)
RUNTIME=$(echo "$END_TIME - $START_TIME" | bc -l)
# Format runtime to 3 decimal places
RUNTIME_FORMATTED=$(printf "%.3f" $RUNTIME)

# --- Logging ---
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "DNS Servers Tested: ${#DNS_SERVERS[@]}"
echo "Successful Pings: ${successful_servers}"
echo "Average Ping: ${AVERAGE_PING}ms"
echo "Disk Usage: ${TOTAL_DISK_USAGE}%"
echo "Service Status: ${SERVICE_STATUS}"
echo "Status Message: ${STATUS_MESSAGE}"

# Hide sensitive webhook URL in logs
if [[ "$FULL_URL" == *"api/push/"* ]]; then
    # Extract base URL and mask the API key part
    BASE_URL=$(echo "$FULL_URL" | grep -o '^[^?]*')
    MASKED_URL=$(echo "$BASE_URL" | sed 's/\(.*api\/push\/\).*$/\1****MASKED****/')
    QUERY_PARAMS=$(echo "$FULL_URL" | grep -o '?.*')
    echo "Final Push URL: ${MASKED_URL}${QUERY_PARAMS}"
else
    echo "Final Push URL: [URL masked for security]"
fi

echo "Script Runtime: ${RUNTIME_FORMATTED} seconds"
echo "Exit Code: ${CURL_EXIT_CODE}"
echo ""