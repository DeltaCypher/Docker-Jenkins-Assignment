#!/bin/bash
echo "========================================="
echo "       Nginx Log - Unique IP Report      "
echo "========================================="

docker exec nginx_server awk '
{
    count[$1]++
}
END {
    print "COUNT      IP ADDRESS"
    print "---------  ---------------"
    for (ip in count) {
        printf "%-10s %s\n", count[ip], ip
    }
    print "Unique IPs: " length(count)
}
' /var/log/nginx/access.log

echo "========================================="
