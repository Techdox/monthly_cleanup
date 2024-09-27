#!/bin/bash

# Define a log file to record the actions
LOGFILE="/var/log/monthly_cleanup.log"

# Function to log actions
log_action() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [--upgrade]"
    echo "--upgrade   Optionally upgrade system packages."
}

# Parse the input arguments
UPGRADE_SYSTEM=0
for arg in "$@"; do
    case $arg in
        --upgrade)
            UPGRADE_SYSTEM=1
            shift
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
done

log_action "Starting monthly server cleanup."

# 1. Remove unnecessary packages
log_action "Removing unused packages..."
apt-get autoremove -y | tee -a "$LOGFILE"
apt-get autoclean -y | tee -a "$LOGFILE"

# 2. Clean up APT cache
log_action "Cleaning APT cache..."
apt-get clean | tee -a "$LOGFILE"

# 3. Rotate and remove old logs
log_action "Rotating and cleaning up old logs..."
logrotate --force /etc/logrotate.conf | tee -a "$LOGFILE"

# Remove old archived logs older than 30 days
find /var/log -type f -name "*.gz" -mtime +30 -exec rm -f {} \; | tee -a "$LOGFILE"
find /var/log -type f -name "*.log" -mtime +30 -exec rm -f {} \; | tee -a "$LOGFILE"

# 4. Clear systemd journal logs older than 30 days
log_action "Cleaning systemd journal logs older than 30 days..."
journalctl --vacuum-time=30d | tee -a "$LOGFILE"

# 5. Remove old temporary files
log_action "Cleaning temporary files..."
find /tmp -type f -atime +10 -exec rm -f {} \; | tee -a "$LOGFILE"

# 6. Remove Docker dangling images, containers, and volumes (if Docker is installed)
if [ -x "$(command -v docker)" ]; then
    log_action "Cleaning up Docker resources..."
    docker system prune -f | tee -a "$LOGFILE"
    docker volume prune -f | tee -a "$LOGFILE"
else
    log_action "Docker not found, skipping Docker cleanup."
fi

# 7. Optionally check and apply system updates
if [ $UPGRADE_SYSTEM -eq 1 ]; then
    log_action "Checking and applying system updates..."
    apt-get update | tee -a "$LOGFILE"
    apt-get upgrade -y | tee -a "$LOGFILE"
else
    log_action "Skipping system updates as --upgrade flag was not used."
fi

# End cleanup
log_action "Server cleanup completed."

# Exit the script
exit 0
