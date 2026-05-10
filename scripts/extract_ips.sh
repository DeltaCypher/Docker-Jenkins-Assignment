#!/bin/bash
# extract_ips.sh - Fast IP extraction directly from nginx container

echo "========================================="
echo "       Nginx Log - Unique IP Report      "
echo "========================================="

# Read log directly from container using docker exec
# No file copying needed - much faster!
LOG=$(docker exec nginx_server cat /var/log/nginx/access.log 2>/dev/null)

if [ -z "$LOG" ]; then
    echo "Log is empty or nginx container is not running."
    exit 1
fi

echo "Total Requests : $(echo "$LOG" | wc -l)"
echo ""
echo "COUNT      IP ADDRESS"
echo "---------  ---------------"
echo "$LOG" | awk '{print $1}' | sort | uniq -c | sort -rn | \
    awk '{printf "%-10s %s\n", $1, $2}'

echo ""
echo "Unique IPs : $(echo "$LOG" | awk '{print $1}' | sort -u | wc -l)"
echo "========================================="
