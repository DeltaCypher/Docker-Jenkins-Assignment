#!/bin/bash

# Log file path
LOG_FILE="/var/log/nginx/access.log"

echo "Unique IP Addresses:"
echo "---------------------"

# Extract unique IP addresses
awk '{print $1}' $LOG_FILE | sort | uniq
