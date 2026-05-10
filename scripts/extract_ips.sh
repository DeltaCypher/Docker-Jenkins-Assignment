#!/bin/bash
# extract_ips.sh
# Extracts unique IP addresses from Nginx access log

echo "========================================="
echo "       Nginx Log - Unique IP Report      "
echo "========================================="
echo "Date: $(date)"
echo ""

# Copy nginx access log from container to a temp file
docker cp nginx_server:/var/log/nginx/access.log /tmp/nginx_access.log

# Check if log file exists and has content
if [ ! -s /tmp/nginx_access.log ]; then
    echo "Log file is empty or not found."
    exit 1
fi

echo "Total Requests: $(wc -l < /tmp/nginx_access.log)"
echo ""

# Extract IPs:
# awk '{print $1}'  → get first column (IP address)
# sort              → sort them
# uniq -c           → count duplicates, keep unique
# sort -rn          → sort by count highest first
echo "COUNT      IP ADDRESS"
echo "---------  ---------------"
awk '{print $1}' /tmp/nginx_access.log | sort | uniq -c | sort -rn | \
    awk '{printf "%-10s %s\n", $1, $2}'

echo ""
echo "========================================="
echo "Unique IPs: $(awk '{print $1}' /tmp/nginx_access.log | sort -u | wc -l)"
echo "========================================="

# Cleanup
rm -f /tmp/nginx_access.log
