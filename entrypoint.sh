#!/bin/sh
set -eu

# Read scan_interval from config using imapfilter itself
SCAN_INTERVAL=$(imapfilter -e 'dofile("/app/config.lua"); print(CONFIG.scan_interval or 300); os.exit(0)' 2>/dev/null || echo 300)

echo "Starting scanner: interval=${SCAN_INTERVAL}s"

while true; do
    imapfilter -c /app/main.lua || echo "Error during scan"
    echo "$(date '+%Y-%m-%d %H:%M:%S') Sleeping ${SCAN_INTERVAL}s"
    sleep "$SCAN_INTERVAL"
done
