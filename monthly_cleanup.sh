#!/bin/bash

# Define a log file to record the actions
LOGFILE="/var/log/monthly_cleanup.log"

# Retrieve the system's hostname
HOSTNAME=$(hostname) 

# Function to log actions
log_action() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Function to send a webhook notification with Markdown formatting
send_webhook() {
    local title=$1
    local body=$2
    local url=$3

    # JSON payload with Markdown support
    curl \
    -H "Title: $title" \
    -d "**Hostname**: $HOSTNAME
    $body." \
    -H "Markdown: yes" \
    $url
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [--upgrade] [--send-webhook] [--webhook-url <url>]"
    echo "--upgrade       Optionally upgrade system packages."
    echo "--send-webhook  Send a notification to the webhook endpoint."
    echo "--webhook-url   Specify the URL for the webhook (required if --send-webhook is used)."
}

# Parse the input arguments
UPGRADE_SYSTEM=0
SEND_WEBHOOK=0
WEBHOOK_URL=""

# Iterate through arguments using a loop
while [[ $# -gt 0 ]]; do
    case $1 in
        --upgrade)
            UPGRADE_SYSTEM=1
            shift
            ;;
        --send-webhook)
            SEND_WEBHOOK=1
            shift
            ;;
        --webhook-url)
            WEBHOOK_URL="$2"
            shift 2
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
done

# Check if --send-webhook is used without specifying --webhook-url
if [ $SEND_WEBHOOK -eq 1 ] && [ -z "$WEBHOOK_URL" ]; then
    echo "Error: --send-webhook flag requires --webhook-url to be specified."
    show_usage
    exit 1
fi

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

# Send webhook notification if requested
if [ $SEND_WEBHOOK -eq 1 ]; then
    log_action "Sending notification to webhook: $WEBHOOK_URL"
    send_webhook "Monthly Server Cleanup Report" "The monthly server cleanup has completed successfully. All unnecessary packages, logs, and temporary files have been cleaned up." "$WEBHOOK_URL"
fi

# Exit the script
exit 0
