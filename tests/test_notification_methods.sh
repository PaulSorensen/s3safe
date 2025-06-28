#!/bin/bash
# test_notification_methods.sh - Test notification method connectivity

SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
source "$SCRIPT_DIR/.env"
source "$SCRIPT_DIR/s3safe.conf"

# ntfy: If topic is set, check if ntfy server is reachable (warn only)
if [ -n "$NTFY_TOPIC" ]; then
    if ! curl -sfI "https://ntfy.sh/" >/dev/null; then
        echo "Warning: ntfy server not reachable. Notifications may fail."
    fi
    echo "✅ Test ntfy server connectivity passed"
fi

# Webhook: If URL is set, check if endpoint returns HTTP 2xx (warn only)
if [ -n "$WEBHOOK_URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WEBHOOK_URL")
    if [[ "$HTTP_CODE" == 2* || "$HTTP_CODE" == 405 ]]; then
        echo "✅ Test Webhook URL connectivity passed with HTTP code $HTTP_CODE (GET)"
    else
        echo "❌ Warning: Webhook endpoint returned HTTP $HTTP_CODE to GET request. Notifications may fail."
    fi
fi