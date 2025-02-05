#!/bin/bash
# ==============================================================================
# Script Name:       rsync-pull-codeigniter.sh
# Description:       High-performance, robust Rsync pull for CodeIgniter websites,
#                    optimized for execution from either staging or production servers.
#                    Includes database and file synchronization.
# Compatibility:     Linux (Debian/Ubuntu) running CloudPanel & CodeIgniter
# Requirements:      CloudPanel, ssh-keygen
# Author:            WP Speed Expert
# Author URI:        https://wpspeedexpert.com
# Version:           1.0.0
# GitHub:            https://github.com/WPSpeedExpert/cloudpanel-codeigniter-sync
# GitHub Branch:     main
# Primary Branch:    main
# ==============================================================================
#
# Usage Instructions:
# 1. Make the script executable:
#    chmod +x rsync-pull-codeigniter.sh
#
# 2. Update the variables in Part 1 of the script:
#    - Set source environment details (server you're pulling FROM)
#    - Set destination environment details (server you're pulling TO)
#    - Update SSH settings if needed
#
# 3. Run the script:
#    ./rsync-pull-codeigniter.sh
#
# Example crontab schedule:
#    0 0 * * * /home/user/rsync-pull-codeigniter.sh
#
# ==============================================================================
# Part 1: Initial Setup and Variables
# ==============================================================================

# 1.1: Source Environment (Production)
source_domainName=""                        # Domain name for the source environment
source_siteUser=""                         # User associated with the source environment
source_databaseName="${source_siteUser}"   # Database name for the source environment
source_databaseUserName="${source_siteUser}" # Database user name for the source environment
source_websitePath="/home/${source_siteUser}/htdocs/${source_domainName}" # Path to source website files
source_scriptPath="/home/${source_siteUser}" # Path to source scripts and configuration files

# 1.2: Destination Environment
destination_domainName=""                   # Domain name for the destination environment
destination_siteUser=""                    # User associated with the destination environment
destination_databaseName="${destination_siteUser}"  # Database name for the destination environment
destination_databaseUserName="${destination_siteUser}" # Database user name for the destination environment
destination_databaseUserPassword=""         # Database user password for the destination environment (needed if recreate_database=true)
destination_websitePath="/home/${destination_siteUser}/htdocs/${destination_domainName}" # Path to destination website files
destination_scriptPath="/home/${destination_siteUser}" # Path to destination scripts and configuration files

# 1.3: Remote Server Settings
remote_server_ssh="root@0.0.0.0"          # Remote server SSH connection string
remote_server_port="22"                    # SSH port number

# 1.4: Database Settings
backup_destination_database=false          # Set to true to backup destination database before import
recreate_database=true                    # Set to true to recreate database instead of just dropping tables
mysql_restart_method="stop_start"           # Options: "restart", "stop_start", "none"

# 1.5: General Settings
timezone="Europe/Dublin"                    # Timezone for logging
LogFile="${destination_scriptPath}/rsync-pull-codeigniter.log" # Log file location

# Log the start time with the correct timezone
start_time=$(TZ=$timezone date)

# ==============================================================================
# Part 2: Pre-execution Checks
# ==============================================================================

# Check if password is set when database recreation is enabled
if [ "$recreate_database" = true ] && [ -z "${destination_databaseUserPassword}" ]; then
    echo "[+] ERROR: Database password not set in variables (required when recreate_database=true)" 2>&1 | tee -a ${LogFile}
    exit 1
fi

# Check SSH Connection
echo "[+] Checking SSH connection to remote server: ${remote_server_ssh}" 2>&1 | tee -a ${LogFile}
if ssh -p ${remote_server_port} -o BatchMode=yes -o ConnectTimeout=5 ${remote_server_ssh} 'true' 2>&1 | tee -a ${LogFile}; then
    echo "[+] SSH connection to remote server established." 2>&1 | tee -a ${LogFile}
else
    echo "[+] ERROR: SSH connection to remote server failed. Aborting!" 2>&1 | tee -a ${LogFile}
    exit 1
fi

# ==============================================================================
# Part 3: Database Export and Sync
# ==============================================================================

# Export the source database
echo "[+] Exporting the source database: ${source_databaseName}" 2>&1 | tee -a ${LogFile}
ssh -p ${remote_server_port} ${remote_server_ssh} "clpctl db:export --databaseName=${source_databaseName} --file=${source_scriptPath}/tmp/${source_databaseName}.sql.gz" 2>&1 | tee -a ${LogFile}

# Sync the database file
echo "[+] Syncing the database file" 2>&1 | tee -a ${LogFile}
rsync -azP -e "ssh -p ${remote_server_port}" \
    ${remote_server_ssh}:${source_scriptPath}/tmp/${source_databaseName}.sql.gz \
    ${destination_scriptPath}/tmp/ 2>&1 | tee -a ${LogFile}

# Clean up remote export
ssh -p ${remote_server_port} ${remote_server_ssh} "rm ${source_scriptPath}/tmp/${source_databaseName}.sql.gz" 2>&1 | tee -a ${LogFile}

# Backup destination database if enabled
if [ "$backup_destination_database" = true ]; then
    echo "[+] Creating backup of destination database" 2>&1 | tee -a ${LogFile}
    backup_file="${destination_scriptPath}/tmp/${destination_databaseName}-backup-$(date +%F).sql.gz"
    clpctl db:export --databaseName=${destination_databaseName} --file=${backup_file} 2>&1 | tee -a ${LogFile}
fi

# ==============================================================================
# Part 4: Database Import
# ==============================================================================

# Handle database recreation or table dropping
if [ "$recreate_database" = true ]; then
    echo "[+] Recreating destination database" 2>&1 | tee -a ${LogFile}
    clpctl db:delete --databaseName=${destination_databaseName} --force 2>&1 | tee -a ${LogFile}
    clpctl db:add --domainName=${destination_domainName} \
                  --databaseName=${destination_databaseName} \
                  --databaseUserName=${destination_databaseUserName} \
                  --databaseUserPassword="${destination_databaseUserPassword}" 2>&1 | tee -a ${LogFile}
else
    echo "[+] Dropping all tables from destination database" 2>&1 | tee -a ${LogFile}
    # Drop tables using CloudPanel CLI
    clpctl db:delete --databaseName=${destination_databaseName} --force 2>&1 | tee -a ${LogFile}
    clpctl db:add --domainName=${destination_domainName} \
                  --databaseName=${destination_databaseName} \
                  --databaseUserName=${destination_databaseUserName} \
                  --databaseUserPassword="${destination_databaseUserPassword}" 2>&1 | tee -a ${LogFile}
    done
fi

# Import the database
echo "[+] Importing database to destination" 2>&1 | tee -a ${LogFile}
clpctl db:import --databaseName=${destination_databaseName} --file=${destination_scriptPath}/tmp/${source_databaseName}.sql.gz 2>&1 | tee -a ${LogFile}

# Clean up the imported database file
rm ${destination_scriptPath}/tmp/${source_databaseName}.sql.gz 2>&1 | tee -a ${LogFile}

# ==============================================================================
# Part 5: File Sync
# ==============================================================================

# Rsync the files
echo "[+] Starting Rsync pull from source to destination..." 2>&1 | tee -a ${LogFile}

rsync -azP -e "ssh -p ${remote_server_port}" \
    --exclude 'application/cache/' \
    --exclude 'application/logs/' \
    --exclude 'application/config/database.php' \
    --exclude 'application/config/config.php' \
    --exclude '.env' \
    ${remote_server_ssh}:${source_websitePath}/ ${destination_websitePath}/ 2>&1 | tee -a ${LogFile}

if [ $? -ne 0 ]; then
    echo "[+] ERROR: Rsync failed. Aborting!" 2>&1 | tee -a ${LogFile}
    exit 1
fi

# ==============================================================================
# Part 6: Set Permissions
# ==============================================================================

echo "[+] Setting correct file permissions..." 2>&1 | tee -a ${LogFile}

# Set ownership
chown -R ${destination_siteUser}:${destination_siteUser} ${destination_websitePath}

# Set directory permissions
find ${destination_websitePath} -type d -exec chmod 755 {} \;

# Set file permissions
find ${destination_websitePath} -type f -exec chmod 644 {} \;

# Make specific directories writable
chmod -R 775 ${destination_websitePath}/application/cache
chmod -R 775 ${destination_websitePath}/application/logs
chmod -R 775 ${destination_websitePath}/application/sessions

# ==============================================================================
# Part 7: MySQL Restart (if configured)
# ==============================================================================

case "$mysql_restart_method" in
    "restart")
        echo "[+] Restarting MySQL server" 2>&1 | tee -a ${LogFile}
        systemctl restart mysql
        ;;
    "stop_start")
        echo "[+] Stopping and starting MySQL server" 2>&1 | tee -a ${LogFile}
        systemctl stop mysql
        systemctl start mysql
        ;;
    "none")
        echo "[+] Skipping MySQL restart" 2>&1 | tee -a ${LogFile}
        ;;
esac

# ==============================================================================
# Part 8: Completion
# ==============================================================================

# Log completion
end_time=$(TZ=$timezone date)
echo "[+] Sync completed successfully at ${end_time}" 2>&1 | tee -a ${LogFile}

exit 0
