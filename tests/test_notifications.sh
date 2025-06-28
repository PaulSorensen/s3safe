#!/bin/bash
# test_notifications.sh - Send real notification on simulated backup failure

SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
S3SAFE="$SCRIPT_DIR/s3safe.sh"

export ENV_FILE="$SCRIPT_DIR/.env"
export CONF_FILE="$SCRIPT_DIR/s3safe.conf"

# Setup test environment
export PATH="$SCRIPT_DIR/tests/test_mocks:$PATH"
mkdir -p "$SCRIPT_DIR/tests/test_mocks"

# Mock mariadb-dump to fail (triggers DB backup failure)
echo '#!/bin/bash
exit 1' > "$SCRIPT_DIR/tests/test_mocks/mariadb-dump"
chmod +x "$SCRIPT_DIR/tests/test_mocks/mariadb-dump"

# Mock mariadb to return test database
echo '#!/bin/bash
if [[ "$*" == *"SHOW DATABASES"* ]]; then
    echo -e "Database\ntest_db"
fi' > "$SCRIPT_DIR/tests/test_mocks/mariadb"
chmod +x "$SCRIPT_DIR/tests/test_mocks/mariadb"

# Mock other commands to succeed
for cmd in tar gpg aws rsync; do
    echo '#!/bin/bash' > "$SCRIPT_DIR/tests/test_mocks/$cmd"
    chmod +x "$SCRIPT_DIR/tests/test_mocks/$cmd"
done

echo "Testing notifications..."
echo "This will send a real notification!"

# Run main script and discard error output
"$S3SAFE" 2>/dev/null

if [ $? -eq 1 ]; then
    echo "✅ Test completed - check your notifications!"
else
    echo "❌ Test failed - no notification sent (script exited with success)"
fi

# Cleanup
rm -rf "$SCRIPT_DIR/tests/test_mocks"