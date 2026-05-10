#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  extract_ips.sh  –  Extract Unique IP Addresses from Web Logs
#
#  Works with:  Nginx access logs, Apache access logs
#
#  Usage:
#    chmod +x extract_ips.sh
#    ./extract_ips.sh                          # uses default log path
#    ./extract_ips.sh /path/to/access.log      # custom log file
#    ./extract_ips.sh --docker                 # reads from Docker container
#
#  Output:  Sorted list of unique IPs with request count
# ═══════════════════════════════════════════════════════════════

set -euo pipefail   # exit on error, undefined vars, pipe failures

# ── Color codes for pretty output ──────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'   # No Color (reset)

# ── Default log locations ───────────────────────────────────────
NGINX_LOG_DEFAULT="/var/log/nginx/access.log"
APACHE_LOG_DEFAULT="/var/log/apache2/access.log"
DOCKER_CONTAINER="nginx_server"              # container name from docker-compose

# ── Output file (optional – leave blank to only print to screen)
OUTPUT_FILE="unique_ips_$(date +%Y%m%d_%H%M%S).txt"

# ═══════════════════════════════════════════════════════════════
#  FUNCTION: print a section header
# ═══════════════════════════════════════════════════════════════
print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════════════════
#  FUNCTION: extract IPs from a log file
#  Nginx / Apache Combined Log Format:
#    192.168.1.1 - - [01/Jan/2024:00:00:01 +0000] "GET / HTTP/1.1" 200 ...
#  The IP address is always the FIRST field (column 1)
# ═══════════════════════════════════════════════════════════════
extract_ips() {
    local log_file="$1"

    print_header "Extracting IPs from: $log_file"

    # Validate file exists and is readable
    if [[ ! -f "$log_file" ]]; then
        echo -e "${RED}❌ File not found: $log_file${NC}"
        exit 1
    fi

    if [[ ! -r "$log_file" ]]; then
        echo -e "${RED}❌ Permission denied: $log_file${NC}"
        echo -e "${YELLOW}   Try running with: sudo ./extract_ips.sh${NC}"
        exit 1
    fi

    local total_lines
    total_lines=$(wc -l < "$log_file")
    echo -e "${GREEN}📄 Total log lines : $total_lines${NC}"

    # ── Core extraction pipeline ──────────────────────────────
    # awk '{print $1}'     → grab column 1 (the IP address)
    # grep -E '...'        → keep only valid IPv4 addresses
    # sort                 → sort alphabetically
    # uniq -c              → count duplicates, keep one of each
    # sort -rn             → sort by count (highest first)
    # ──────────────────────────────────────────────────────────
    local ip_data
    ip_data=$(awk '{print $1}' "$log_file" \
        | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' \
        | sort \
        | uniq -c \
        | sort -rn)

    local unique_count
    unique_count=$(echo "$ip_data" | wc -l)

    echo -e "${GREEN}🌐 Unique IP count  : $unique_count${NC}\n"

    # ── Print formatted table ─────────────────────────────────
    echo -e "${YELLOW}  REQUESTS   IP ADDRESS${NC}"
    echo    "  ─────────  ─────────────────"

    while IFS= read -r line; do
        count=$(echo "$line" | awk '{print $1}')
        ip=$(echo "$line"    | awk '{print $2}')
        printf "  %-9s  %s\n" "$count" "$ip"
    done <<< "$ip_data"

    # ── Save to output file ───────────────────────────────────
    {
        echo "# IP Extraction Report"
        echo "# Generated : $(date)"
        echo "# Log file  : $log_file"
        echo "# Total lines: $total_lines | Unique IPs: $unique_count"
        echo "#"
        echo "# REQUESTS   IP_ADDRESS"
        echo "$ip_data" | awk '{printf "%-11s %s\n", $1, $2}'
    } > "$OUTPUT_FILE"

    echo -e "\n${GREEN}✅ Report saved to: ${OUTPUT_FILE}${NC}"
}

# ═══════════════════════════════════════════════════════════════
#  FUNCTION: extract IPs from a Docker container's logs
# ═══════════════════════════════════════════════════════════════
extract_from_docker() {
    print_header "Extracting IPs from Docker container: $DOCKER_CONTAINER"

    if ! docker ps --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
        echo -e "${RED}❌ Container '$DOCKER_CONTAINER' is not running.${NC}"
        echo -e "${YELLOW}   Start it with: docker-compose up -d${NC}"
        exit 1
    fi

    # Copy log from container to temp file, then process it
    local tmp_log="/tmp/nginx_access_$$.log"
    docker cp "${DOCKER_CONTAINER}:/var/log/nginx/access.log" "$tmp_log"

    extract_ips "$tmp_log"
    rm -f "$tmp_log"   # clean up temp file
}

# ═══════════════════════════════════════════════════════════════
#  MAIN LOGIC – decide which log source to use
# ═══════════════════════════════════════════════════════════════
main() {
    print_header "🔍 Nginx/Apache Log IP Extractor"

    # Check if a custom log path or flag was given
    if [[ "${1:-}" == "--docker" ]]; then
        extract_from_docker

    elif [[ -n "${1:-}" ]]; then
        # User passed a custom file path
        extract_ips "$1"

    elif [[ -f "$NGINX_LOG_DEFAULT" ]]; then
        # Auto-detect Nginx log
        echo -e "${CYAN}Auto-detected Nginx log...${NC}"
        extract_ips "$NGINX_LOG_DEFAULT"

    elif [[ -f "$APACHE_LOG_DEFAULT" ]]; then
        # Auto-detect Apache log
        echo -e "${CYAN}Auto-detected Apache log...${NC}"
        extract_ips "$APACHE_LOG_DEFAULT"

    else
        echo -e "${RED}❌ No log file found automatically.${NC}"
        echo ""
        echo "Usage:"
        echo "  ./extract_ips.sh                            # auto-detect"
        echo "  ./extract_ips.sh /path/to/access.log       # custom file"
        echo "  ./extract_ips.sh --docker                  # from Docker container"
        exit 1
    fi
}

main "$@"
