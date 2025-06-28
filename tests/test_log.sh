#!/bin/bash
# test_log.sh - Isolates and tests log file creation and output

SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
S3SAFE="$SCRIPT_DIR/s3safe.sh"

export ENV_FILE="$SCRIPT_DIR/.env"
export CONF_FILE="$SCRIPT_DIR/s3safe.conf"

# Setup test environment
export PATH="$SCRIPT_DIR/tests/test_mocks:$PATH"
mkdir -p "$SCRIPT_DIR/tests/test_mocks"

# Mock all commands to succeed
for cmd in tar gpg aws rsync mariadb mariadb-dump; do
    echo '#!/bin/bash' > "$SCRIPT_DIR/tests/test_mocks/$cmd"
    chmod +x "$SCRIPT_DIR/tests/test_mocks/$cmd"
done

# Run main script and discard error output
"$S3SAFE" 2>/dev/null

# Find the latest log file created
LOG_DIR="$HOME/backup/logs"
LOG_FILE=$(ls -t "$LOG_DIR"/s3safe-*.log 2>/dev/null | head -n1)

if [ -n "$LOG_FILE" ] && grep -q "Backup completed at:" "$LOG_FILE"; then
    echo -e "\n✅ Log test passed: Found backup completion message in log."
else
    echo -e "\n❌ Log test failed: Backup completion message not found in log."
fi

echo -e "\nLog output:"
[ -n "$LOG_FILE" ] && cat "$LOG_FILE"

# Cleanup mocks only (not logs)
rm -rf "$SCRIPT_DIR/tests/test_mocks"