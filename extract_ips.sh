#!/bin/bash
echo "========================================="
echo "       Nginx Log - Unique IP Report      "
echo "========================================="

docker exec nginx_server awk '{ count[$1]++ } END { for (ip in count) printf "%-10s %s\n", count[ip], ip }' /var/log/nginx/access.log

echo "========================================="

