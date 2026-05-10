#!/bin/bash
# extract_ips.sh
# Extracts unique IPs using only awk (fastest method - single pass)

echo "========================================="
echo "       Nginx Log - Unique IP Report      "
echo "========================================="

# Single awk command does everything in ONE pass:
# - reads log directly from container
# - counts each IP
# - prints result
# No sort, no uniq, no temp files = very fast
docker exec nginx_server awk '
{
    count[$1]++       # count each IP (column 1)
}
END {
    print "COUNT      IP ADDRESS"
    print "---------  ---------------"
    for (ip in count) {
        printf "%-10s %s\n", count[ip], ip
    }
    print "---------  ---------------"
    print "Unique IPs: " length(count)
}
' /var/log/nginx/access.log

echo "========================================="
