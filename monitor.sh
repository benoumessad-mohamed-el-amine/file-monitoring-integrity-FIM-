#!/bin/bash

# File Monitor Script with User Identification
# Author: Benoumessad Mohamed El Amine
# Purpose: Monitor file changes and identify users performing operations

set -euo pipefail  # Enable strict error handling

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
# Function to check and install required tools
install_dependencies() {
    local packages=(inotify-tools auditd libnotify-bin lsof)
    local missing=()
    local installer=""
    local update_cmd=""
    local install_cmd=""

    echo -e "${BLUE}Checking dependencies...${NC}"

    # Detect the OS type
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|kali)
                installer="apt"
                update_cmd="apt update"
                install_cmd="apt install -y"
                ;;
            arch)
                installer="pacman"
                update_cmd="pacman -Sy"
                install_cmd="pacman -S --noconfirm"
                packages=(inotify-tools audit libnotify lsof)
                ;;
            fedora)
                installer="dnf"
                update_cmd="dnf check-update"
                install_cmd="dnf install -y"
                ;;
            centos|rhel)
                installer="yum"
                update_cmd="yum check-update"
                install_cmd="yum install -y"
                ;;
            opensuse*|suse|sles)
                installer="zypper"
                update_cmd="zypper refresh"
                install_cmd="zypper install -y"
                packages=(inotify-tools audit libnotify lsof)  # Adjust names if needed
                ;;
            *)
                echo -e "${RED}Unsupported distribution: $ID${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${RED}Cannot detect operating system.${NC}"
        exit 1
    fi

    # Check for missing packages
    for pkg in "${packages[@]}"; do
        case "$installer" in
            apt)
                dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
                ;;
            pacman)
                pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
                ;;
            dnf|yum|zypper)
                rpm -q "$pkg" &>/dev/null || missing+=("$pkg")
                ;;
        esac
    done

    # Install if missing
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "${GREEN}All dependencies are already installed.${NC}"
    else
        echo -e "${YELLOW}Missing packages: ${missing[*]}${NC}"
        echo -e "${YELLOW}Installing missing dependencies using $installer...${NC}"
        eval "$update_cmd"
        eval "$install_cmd ${missing[*]}"

        # Check if install command failed
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Error: Failed to install required packages.${NC}"
            echo -e "${RED}Unresolved problem: Please install the following packages manually:${NC}"
            echo -e "${RED}${missing[*]}${NC}"
            exit 1
        fi
    fi
}


# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}   

# Must run script as root for audit access
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root to access audit logs${NC}"
    echo "Usage: sudo $0 [directory_to_monitor]"
    exit 1
fi

# ✅ Install dependencies now (while we know we're root)
install_dependencies

# Setup for notifications in GUI
export DISPLAY=:0
REAL_USER=$(who | head -n1 | awk '{print $1}')
REAL_USER_ID=$(id -u "$REAL_USER" 2>/dev/null || echo "1000")

# Set up D-Bus for notifications
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${REAL_USER_ID}/bus"

# Test notification system
if command -v notify-send >/dev/null 2>&1; then
    sudo -u "$REAL_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" notify-send "File Monitor" "Monitoring system initialized" 2>/dev/null || true
fi

# Determine directory to monitor
if [ $# -eq 0 ]; then
    WATCH_DIR=$(pwd)
    echo -e "${GREEN}Monitoring current directory: $WATCH_DIR${NC}"
else
    if [[ -d "$1" ]]; then
        WATCH_DIR=$(realpath "$1")
        echo -e "${GREEN}Monitoring specified directory: $WATCH_DIR${NC}"
    else
        echo -e "${RED}Error: Directory '$1' doesn't exist!${NC}"
        exit 1
    fi
fi

# Configuration
HASH_FILE="$WATCH_DIR/.file_monitor_hashes.sha256"
LOG_FILE="$WATCH_DIR/file_monitor.log"
AUDIT_LOG="/var/log/audit/audit.log"
declare -A LAST_ALERT

# Ensure audit system is running
if ! systemctl is-active --quiet auditd; then
    echo -e "${YELLOW}Warning: auditd service is not running. Starting it...${NC}"
    systemctl start auditd || {
        echo -e "${RED}Error: Could not start auditd service${NC}"
        exit 1
    }
fi

# Set up audit rules for the monitored directory
setup_audit_rules() {
    local watch_path="$1"
    # Remove any existing watch rule for this path and key
    auditctl -W "$watch_path" -p wa -k filewatch 2>/dev/null || true
    # Add the new rule
    auditctl -w "$watch_path" -p wa -k filewatch
    log_message "INFO" "Audit rule refreshed for: $watch_path"
}

# Function to get detailed user information
get_user_info() {
    local filepath="$1"
    local event_type="$2"
    local user_info=""
    
    # Get file owner information
    if [[ -f "$filepath" ]]; then
        local file_owner=$(stat -c "%U" "$filepath" 2>/dev/null || echo "unknown")
        local file_group=$(stat -c "%G" "$filepath" 2>/dev/null || echo "unknown")
        user_info="File Owner: $file_owner:$file_group"
    fi
    
    # Try to get audit information for recent activity
    local audit_info=""
    local current_time=$(date +%s)
    local search_time=$((current_time - 10))  # Look back 10 seconds
    local search_date=$(date -d "@$search_time" "+%m/%d/%Y %H:%M:%S")
    
    # Search audit logs for recent file access
    if [[ -r "$AUDIT_LOG" ]]; then
        audit_info=$(ausearch -ts "$search_date" -k filewatch 2>/dev/null | \
                    grep -E "(type=SYSCALL|type=PATH)" | \
                    grep -A5 -B5 "$(basename "$filepath")" | \
                    head -20 || true)
        
        if [[ -n "$audit_info" ]]; then
            # Extract user ID and process information
            local uid=$(echo "$audit_info" | grep -E "uid=[0-9]+" | head -1 | sed -E 's/.*uid=([0-9]+).*/\1/' || echo "")
            local pid=$(echo "$audit_info" | grep -E "pid=[0-9]+" | head -1 | sed -E 's/.*pid=([0-9]+).*/\1/' || echo "")
            local comm=$(echo "$audit_info" | grep -E "comm=" | head -1 | sed -E 's/.*comm="([^"]+)".*/\1/' || echo "")
            
            if [[ -n "$uid" ]]; then
                local username=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1 || echo "uid:$uid")
                user_info="$user_info | Action by: $username"
                [[ -n "$comm" ]] && user_info="$user_info (process: $comm)"
                [[ -n "$pid" ]] && user_info="$user_info [PID: $pid]"
            fi
        fi
    fi
    
    # Fallback: check currently logged in users and recent process activity
    if [[ -z "$audit_info" ]]; then
        local logged_users=$(who | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
        user_info="$user_info | Logged users: $logged_users"
        
        # Check recent file access using lsof (if available)
        if command -v lsof >/dev/null 2>&1 && [[ -f "$filepath" ]]; then
            local lsof_info=$(lsof "$filepath" 2>/dev/null | tail -n +2 | head -3 || true)
            if [[ -n "$lsof_info" ]]; then
                local lsof_user=$(echo "$lsof_info" | awk '{print $3}' | head -1)
                user_info="$user_info | Recent access by: $lsof_user"
            fi
        fi
    fi
    
    echo "$user_info"
}

# Function to send notification
send_notification() {
    local title="$1"
    local message="$2"
    local icon="$3"
    
    if command -v notify-send >/dev/null 2>&1; then
        sudo -u "$REAL_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
            notify-send --icon="$icon" --urgency=normal --expire-time=5000 "$title" "$message" 2>/dev/null || true
    fi
}

# Function to remove duplicate entries from hash file
remove_duplicate_files() {
    if [[ -f "$HASH_FILE" ]]; then
        local tmpfile
        tmpfile=$(mktemp --tmpdir hashfile.XXXXXX)
        sort "$HASH_FILE" | awk '!seen[$1]++' > "$tmpfile"
        mv "$tmpfile" "$HASH_FILE"
    fi
}

# Initialize monitoring
initialize_monitoring() {
    echo
    echo -e "\e[1;32m========================================\e[0m"
    echo -e "\e[1;34m   🛡️  File Integrity Monitor Started   \e[0m"
    echo -e "\e[1;32m========================================\e[0m"
    echo -e "\e[1;33mMonitoring directory: $WATCH_DIR\e[0m"
    echo

    # Ensure log file exists and set permissions (visible)
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 600 "$LOG_FILE"
        echo "# File Integrity Monitor Log" > "$LOG_FILE"
        echo "# Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
        echo "# Directory: $WATCH_DIR" >> "$LOG_FILE"
        echo >> "$LOG_FILE"
    else
        chmod 600 "$LOG_FILE"
    fi

    # Ensure hash file exists and set permissions (hidden)
    if [[ -f "$HASH_FILE" ]]; then
        chmod 600 "$HASH_FILE"
    fi

    cd "$WATCH_DIR" || exit 1
    
    # Setup audit rules
    setup_audit_rules "$WATCH_DIR"
    
    # Generate initial hash baseline if not present
    if [[ ! -f "$HASH_FILE" ]]; then
        echo -e "${BLUE}Creating initial hash baseline...${NC}"
        find . -type f -name "*.txt" -exec sha256sum {} + > "$HASH_FILE" 2>/dev/null || true
        log_message "INIT" "Baseline created with $(wc -l < "$HASH_FILE") files"
        remove_duplicate_files
    else
        log_message "INIT" "Using existing baseline with $(wc -l < "$HASH_FILE") files"
    fi
    
    log_message "MONITOR" "File monitoring started"
    echo -e "${GREEN}File monitoring active. Press Ctrl+C to stop.${NC}"
}

# Cleanup function
cleanup() {
    
    echo
    echo -e "\e[1;33m========================================\e[0m"
    echo -e "\e[1;32m   🚦 File Integrity Monitor Stopped   \e[0m"
    echo -e "\e[1;33m========================================\e[0m"
    echo -e "\e[1;34mAll monitoring stopped and cleanup completed.\e[0m"
    #removing audit rules
    auditctl -d -W "$WATCH_DIR" 2>/dev/null || true
    echo -e "\e[1;36mThank you for using fim-monitor! Stay secure. 🛡️\e[0m"
    echo 
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Initialize monitoring
initialize_monitoring

# Main monitoring loop
inotifywait -m -r -e create -e modify -e delete -e move \
    --exclude '(^|/)\.|~$|\.tmp$' \
    --format '%T|%e|%w%f' \
    --timefmt '%Y-%m-%d %H:%M:%S' \
    "$WATCH_DIR" 2>/dev/null |
while IFS='|' read -r TIMESTAMP EVENT FILEPATH; do
    
    # Only monitor .txt files
    [[ "$FILEPATH" != *.txt ]] && continue
    
    # Skip hidden files and monitoring files
    [[ "$(basename "$FILEPATH")" == .file_monitor* ]] && continue
    
    REL_PATH=".${FILEPATH#$WATCH_DIR}"
    MODIFIED=false
    
    log_message "EVENT" "$EVENT detected: $REL_PATH"
    
    case "$EVENT" in
        *DELETE*)
            log_message "DELETE" "File deleted: $REL_PATH"
            sed -i "\| $REL_PATH\$|d" "$HASH_FILE" 2>/dev/null || true
            
            USER_INFO=$(get_user_info "$FILEPATH" "DELETE")
            NOTIFICATION_MSG="File: $REL_PATH"$'\n'"$USER_INFO"
            send_notification "🗑️ File Deleted" "$NOTIFICATION_MSG" "dialog-warning"
            ;;
            
        *CREATE*)
            if [[ -f "$FILEPATH" ]]; then
                HASH=$(sha256sum "$FILEPATH" 2>/dev/null | awk '{print $1}' || echo "error")
                if [[ "$HASH" != "error" ]]; then
                    echo "$HASH  $REL_PATH" >> "$HASH_FILE"
                    MODIFIED=true
                    
                    USER_INFO=$(get_user_info "$FILEPATH" "CREATE")
                    log_message "CREATE" "File created: $REL_PATH | $USER_INFO"
                    
                    NOTIFICATION_MSG="File: $REL_PATH"$'\n'"$USER_INFO"
                    send_notification "📄 File Created" "$NOTIFICATION_MSG" "dialog-information"
                fi
            fi
            ;;
            
        *MODIFY*)
            if [[ -f "$FILEPATH" ]]; then
                NEW_HASH=$(sha256sum "$FILEPATH" 2>/dev/null | awk '{print $1}' || echo "error")
                OLD_HASH=$(grep " $REL_PATH\$" "$HASH_FILE" 2>/dev/null | awk '{print $1}' || echo "")
                
                if [[ "$NEW_HASH" != "error" && "$NEW_HASH" != "$OLD_HASH" ]]; then
                    # Rate limiting for notifications
                    NOW=$(date +%s)
                    LAST=${LAST_ALERT["$REL_PATH"]:-0}
                    
                    if (( NOW - LAST >= 5 )); then
                        USER_INFO=$(get_user_info "$FILEPATH" "MODIFY")
                        log_message "MODIFY" "File modified: $REL_PATH | $USER_INFO"
                        
                        NOTIFICATION_MSG="File: $REL_PATH"$'\n'"$USER_INFO"
                        send_notification "✏️ File Modified" "$NOTIFICATION_MSG" "dialog-information"
                        
                        LAST_ALERT["$REL_PATH"]=$NOW
                    fi
                    
                    # Update hash
                    sed -i "\| $REL_PATH\$|d" "$HASH_FILE" 2>/dev/null || true
                    echo "$NEW_HASH  $REL_PATH" >> "$HASH_FILE"
                    MODIFIED=true
                fi
            fi
            ;;
            
        *MOVE*)
            USER_INFO=$(get_user_info "$FILEPATH" "MOVE")
            log_message "MOVE" "File moved: $REL_PATH | $USER_INFO"
            
            NOTIFICATION_MSG="File: $REL_PATH"$'\n'"$USER_INFO"
            send_notification "📦 File Moved" "$NOTIFICATION_MSG" "dialog-information"
            ;;
    esac
    
    # Clean up duplicates if changes occurred
    if [[ "$MODIFIED" == true ]]; then
        remove_duplicate_files
    fi
done
