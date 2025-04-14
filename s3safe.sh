#!/bin/bash
################################################################################
# Script Name   : S3Safe
# Author        : Paul Sørensen
# Website       : https://paulsorensen.io
# GitHub        : https://github.com/paulsorensen
# Version       : 1.0
# Last Modified : 2025/04/14 13:30:18
#
# Description:
# Backs up websites, databases, and database users to S3-compatible storage with
# GPG encryption and sends push notifications on failure if enabled.
#
# Usage: Refer to README.md for details on how to use this script.
#
# If you found this script useful, a small tip is appreciated ❤️
# https://buymeacoffee.com/paulsorensen
################################################################################

BLUE='\033[38;5;81m'
RED='\033[38;5;203m'
NC='\033[0m'
echo -e "${BLUE}S3Safe by paulsorensen.io${NC}"
echo ""

# Check for required configuration files
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${RED}Error: .env file not found in $SCRIPT_DIR. Please copy .env.example to .env and edit it before running this script.${NC}"
    exit 1
fi
if [ ! -f "$SCRIPT_DIR/s3safe.conf" ]; then
    echo -e "${RED}Error: s3safe.conf file not found in $SCRIPT_DIR. Please copy s3safe.conf.example to s3safe.conf and edit it before running this script.${NC}"
    exit 1
fi

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Include sources
source "$SCRIPT_DIR/.env"
source "$SCRIPT_DIR/s3safe.conf"

# Check if GPG_RECIPIENT key exists in keyring
if [ -n "$GPG_RECIPIENT" ] && ! gpg --list-keys "$GPG_RECIPIENT" >/dev/null 2>&1; then
    echo -e "${RED}Public key '$GPG_RECIPIENT' not found in keyring. Make sure to import a public key and specify it in .env.${NC}"
    exit 1
fi

# Check S3 endpoint connectivity
if [ -n "$S3_ENDPOINT" ] && [ -n "$S3_BUCKET" ]; then
    S3_SUCCESS=0
    for ((i=0; i<3; i++)); do
        if aws s3 ls "s3://$S3_BUCKET" --endpoint-url "$S3_ENDPOINT" >/dev/null 2>&1; then
            S3_SUCCESS=1
            break
        fi
        [ "$DEBUG" = "on" ] && echo "S3 connectivity check attempt $((i+1)) failed, retrying in 5 seconds."
        sleep 5
    done
    if [ $S3_SUCCESS -eq 0 ]; then
        echo -e "${RED}Error: Cannot connect to S3 endpoint or access bucket after 3 attempts. Check credentials and endpoint in .env.${NC}"
        exit 1
    fi
fi

# Check Telegram bot connectivity
if [ "$TELEGRAM_NOTIFICATIONS" = "on" ]; then
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "${RED}Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is empty. Check .env${NC}"
        exit 1
    fi
    TELEGRAM_TOKEN_SUCCESS=0
    for ((i=0; i<3; i++)); do
        TOKEN_RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe" 2>&1)
        if echo "$TOKEN_RESPONSE" | grep -q '"ok":true'; then
            TELEGRAM_TOKEN_SUCCESS=1
            break
        fi
        [ "$DEBUG" = "on" ] && echo "Telegram bot token check attempt $((i+1)) failed, retrying in 5 seconds"
        sleep 5
    done
    if [ $TELEGRAM_TOKEN_SUCCESS -eq 0 ]; then
        echo -e "${RED}Error: Cannot connect to Telegram bot with token $TELEGRAM_BOT_TOKEN after 3 attempts. Response: $TOKEN_RESPONSE. Check TELEGRAM_BOT_TOKEN in .env${NC}"
        exit 1
    fi
    TELEGRAM_CHAT_SUCCESS=0
    for ((i=0; i<3; i++)); do
        CHAT_RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getChat" -d chat_id="$TELEGRAM_CHAT_ID" 2>&1)
        if echo "$CHAT_RESPONSE" | grep -q '"ok":true'; then
            TELEGRAM_CHAT_SUCCESS=1
            break
        fi
        [ "$DEBUG" = "on" ] && echo "Telegram chat ID check attempt $((i+1)) failed, retrying in 5 seconds"
        sleep 5
    done
    if [ $TELEGRAM_CHAT_SUCCESS -eq 0 ]; then
        echo -e "${RED}Error: Cannot access Telegram chat $TELEGRAM_CHAT_ID after 3 attempts. Response: $CHAT_RESPONSE. Check TELEGRAM_CHAT_ID in .env${NC}"
        exit 1
    fi
fi

# Check log directory
if [ -z "$LOG_DIR" ]; then
    echo -e "${RED}Error: LOG_DIR is undefined. Check s3safe.conf.${NC}"
    exit 1
fi

#Set log file
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/s3safe-$TIMESTAMP.log"

# Define component names
COMPONENT_WWW_TEXT=""
COMPONENT_DB_TEXT=""
COMPONENT_DB_USERS_TEXT=""
if [ "$COMPONENT_WWW" = "on" ]; then
    COMPONENT_WWW_TEXT="WWW"
fi
if [ "$COMPONENT_DB" = "on" ]; then
    COMPONENT_DB_TEXT="DB"
fi
if [ "$COMPONENT_DB_USERS" = "on" ]; then
    COMPONENT_DB_USERS_TEXT="DB Users"
fi
if [ -z "$COMPONENT_WWW_TEXT" ] && [ -z "$COMPONENT_DB_TEXT" ] && [ -z "$COMPONENT_DB_USERS_TEXT" ]; then
    echo -e "${RED}No backup components enabled in s3safe.conf. Exiting.${NC}"
    exit 0
fi

# Build log string from enabled components
COMPONENTS=""
COMMA=""
if [ -n "$COMPONENT_WWW_TEXT" ]; then
    COMPONENTS="$COMPONENT_WWW_TEXT"
    COMMA=", "
fi
if [ -n "$COMPONENT_DB_TEXT" ]; then
    COMPONENTS="${COMPONENTS}${COMMA}${COMPONENT_DB_TEXT}"
    COMMA=", "
fi
if [ -n "$COMPONENT_DB_USERS_TEXT" ]; then
    if [ -n "$COMPONENTS" ]; then
        COMPONENTS="${COMPONENTS} and ${COMPONENT_DB_USERS_TEXT}"
    else
        COMPONENTS="$COMPONENT_DB_USERS_TEXT"
    fi
fi
echo "Backup of $COMPONENTS started at: $TIMESTAMP" | tee "$LOG_FILE"

# Debug to log file
if [ "${DEBUG}" = "on" ]; then
    set -x
    if ! exec 2>>"$LOG_FILE"; then
        echo -e "${RED}Error: Cannot redirect stderr to $LOG_FILE. Check permissions.${NC}"
        exit 1
    fi
fi

# Function to send notification and exit
send_notification_and_exit() {
    if [ "$TELEGRAM_NOTIFICATIONS" = "on" ]; then
        MSG=""
        if [ ${#FAILED_WEBSITES[@]} -gt 0 ] || [ ${#FAILED_DBS[@]} -gt 0 ] || [ $DB_USERS_FAILURES -gt 0 ]; then
            read -r -d '' MSG <<EOT
<b>Backup Failure Notice!</b>
EOT
            MSG+=$'\n\n'
            
            if [ ${#FAILED_WEBSITES[@]} -gt 0 ]; then
                read -r -d '' MSG_WEBSITES <<EOT
$COMPONENT_WWW_TEXT failed to back up on $SERVER @ $TIMESTAMP:

$(for SITE_NAME in "${FAILED_WEBSITES[@]}"; do
    FAIL_REASON="${WEB_FAIL_REASONS[$SITE_NAME]:-backup failed}"
    echo "$SITE_NAME (Reason: $FAIL_REASON)"
done)

<b>Total of ${#FAILED_WEBSITES[@]} websites failed.</b>
EOT
                MSG+="$MSG_WEBSITES"
            fi
            
            if [ ${#FAILED_DBS[@]} -gt 0 ]; then
                if [ ${#FAILED_WEBSITES[@]} -gt 0 ]; then
                    MSG+=$'\n\n'
                fi
                read -r -d '' MSG_DBS <<EOT
$COMPONENT_DB_TEXT failed to back up on $SERVER @ $TIMESTAMP:

$(for DB in "${FAILED_DBS[@]}"; do
    FAIL_REASON="${DB_FAIL_REASONS[$DB]:-backup failed}"
    echo "$DB (Reason: $FAIL_REASON)"
done)

<b>Total of ${#FAILED_DBS[@]} databases failed.</b>
EOT
                MSG+="$MSG_DBS"
            fi
            DEBUG_SKIP_S3
            if [ $DB_USERS_FAILURES -gt 0 ]; then
                if [ ${#FAILED_WEBSITES[@]} -gt 0 ] || [ ${#FAILED_DBS[@]} -gt 0 ]; then
                    MSG+=$'\n\n'
                fi
                FAIL_REASON="${FAILED_DB_USERS_REASON:-backup failed}"
                read -r -d '' MSG_DB_USERS <<EOT
$COMPONENT_DB_USERS_TEXT failed to back up on $SERVER @ $TIMESTAMP:

Global (Reason: $FAIL_REASON)

<b>Total of 1 db-users backup failed.</b>
EOT
                MSG+="$MSG_DB_USERS"
            fi
        fi
        
        if [ -n "$MSG" ]; then
            { curl -s --data chat_id="$TELEGRAM_CHAT_ID" \
                --data-urlencode "text=$MSG" \
                "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage?parse_mode=HTML" >/dev/null; } 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "Notification sent successfully" >> "$LOG_FILE"
            else
                echo "Failed to send notification" >> "$LOG_FILE"
            fi
        fi
    fi
    echo "Backup completed at: $TIMESTAMP" | tee -a "$LOG_FILE"
    exit 1
}

# Initialize failure counters and arrays
WEB_FAILURES=0
DB_FAILURES=0
DB_USERS_FAILURES=0
declare -A WEB_FAIL_REASONS
declare -A DB_FAIL_REASONS
FAILED_WEBSITES=()
FAILED_DBS=()
FAILED_DB_USERS_REASON=""

# Set default WWWROOT if unset
[ -z "$WWWROOT" ] && WWWROOT="/var/www"

# Backup Websites
if [ "$COMPONENT_WWW" = "on" ]; then
    # Create snapshot of www root
    mkdir -p "$SNAP_DIR"
    [ "$DEBUG" = "on" ] && echo "Creating snapshot of $WWWROOT"
    rsync -a "$WWWROOT/" "$SNAP_DIR" >> "$LOG_FILE" 2>&1
    for SITE in "$WWWROOT"/*; do
        if [ -d "$SITE" ]; then
            SITE_NAME=$(basename "$SITE")
            echo "Backing up website: $SITE_NAME" >> "$LOG_FILE"
            [ "$DEBUG" = "on" ] && echo "Backing up website: $SITE_NAME"
            RETRIES=2
            SUCCESS=1
            for ((i=0; i<=RETRIES; i++)); do
                [ "$DEBUG" = "on" ] && echo "Attempt $((i+1)) for website $SITE_NAME" >> "$LOG_FILE"
                [ "$DEBUG" = "on" ] && echo "Attempt $((i+1)) for website $SITE_NAME"
                if [ "$DEBUG" = "on" ]; then
                    if [ "$DEBUG_VERBOSE" = "on" ]; then
                        tar -cvzf "$BACKUP_DIR/www-$SITE_NAME.tar.gz" --warning=no-file-changed -C "$SNAP_DIR" "$SITE_NAME" 2>&1 | tee -a "$LOG_FILE"
                        if [ ${PIPESTATUS[0]} -eq 0 ]; then
                            echo "Compressed website: $SITE_NAME" >> "$LOG_FILE"
                            echo "Compressed website: $SITE_NAME"
                        else
                            echo "Website backup failed: $SITE_NAME" >> "$LOG_FILE"
                            echo "Website backup failed: $SITE_NAME"
                            WEB_FAIL_REASONS[$SITE_NAME]="Website backup failed"
                            SUCCESS=0
                        fi
                    else
                        tar -cvzf "$BACKUP_DIR/www-$SITE_NAME.tar.gz" --warning=no-file-changed -C "$SNAP_DIR" "$SITE_NAME" 2>/dev/null
                        if [ $? -eq 0 ]; then
                            echo "Compressed website: $SITE_NAME" >> "$LOG_FILE"
                            echo "Compressed website: $SITE_NAME"
                        else
                            echo "Website backup failed: $SITE_NAME" >> "$LOG_FILE"
                            echo "Website backup failed: $SITE_NAME"
                            WEB_FAIL_REASONS[$SITE_NAME]="Website backup failed"
                            SUCCESS=0
                        fi
                    fi
                else
                    tar -czf "$BACKUP_DIR/www-$SITE_NAME.tar.gz" --warning=no-file-changed -C "$SNAP_DIR" "$SITE_NAME" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "Compressed website: $SITE_NAME" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Compressed website: $SITE_NAME"
                    else
                        echo "Website backup failed: $SITE_NAME" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Website backup failed: $SITE_NAME"
                        WEB_FAIL_REASONS[$SITE_NAME]="Website backup failed"
                        SUCCESS=0
                    fi
                fi
                if [ $SUCCESS -eq 1 ]; then
                    if gpg --batch --encrypt --recipient "$GPG_RECIPIENT" --trust-model always "$BACKUP_DIR/www-$SITE_NAME.tar.gz"; then
                        [ "$DEBUG" = "on" ] && echo "Encrypted website: $SITE_NAME"
                        if [ "$DEBUG_SKIP_S3" = "on" ]; then
                            echo "S3 upload skipped for: $SITE_NAME (DEBUG_SKIP_S3=on)" >> "$LOG_FILE"
                            [ "$DEBUG" = "on" ] && echo "S3 upload skipped for: $SITE_NAME (DEBUG_SKIP_S3=on)"
                        elif { set +x; aws s3 cp "$BACKUP_DIR/www-$SITE_NAME.tar.gz.gpg" "s3://$S3_BUCKET/www/$SITE_NAME/$TIMESTAMP/www-$SITE_NAME.tar.gz.gpg" --endpoint-url "$S3_ENDPOINT" --checksum-algorithm CRC32 >/dev/null 2>&1; set -x; }; then
                            echo "Website uploaded: $SITE_NAME" >> "$LOG_FILE"
                            [ "$DEBUG" = "on" ] && echo "Uploaded website: $SITE_NAME"
                        else
                            [ "$DEBUG" = "on" ] && echo "Upload failed: $SITE_NAME" >> "$LOG_FILE"
                            [ "$DEBUG" = "on" ] && echo "Upload failed: $SITE_NAME"
                            WEB_FAIL_REASONS[$SITE_NAME]="Upload failed"
                            SUCCESS=0
                        fi
                        rm "$BACKUP_DIR/www-$SITE_NAME.tar.gz" "$BACKUP_DIR/www-$SITE_NAME.tar.gz.gpg"
                        echo "Website backed up: $SITE_NAME" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Website backed up: $SITE_NAME"
                        SUCCESS=1
                        break
                    else
                        [ "$DEBUG" = "on" ] && echo "Encryption failed: $SITE_NAME" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Encryption failed: $SITE_NAME"
                        WEB_FAIL_REASONS[$SITE_NAME]="Encryption failed"
                        SUCCESS=0
                    fi
                fi
                if [ $SUCCESS -eq 0 ] && [ $i -lt $RETRIES ]; then
                    [ "$DEBUG" = "on" ] && echo "Retrying website $SITE_NAME in 10 seconds" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "Retrying website $SITE_NAME in 10 seconds"
                    sleep 10
                fi
            done
            if [ $SUCCESS -eq 0 ]; then
                [ "$DEBUG" = "on" ] && echo "All retries failed for website $SITE_NAME" >> "$LOG_FILE"
                [ "$DEBUG" = "on" ] && echo "All retries failed for website $SITE_NAME"
                WEB_FAILURES=$((WEB_FAILURES + 1))
                FAILED_WEBSITES+=("$SITE_NAME")
            fi
        fi
    done
    # Clean up snapshot
    [ "$DEBUG" = "on" ] && echo "Cleaning up snapshot"
    rm -rf "$SNAP_DIR" >> "$LOG_FILE" 2>&1
fi

# Backup Databases
if [ "$COMPONENT_DB" = "on" ]; then
    DBS=$(mariadb -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|mysql|performance_schema|sys|phpmyadmin)")
    for DB in $DBS; do
        echo "Backing up database: $DB" >> "$LOG_FILE"
        [ "$DEBUG" = "on" ] && echo "Backing up database: $DB"
        RETRIES=2
        SUCCESS=1
        for ((i=0; i<=RETRIES; i++)); do
            [ "$DEBUG" = "on" ] && echo "Attempt $((i+1)) for database $DB" >> "$LOG_FILE"
            [ "$DEBUG" = "on" ] && echo "Attempt $((i+1)) for database $DB"
            if mariadb-dump --databases "$DB" > "$BACKUP_DIR/db-$DB.sql"; then
                [ "$DEBUG" = "on" ] && echo "Dumped database: $DB"
                if [ "$DEBUG" = "on" ]; then
                    if [ "$DEBUG_VERBOSE" = "on" ]; then
                        if (cd "$BACKUP_DIR" && tar -cvzf "db-$DB.tar.gz" --warning=no-file-changed "db-$DB.sql" | tee -a "$LOG_FILE"); then
                            echo "Compressed database: $DB" >> "$LOG_FILE"
                            echo "Compressed database: $DB"
                        else
                            echo "Compression failed: $DB" >> "$LOG_FILE"
                            echo "Compression failed: $DB"
                            DB_FAIL_REASONS[$DB]="Compression failed"
                            SUCCESS=0
                        fi
                    else
                        if (cd "$BACKUP_DIR" && tar -cvzf "db-$DB.tar.gz" --warning=no-file-changed "db-$DB.sql"); then
                            echo "Compressed database: $DB" >> "$LOG_FILE"
                            echo "Compressed database: $DB"
                        else
                            echo "Compression failed: $DB" >> "$LOG_FILE"
                            echo "Compression failed: $DB"
                            DB_FAIL_REASONS[$DB]="Compression failed"
                            SUCCESS=0
                        fi
                    fi
                else
                    if (cd "$BACKUP_DIR" && tar -czf "db-$DB.tar.gz" --warning=no-file-changed "db-$DB.sql"); then
                        echo "Compressed database: $DB" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Compressed database: $DB"
                    else
                        echo "Compression failed: $DB" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Compression failed: $DB"
                        DB_FAIL_REASONS[$DB]="Compression failed"
                        SUCCESS=0
                    fi
                fi
                rm "$BACKUP_DIR/db-$DB.sql"
                if gpg --batch --encrypt --recipient "$GPG_RECIPIENT" --trust-model always "$BACKUP_DIR/db-$DB.tar.gz"; then
                    [ "$DEBUG" = "on" ] && echo "Encrypted database: $DB"
                    if [ "$DEBUG_SKIP_S3" = "on" ]; then
                        echo "S3 upload skipped for: $DB (DEBUG_SKIP_S3=on)" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "S3 upload skipped for: $DB (DEBUG_SKIP_S3=on)"
                    elif { set +x; aws s3 cp "$BACKUP_DIR/db-$DB.tar.gz.gpg" "s3://$S3_BUCKET/db/$DB/$TIMESTAMP/db-$DB.tar.gz.gpg" --endpoint-url "$S3_ENDPOINT" --checksum-algorithm CRC32 >/dev/null 2>&1; set -x; }; then
                        echo "Database uploaded: $DB" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Uploaded database: $DB"
                    else
                        [ "$DEBUG" = "on" ] && echo "Upload failed: $DB" >> "$LOG_FILE"
                        [ "$DEBUG" = "on" ] && echo "Upload failed: $DB"
                        DB_FAIL_REASONS[$DB]="Upload failed"
                        SUCCESS=0
                    fi
                    rm "$BACKUP_DIR/db-$DB.tar.gz" "$BACKUP_DIR/db-$DB.tar.gz.gpg"
                    echo "Database backed up: $DB" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "Database backed up: $DB"
                    SUCCESS=1
                    break
                else
                    [ "$DEBUG" = "on" ] && echo "Encryption failed: $DB" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "Encryption failed: $DB"
                    DB_FAIL_REASONS[$DB]="Encryption failed"
                    SUCCESS=0
                fi
            else
                [ "$DEBUG" = "on" ] && echo "Database dump failed: $DB" >> "$LOG_FILE"
                [ "$DEBUG" = "on" ] && echo "Database dump failed: $DB"
                DB_FAIL_REASONS[$DB]="Database dump failed"
                SUCCESS=0
            fi
            if [ $SUCCESS -eq 0 ] && [ $i -lt $RETRIES ]; then
                [ "$DEBUG" = "on" ] && echo "Retrying database $DB in 10 seconds" >> "$LOG_FILE"
                [ "$DEBUG" = "on" ] && echo "Retrying database $DB in 10 seconds"
                sleep 10
            fi
        done
        if [ $SUCCESS -eq 0 ]; then
            [ "$DEBUG" = "on" ] && echo "All retries failed for database $DB" >> "$LOG_FILE"
            [ "$DEBUG" = "on" ] && echo "All retries failed for database $DB"
            DB_FAILURES=$((DB_FAILURES + 1))
            FAILED_DBS+=("$DB")
        fi
    done
fi

# Backup DB Users
if [ "$COMPONENT_DB_USERS" = "on" ]; then
    echo "Backing up database users" >> "$LOG_FILE"
    [ "$DEBUG" = "on" ] && echo "Backing up database users"
    RETRIES=2
    SUCCESS=1
    for ((i=0; i<=RETRIES; i++)); do
        [ "$DEBUG" = "on" ] && echo "Attempt $((i+1)) for db-users" >> "$LOG_FILE"
        [ "$DEBUG" = "on" ] && echo "Attempt $((i+1)) for db-users"
        if mariadb -e "SELECT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') FROM mysql.user WHERE user NOT IN ('root', 'mysql.sys', 'mysql.session');" | tail -n +2 | while read -r grant; do
            mariadb -e "$grant" >> "$BACKUP_DIR/db-users.sql"
        done; then
            [ "$DEBUG" = "on" ] && echo "Dumped database users"
            if [ "$DEBUG" = "on" ]; then
                if [ "$DEBUG_VERBOSE" = "on" ]; then
                    if (cd "$BACKUP_DIR" && tar -cvzf "db-users.tar.gz" --warning=no-file-changed "db-users.sql" | tee -a "$LOG_FILE"); then
                        echo "Compressed database users" >> "$LOG_FILE"
                        echo "Compressed database users"
                    else
                        echo "Compression failed: db-users" >> "$LOG_FILE"
                        echo "Compression failed: db-users"
                        FAILED_DB_USERS_REASON="Compression failed"
                        SUCCESS=0
                    fi
                else
                    if (cd "$BACKUP_DIR" && tar -cvzf "db-users.tar.gz" --warning=no-file-changed "db-users.sql"); then
                        echo "Compressed database users" >> "$LOG_FILE"
                        echo "Compressed database users"
                    else
                        echo "Compression failed: db-users" >> "$LOG_FILE"
                        echo "Compression failed: db-users"
                        FAILED_DB_USERS_REASON="Compression failed"
                        SUCCESS=0
                    fi
                fi
            else
                if (cd "$BACKUP_DIR" && tar -czf "db-users.tar.gz" --warning=no-file-changed "db-users.sql"); then
                    echo "Compressed database users" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "Compressed database users"
                else
                    echo "Compression failed: db-users" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "Compression failed: db-users"
                    FAILED_DB_USERS_REASON="Compression failed"
                    SUCCESS=0
                fi
            fi
            rm "$BACKUP_DIR/db-users.sql"
            if gpg --batch --encrypt --recipient "$GPG_RECIPIENT" --trust-model always "$BACKUP_DIR/db-users.tar.gz"; then
                [ "$DEBUG" = "on" ] && echo "Encrypted database users"
                if [ "$DEBUG_SKIP_S3" = "on" ]; then
                    echo "S3 upload skipped for: db-users (DEBUG_SKIP_S3=on)" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "S3 upload skipped: for db-users (DEBUG_SKIP_S3=on)"
                elif { set +x; aws s3 cp "$BACKUP_DIR/db-users.tar.gz.gpg" "s3://$S3_BUCKET/db-users/global/$TIMESTAMP/db-users.tar.gz.gpg" --endpoint-url "$S3_ENDPOINT" --checksum-algorithm CRC32 >/dev/null 2>&1; set -x; }; then
                    echo "Database users uploaded" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "Uploaded database users"
                else
                    [ "$DEBUG" = "on" ] && echo "Upload failed: db-users" >> "$LOG_FILE"
                    [ "$DEBUG" = "on" ] && echo "Upload failed: db-users"
                    FAILED_DB_USERS_REASON="Upload failed"
                    SUCCESS=0
                fi
                rm "$BACKUP_DIR/db-users.tar.gz" "$BACKUP_DIR/db-users.tar.gz.gpg"
                echo "Database users backed up" >> "$LOG_FILE"
                [ "$DEBUG" = "on" ] && echo "Database users backed up"
                SUCCESS=1
                break
            else
                [ "$DEBUG" = "on" ] && echo "Encryption failed: db-users" >> "$LOG_FILE"
                [ "$DEBUG" = "on" ] && echo "Encryption failed: db-users"
                FAILED_DB_USERS_REASON="Encryption failed"
                SUCCESS=0
            fi
        else
            [ "$DEBUG" = "on" ] && echo "Database users dump failed" >> "$LOG_FILE"
            [ "$DEBUG" = "on" ] && echo "Database users dump failed"
            FAILED_DB_USERS_REASON="Database users dump failed"
            SUCCESS=0
        fi
        if [ $SUCCESS -eq 0 ] && [ $i -lt $RETRIES ]; then
            [ "$DEBUG" = "on" ] && echo "Retrying db-users in 10 seconds" >> "$LOG_FILE"
            [ "$DEBUG" = "on" ] && echo "Retrying db-users in 10 seconds"
            sleep 10
        fi
    done
    if [ $SUCCESS -eq 0 ]; then
        [ "$DEBUG" = "on" ] && echo "All retries failed for db-users" >> "$LOG_FILE"
        [ "$DEBUG" = "on" ] && echo "All retries failed for db-users"
        DB_USERS_FAILURES=$((DB_USERS_FAILURES + 1))
    fi
fi

# Check for any failures and notify if needed
if [ $WEB_FAILURES -gt 0 ] || [ $DB_FAILURES -gt 0 ] || [ $DB_USERS_FAILURES -gt 0 ]; then
    echo "Failures: $WEB_FAILURES websites, $DB_FAILURES databases, $DB_USERS_FAILURES db-users" | tee -a "$LOG_FILE"
    send_notification_and_exit
fi

echo "Backup completed at: $TIMESTAMP" | tee -a "$LOG_FILE"