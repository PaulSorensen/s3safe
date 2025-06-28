# S3Safe

[![Badge](https://img.shields.io/badge/License-MIT-97CA00)](/LICENSE)
[![Badge](https://img.shields.io/badge/-Buy%20Me%20a%20Coffee-dab728?logo=buymeacoffee&logoColor=white)](https://buymeacoffee.com/paulsorensen)

**S3Safe** is a robust Bash script for backing up websites, databases, and database users to any S3-compatible storage (e.g., AWS S3, Cloudflare R2, Google Cloud Storage, Infomaniak Swiss Backup) using AWS CLI. It compresses, encrypts backups with GPG, and uploads them securely. Features include retry logic for reliability, notifications for failures, and flexible configuration for components (WWW, DB, DB users). Logs provide detailed tracking, with optional debugging modes.

## Features

- Backs up websites, MariaDB/MySQL databases, and database users.
- Supports any S3-compatible storage via AWS CLI.
- Compresses and encrypts backups with GPG for security.
- Configurable backup components (enable/disable WWW, DB, DB users).
- Retry logic for compression, encryption and S3 uploads for websites, databases and database users, and database dumps.
- Supports multiple notification methods for failures (can be disabled for custom monitoring, e.g., Zabbix):
  - [ntfy](https://ntfy.sh)
  - Telegram Bot
  - Webhook
- Customizable backup, snapshot, and log directories.
- Debugging modes for detailed logging and S3 upload skipping.
- Logs all operations for monitoring and troubleshooting.

## S3 Storage Structure

```bash
s3://<bucket>/
├── www/<site_name>/<timestamp>/www-<site_name>.tar.gz.gpg
├── db/<database_name>/<timestamp>/db-<database_name>.tar.gz.gpg
└── db-users/global/<timestamp>/db-users.tar.gz.gpg
```

## Requirements

Before running the script, ensure:

- Linux environment with Bash.
- MariaDB or MySQL (script supports both).
- AWS CLI installed and configured.
- GPG for encryption.
- `curl` for notifications (if enabled).
- `rsync` and `tar` for file operations.

## Installation

1. **Install Dependencies**:

   ```bash
   sudo apt update
   sudo apt install mariadb-client awscli gnupg curl rsync tar
   ```

2. **Configure AWS CLI**:

   Install AWS CLI if not already installed:

   ```bash
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

   Configure credentials for your S3-compatible storage:

   ```bash
   aws configure
   ```

   Set your access key, secret key, region (if applicable), and output format.

3. **Set Up GPG Encryption**:

   - Generate or obtain a GPG key pair (public/private).

   - Import the public key on the backup server:

     ```bash
     gpg --import public_key.asc
     ```

   - **Security Note**: GPG encryption ensures backups are secure. Store the private key safely and never expose it. Verify the public key is correctly imported to avoid encryption failures.

4. **Configure MariaDB/MySQL Credentials**:

   - Create a `~/.my.cnf` file for passwordless access:

     ```bash
     nano ~/.my.cnf
     ```

   - Add:

     ```bash
     [client]
     user=<your_db_user>
     password=<your_db_password>
     ```

   - Secure the file:

     ```bash
     chmod 600 ~/.my.cnf
     ```

## Configuration

1. **Copy Configuration Files**:

   ```bash
   cp .env.example .env
   cp s3safe.conf.example s3safe.conf
   ```

   - Secure `.env`

   ```bash
   chmod 600 .env     
   ```

2. **Edit .env**:

   Update the following:

   - `S3_BUCKET`: Your S3 bucket name.
   - `S3_ENDPOINT`: Your S3-compatible endpoint URL.
   - `GPG_RECIPIENT`: GPG key ID or email for encryption.
   - `NTFY_TOPIC`: ntfy topic (optional)
   - `TELEGRAM_BOT_TOKEN`: Telegram bot token (optional).
   - `TELEGRAM_CHAT_ID`: Telegram chat ID (optional).
   - `WEBHOOK_URL`: Webhook URL (optional).
   - **Note**: Notifications are enabled by default in `s3safe.conf` (disable if not using), and all notification methods set in .env will be used.

3. **Edit s3safe.conf**:

   **Server Name:**

- Set `SERVER` to your server's name (e.g., MyServer).
  
   **Components:**

- Enable/disable components to back up:
  
  - `COMPONENT_WWW=on` (backs up websites).
  
  - `COMPONENT_DB=on` (backs up databases).
  
  - `COMPONENT_DB_USERS=on` (backs up database users).

    **Notifications:**

- Set `NOTIFICATIONS=off` to disable notifications and monitor logs manually (e.g., via Zabbix), or leave it on to receive notifications.
  
   **WWW Root:**

- Set `WWWROOT` to your web root (e.g., `/var/www`). Defaults to `/var/www` if unset. The script backs up all directories in this path.
  
   **Directories:**

- `BACKUP_DIR`: Temporary storage (default: `$HOME/backup`).

- `SNAP_DIR`: Snapshot directory (default: `$BACKUP_DIR/snap/www`).

- `LOG_DIR`: Log storage (default: `$BACKUP_DIR/logs`).
  
   **Debugging:**

- `DEBUG=on`: Enables detailed logging to console and log file.

- `DEBUG_VERBOSE=on`: Logs exceptions and file lists (requires `DEBUG=on`).

- `DEBUG_SKIP_S3=on`: Skips S3 uploads for testing.

4. **Test the Script**

   Run manually to verify configuration:

   ```bash
   chmod +x s3safe.sh
   ./s3safe.sh
   ```

   Check logs in `LOG_DIR` for errors before scheduling.

## Example Output

With `DEBUG=off`, backing up domain.com, database domain_com and database users:

```bash
Backup of WWW, DB and DB Users started at: 20250628_234510
Backing up website: domain.com
Compressed website: domain.com
Website uploaded: domain.com
Website backed up: domain.com

Backing up database: domain_com
Compressed database: domain_com
Uploaded database: domain_com
Database backed up: domain_com

Backing up database users
Compressed database users
Database users uploaded
Database users backed up

Backup completed at: 20250628_235010
```

## Scheduling

Schedule daily backups at 01:00:

```bash
crontab -e
```

Add:

```bash
0 01 * * * /path/to/s3safe.sh
```

## Additional Notes

- Backup Retention: Configure lifecycle rules on your S3-compatible storage to manage backup retention (e.g., retain last 14 days).
- Log Management: Logs are stored in `LOG_DIR`. Set up `logrotate` to manage log files.
- Error Handling: The script retries failed operations (compression, encryption and S3 uploads for websites, databases and database users, and database dumps) up to 2 times (3 times total). Enable notifications for failure alerts or monitor logs through custom software or manually.
- Security: Ensure `~/.my.cnf` and `.env` permissions are restricted (`chmod 600`). Verify GPG keys are correctly set up to prevent encryption errors.

## Author

**Paul Sørensen**  
[https://paulsorensen.io](https://paulsorensen.io)  
[https://github.com/paulsorensen](https://github.com/paulsorensen)

## Support

If you found this project useful, a small tip is appreciated ❤️  
[https://buymeacoffee.com/paulsorensen](https://buymeacoffee.com/paulsorensen)

## License

This project is licensed under the MIT License.  
See [LICENSE](LICENSE) for details.
