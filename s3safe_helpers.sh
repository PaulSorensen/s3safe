# Helper function to log notifications
log() {
    # Usage: log "message"
    echo "$1" | tee -a "$LOG_FILE"
}

# Helper function to log errors
log_error() {
    # Usage: log_error "error message"
    echo -e "${RED}$1${NC}"
    echo "$1" >> "$LOG_FILE"
}

# Helper function to send notifications
send_notification() {
    if [ "$NOTIFICATIONS" = "on" ]; then
        SUCCESS=0
        (
            [ -n "$NTFY_TOPIC" ] && curl -s -H "Priority: high" -d "$MSG" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>/dev/null && SUCCESS=1
            [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] && curl -s \
                --data chat_id="$TELEGRAM_CHAT_ID" \
                --data-urlencode "text=$MSG" \
                "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage?parse_mode=HTML" >/dev/null 2>/dev/null && SUCCESS=1
            [ -n "$WEBHOOK_URL" ] && curl -s -X POST -H "Content-Type: text/plain" -d "$MSG" "$WEBHOOK_URL" >/dev/null 2>/dev/null && SUCCESS=1
            exit $SUCCESS
        )
        if [ $? -eq 1 ]; then
            log "Notification sent successfully"
        else
            log_error "Failed to send notification"
        fi
    fi
}