#!/bin/bash

#============================================================
# SYSTEM UPGRADE SCRIPT FOR ARCH/ENDEAVOUROS
# Converted from Python to Bash
#============================================================

set -o pipefail

# Error handling
trap 'log_error "Script interrupted"; exit 130' SIGINT SIGTERM
trap 'log_error "Script error at line $LINENO"; exit 1' ERR

#============================================================
# LOGGING FUNCTIONS
#============================================================

log_info() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "++=++ [INFO] ${timestamp} ++=++ ${message}"
    sleep 0.2
}

log_error() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "++=++ [ERROR] ${timestamp} ++=++ : ${message}" >&2
    sleep 1
}

log_header() {
    local message="$1"
    printf "\n========== \t %s \t ==========\n\n" "$message"
}

#============================================================
# UTILITY FUNCTIONS
#============================================================

ask_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local answer
    
    while true; do
        read -rp "++=++ ${prompt} (${default}): " answer
        answer="${answer:-$default}"
        
        # Convert to uppercase for comparison
        answer="${answer^^}"
        
        # Match Y, YE, YES for yes; N, NO for no
        case "$answer" in
            Y|YE|YES)
                return 0
                ;;
            N|NO)
                return 1
                ;;
            *)
                log_error "Invalid input. Please enter Y, Yes, or No"
                ;;
        esac
    done
}

show_disk_space() {
    local label="$1"
    log_info "${label}:"
    local output used available percent
    
    if ! output=$(df -h / 2>/dev/null | tail -1); then
        log_error "Failed to get disk space information"
        return 1
    fi
    
    used=$(echo "$output" | awk '{print $3}')
    available=$(echo "$output" | awk '{print $4}')
    percent=$(echo "$output" | awk '{print $5}')
    
    printf "  Used: %s / Available: %s (%s used)\n" "$used" "$available" "$percent"
    return 0
}

#============================================================
# MIRROR FUNCTIONS
#============================================================

rank_arch_mirrors() {
    local name="Arch Mirrors"
    local num_mirrors=15
    
    local orig_path="/etc/pacman.d/mirrorlist.orig"
    local pacnew_path="/etc/pacman.d/mirrorlist.pacnew"
    
    # Cleanup old files
    sudo rm -f "$orig_path" "$pacnew_path" 2>/dev/null
    
    local url="https://archlinux.org/mirrorlist/all/https/"
    
    log_info "[${name}] Downloading Arch mirrorlist…"
    
    local data
    data=$(curl -s -L --max-time 20 --user-agent "ArchMirrorRanker" "$url") || {
        log_error "Failed to download mirrorlist"
        return 1
    }
    
    # Extract and write servers
    local servers=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^#?Server ]]; then
            servers+=("${line#\#}")
        fi
    done <<< "$data"
    
    sudo tee "$orig_path" > /dev/null <<< "$(IFS=$'\n'; echo "${servers[*]}")" || {
        log_error "Failed to write mirrorlist"
        return 1
    }
    sudo chmod 644 "$orig_path"
    log_info "[${name}] Downloaded ${#servers[@]} mirror URLs"
    
    # Check for rankmirrors
    if ! command -v rankmirrors &>/dev/null; then
        log_error "rankmirrors is not installed (pacman-contrib missing)"
        return 1
    fi
    
    log_info "[${name}] Running rankmirrors -n ${num_mirrors}…"
    
    local ranked_output
    ranked_output=$(sudo rankmirrors -n "$num_mirrors" "$orig_path" 2>/dev/null) || {
        log_error "rankmirrors failed"
        return 1
    }
    
    # Write final ranked output
    echo "$ranked_output" | sudo tee "$pacnew_path" > /dev/null
    sudo chmod 644 "$pacnew_path"
    
    local mirror_count
    mirror_count=$(echo "$ranked_output" | grep -c "^Server")
    log_info "[${name}] Ranked and saved ${mirror_count} mirrors to ${pacnew_path}"
    
    return 0
}

rank_eos_mirrors() {
    local name="EndeavourOS Mirrors"
    
    log_info "[${name}] Running eos-rankmirrors…"
    
    # Check for eos-rankmirrors
    if ! command -v eos-rankmirrors &>/dev/null; then
        log_error "eos-rankmirrors is not installed"
        return 1
    fi
    
    sudo eos-rankmirrors || {
        log_error "eos-rankmirrors failed"
        return 1
    }
    
    log_info "[${name}] Mirror ranking complete"
    return 0
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

mirrorlist() {
    log_header "Update System Mirrors"
    
    local distro
    distro=$(detect_distro)
    
    if [[ "$distro" == "endeavouros" ]]; then
        if ! ask_yes_no "Rank EndeavourOS mirrors?" "N"; then
            log_info "Mirror ranking skipped."
            return 0
        fi
        rank_eos_mirrors
    elif [[ "$distro" == "arch" ]]; then
        if ! ask_yes_no "Rank Arch mirrors?" "N"; then
            log_info "Mirror ranking skipped."
            return 0
        fi
        rank_arch_mirrors
    else
        log_info "Unknown distro or mirrors not supported"
        return 0
    fi
}

#============================================================
# FIRMWARE UPDATE FUNCTION
#============================================================

update_firmware() {
    log_header "Firmware Update"
    
    if ! ask_yes_no "Check for firmware updates?" "N"; then
        log_info "Firmware check skipped."
        return 0
    fi
    
    log_info "Getting firmware update info"
    sudo fwupdmgr get-updates || true
}

#============================================================
# PACKAGE MANAGER FUNCTIONS
#============================================================

update_pacman() {
    log_header "Pacman Update"
    
    if ! ask_yes_no "Update pacman?" "N"; then
        log_info "Pacman update skipped."
        return 0
    fi
    
    log_info "Updating pacman database..."
    sudo pacman -Sy --noconfirm || true
    
    log_info "Performing full system upgrade..."
    sudo pacman -Su --noconfirm || true
    
    log_info "Checking for orphaned packages..."
    local orphans
    orphans=$(pacman -Qdtq 2>/dev/null) || true
    if [[ -n "$orphans" ]]; then
        log_info "Found orphaned packages, removing..."
        # Use printf to safely pass orphans as separate arguments
        printf '%s\n' "$orphans" | xargs -r sudo pacman -Rs --noconfirm 2>/dev/null || true
    else
        log_info "No orphaned packages found"
    fi
    
    if ask_yes_no "Clean pacman cache?" "Y"; then
        log_info "Cleaning pacman cache..."
        sudo pacman -Sc --noconfirm || true
    fi
}

update_aur() {
    log_header "AUR Update (yay)"
    
    if ! command -v yay &>/dev/null; then
        log_info "yay not found, skipping AUR update"
        return 0
    fi
    
    if ! ask_yes_no "Update AUR packages with yay?" "N"; then
        log_info "AUR update skipped."
        return 0
    fi
    
    log_info "Updating AUR packages..."
    timeout 300 yay -Su --noconfirm 2>&1 || true
    
    if ask_yes_no "Clean yay cache?" "N"; then
        log_info "Cleaning yay cache..."
        yay -Sc --noconfirm 2>&1 || true
    fi
}

#============================================================
# FLATPAK FUNCTION
#============================================================

update_flatpak() {
    log_header "Flatpak Update"
    
    if ! ask_yes_no "Update Flatpak?" "N"; then
        log_info "Flatpak update skipped."
        return 0
    fi
    
    log_info "Updating Flatpak packages..."
    flatpak update -y || true
    
    if ask_yes_no "Remove unused Flatpak runtimes?" "N"; then
        log_info "Removing unused Flatpak runtimes..."
        flatpak uninstall --unused -y || true
    fi
    
    # Check flatpak checksums and remove .removed flatpaks
    if ask_yes_no "Verify flatpak checksums and remove .removed data?" "N"; then
        log_info "Repairing flatpak installation (checking checksums)..."
        flatpak repair || true
        log_info "Flatpak repair complete"
    fi
}

#============================================================
# SHELL UPDATE FUNCTIONS
#============================================================

update_shell() {
    log_header "Update zsh shell"
    
    if ! ask_yes_no "Update Zinit" "N"; then
        log_info "Zinit update skipped."
        return 0
    fi
    zsh -ic "zinit self-update" || true
    
    if ask_yes_no "Update zinit plugins" "Y"; then
        zsh -ic "zinit update --all" || true
    fi
    
    zsh -ic "zinit zstatus" || true
}

#============================================================
# LOG CLEANUP FUNCTIONS
#============================================================

logs_journalctl() {
    log_header "Cleaning logs"
    
    # Get log space before
    local log_space_before
    log_space_before=$(df --output=used -B1 / | tail -1) || log_space_before="0"
    log_info "Log space before cleanup: ${log_space_before}"
    
    if ask_yes_no "Vacuum journalctl down?" "N"; then
        log_info "Shrinking journalctl total size, and rotating logs"
        
        sudo journalctl --sync 2>/dev/null || true
        sudo journalctl --flush 2>/dev/null || true
        sudo journalctl --rotate 2>/dev/null || true
        sudo journalctl --vacuum-size=10M 2>/dev/null || true
        
        if command -v logrotate &>/dev/null; then
            log_info "Forcing logrotate"
            sudo logrotate -f /etc/logrotate.conf 2>/dev/null || true
            log_info "Removing rotated log files"
        fi
    else
        log_info "Skipping journalctl vacuum"
    fi
    
    if ask_yes_no "Shorten ACTIVE log files? (Highly invasive)" "N"; then
        log_info "Stopping rsyslog and journald"
        sudo systemctl stop rsyslog 2>/dev/null || true
        sudo systemctl stop systemd-journald 2>/dev/null || true
        
        log_info "Emptying current log files"
        sudo find /var/log -maxdepth 2 -type f -name "*.log" -exec truncate -s 0 {} + 2>/dev/null || true
        
        log_info "Restarting services"
        sudo systemctl start rsyslog 2>/dev/null || true
        sudo systemctl start systemd-journald 2>/dev/null || true
        
        log_info "Removing rotated log files"
        sudo find /var/log -type f -name "*.log.*" -delete 2>/dev/null || true
    else
        log_info "Skipping removal of current log files"
    fi
    
    if ask_yes_no "Clear coredumps?" "N"; then
        log_info "Cleaning coredump files..."
        
        # Detect init system
        local init_system="unknown"
        if command -v systemctl &>/dev/null; then
            init_system="systemd"
        elif command -v sv &>/dev/null; then
            init_system="runit"
        fi
        
        # Stop coredump service if systemd
        if [[ "$init_system" == "systemd" ]]; then
            if sudo systemctl list-units --type=service 2>/dev/null | grep -q systemd-coredump; then
                sudo systemctl stop systemd-coredump.service 2>/dev/null || true
            fi
        fi
        
        # Clean directories
        local dirs_to_clean=(
            "/var/lib/systemd/coredump"
            "/var/crash"
            "/var/dumps"
            "/var/tmp"
            "/tmp"
        )
        
        for dir_path in "${dirs_to_clean[@]}"; do
            if [[ -d "$dir_path" ]]; then
                log_info "Cleaning ${dir_path}..."
                log_info "Contents of ${dir_path}:"
                sudo ls -lah "$dir_path" 2>/dev/null || true
                
                if ask_yes_no "Delete all contents of ${dir_path}?" "N"; then
                    sudo find "$dir_path" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
                    log_info "Cleaned ${dir_path}"
                else
                    log_info "Skipped ${dir_path}"
                fi
            fi
        done
        
        # Restart service if systemd
        if [[ "$init_system" == "systemd" ]]; then
            if sudo systemctl list-units --type=service 2>/dev/null | grep -q systemd-coredump; then
                sudo systemctl start systemd-coredump.service 2>/dev/null || true
            fi
        fi
        
        log_info "Coredump cleanup complete (init system: ${init_system})"
    else
        log_info "Skipping coredump removal"
    fi
    
    # Sync filesystem and wait for it to complete
    log_info "Syncing filesystem..."
    sync
    sleep 2
    
    # Get log space after
    local log_space_after delta before_mb after_mb delta_mb
    log_space_after=$(df --output=used -B1 / | tail -1) || log_space_after="0"
    delta=$((log_space_after - log_space_before))

    before_mb=$((log_space_before / 1024 / 1024))
    after_mb=$((log_space_after / 1024 / 1024))
    delta_mb=$((delta / 1024 / 1024))

    log_info "Disk used before: ${before_mb} MB"
    log_info "Disk used after : ${after_mb} MB"
    log_info "Change          : ${delta_mb} MB"
}

#============================================================
# FINAL FUNCTIONS
#============================================================

final() {
    log_header "Upgrade Summary"
    show_disk_space "Final disk space"
    log_info "System upgrade complete!"
    
    log_header "Reboot system"
    
    if ! command -v reboot &>/dev/null; then
        log_error "reboot command not found"
    else
        if ask_yes_no "Reboot now?" "N"; then
            log_info "Rebooting system in 10 seconds..."
            sleep 10
            sudo reboot
        fi
    fi
    
    return 0
}

#============================================================
# MAIN ENTRY POINT
#============================================================

main() {
    log_header "Starting Full System Upgrade"
    
    # Validate required commands
    for cmd in sudo curl df awk; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    show_disk_space "Initial disk space"
    
    # Run functions
    if command -v pacman &>/dev/null; then
        mirrorlist
    fi
    
    if command -v fwupdmgr &>/dev/null; then
        update_firmware
    fi
    
    if command -v pacman &>/dev/null; then
        update_pacman
        update_aur
    fi
    
    if command -v flatpak &>/dev/null; then
        update_flatpak
    fi
    
    if command -v journalctl &>/dev/null; then
        logs_journalctl
    fi
    
    if command -v zsh &>/dev/null; then
        update_shell
    fi
    
    final
}

#============================================================
# SCRIPT EXECUTION
#============================================================

main
exit $?
