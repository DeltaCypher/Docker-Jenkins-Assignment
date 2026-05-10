#!/bin/bash

ACCESS_LOG="/var/log/nginx/access.log"
ERROR_LOG="/var/log/nginx/error.log"

echo "Unique IP Addresses from Access and Error Logs"
echo "------------------------------------------------"

cat $ACCESS_LOG $ERROR_LOG 2>/dev/null | \
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
sort | uniq
