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

    # Normalize default
    default="${default^^}"

    # Prompt hint
    local hint
    if [[ "$default" == "Y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    while true; do
        read -rp "++=++ ${prompt} ${hint}: " answer
        answer="${answer:-$default}"
        answer="${answer^^}"

        case "$answer" in
            Y|YE|YES)
                return 0
                ;;
            N|NO)
                return 1
                ;;
            *)
                log_error "Invalid input. Please enter yes or no."
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

# =============================================================
#  MIRROR RANKING SECTION
# =============================================================
 
# Global flags (go BEFORE the subcommand)
readonly MIRROR_COUNT=20
readonly MIRROR_CONCURRENCY=8
readonly MIRROR_MAX_JUMPS=5
readonly MIRROR_RETEST_TOP=5
readonly MIRROR_PROTOCOL="https"
 
# Subcommand-specific flags
# --max-delay        : arch, endeavouros, manjaro only
# --sort-mirrors-by  : arch only
# --max-delay is NOT supported by: chaotic-aur, blackarch, cachyos, arcolinux, artix, rebornos, archarm
readonly MIRROR_MAX_DELAY=86400
readonly MIRROR_PER_COUNTRY=3
 
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${ID,,}"
    else
        echo "unknown"
    fi
}
 
# Returns "rate-mirrors-subcommand:/mirrorlist/path" or empty if unsupported
map_distro() {
    case "$1" in
        endeavouros) echo "endeavouros:/etc/pacman.d/endeavouros-mirrorlist" ;;
        cachyos)     echo "cachyos:/etc/pacman.d/cachyos-mirrorlist"         ;;
        manjaro)     echo "manjaro:/etc/pacman.d/mirrorlist"                 ;;
        artix)       echo "artix:/etc/pacman.d/mirrorlist"                   ;;
        arcolinux)   echo "arcolinux:/etc/pacman.d/arcolinux-mirrorlist"     ;;
        rebornos)    echo "rebornos:/etc/pacman.d/mirrorlist"                ;;
        archarm)     echo "archarm:/etc/pacman.d/mirrorlist"                 ;;
        *)           echo ""                                                  ;;
    esac
}
 
# Subcommands that support --max-delay and --country-test-mirrors-per-country
_subcmd_supports_delay() {
    case "$1" in
        arch|endeavouros|manjaro) return 0 ;;
        *) return 1 ;;
    esac
}
 
# Generic rate-mirrors runner for distro subcommands (non-arch)
# Builds the flag set based on what the subcommand actually supports
_rate_mirrors_run() {
    local label="$1" subcmd="$2" out_path="$3"
    local tmpfile
    tmpfile=$(mktemp) || { log_error "[${label}] mktemp failed"; return 1; }
 
    # Build subcommand-specific args
    local subcmd_args=()
    if _subcmd_supports_delay "$subcmd"; then
        subcmd_args+=(
            --max-delay="$MIRROR_MAX_DELAY"
            --country-test-mirrors-per-country="$MIRROR_PER_COUNTRY"
        )
    fi
 
    log_info "[${label}] rate-mirrors ${subcmd} | protocol=${MIRROR_PROTOCOL} concurrency=${MIRROR_CONCURRENCY} max-jumps=${MIRROR_MAX_JUMPS} retest-top=${MIRROR_RETEST_TOP} count=${MIRROR_COUNT}${subcmd_args:+ max-delay=${MIRROR_MAX_DELAY} per-country=${MIRROR_PER_COUNTRY}}"
 
    sudo rate-mirrors \
        --allow-root \
        --save="$tmpfile" \
        --disable-comments-in-file \
        --concurrency="$MIRROR_CONCURRENCY" \
        --max-jumps="$MIRROR_MAX_JUMPS" \
        --top-mirrors-number-to-retest="$MIRROR_RETEST_TOP" \
        --protocol="$MIRROR_PROTOCOL" \
        "$subcmd" \
        "${subcmd_args[@]}" \
        --max-mirrors-to-output="$MIRROR_COUNT" \
        2>&1 \
    || {
        log_error "[${label}] rate-mirrors failed"
        rm -f "$tmpfile"
        return 1
    }
 
    if [[ ! -s "$tmpfile" ]]; then
        log_error "[${label}] rate-mirrors produced empty output"
        rm -f "$tmpfile"
        return 1
    fi
 
    sudo cp "$out_path" "${out_path}.orig" 2>/dev/null || true
    sudo mv "$tmpfile" "$out_path"
    sudo chmod 644 "$out_path"
    log_info "[${label}] Mirrorlist written → ${out_path}"
    return 0
}
 
_rankmirrors_run() {
    local label="$1" src="$2" out_path="$3"
 
    log_info "[${label}] Falling back to rankmirrors …"
 
    local ranked
    ranked=$(sudo rankmirrors -n "$MIRROR_COUNT" "$src" 2>/dev/null) || {
        log_error "[${label}] rankmirrors failed"
        return 1
    }
 
    echo "$ranked" | sudo tee "$out_path" > /dev/null
    sudo chmod 644 "$out_path"
    log_info "[${label}] rankmirrors complete → ${out_path}"
    return 0
}
 
rank_distro_mirrors() {
    local distro="$1"
    local label="${distro^} Mirrors"
 
    local mapping subcmd list_path
    mapping=$(map_distro "$distro")
 
    if [[ -z "$mapping" ]]; then
        log_info "[${label}] No dedicated subcommand for '${distro}'"
        return 0
    fi
 
    subcmd="${mapping%%:*}"
    list_path="${mapping##*:}"
 
    # Tier 1: distro-native tools
    case "$distro" in
        endeavouros)
            if command -v eos-rankmirrors &>/dev/null; then
                log_info "[${label}] Using eos-rankmirrors …"
                sudo cp "$list_path" "${list_path}.orig" 2>/dev/null || true
                if sudo eos-rankmirrors; then
                    return 0
                fi
                log_error "[${label}] eos-rankmirrors failed – falling through"
            fi
            ;;
        cachyos)
            if command -v cachyos-rate-mirrors &>/dev/null; then
                log_info "[${label}] Using cachyos-rate-mirrors …"
                sudo cp "$list_path" "${list_path}.orig" 2>/dev/null || true
                if sudo cachyos-rate-mirrors; then
                    return 0
                fi
                log_error "[${label}] cachyos-rate-mirrors failed – falling through"
            fi
            ;;
    esac
 
    # Tier 2: rate-mirrors
    if command -v rate-mirrors &>/dev/null; then
        [[ -f "$list_path" ]] || { log_error "[${label}] Mirrorlist not found: ${list_path}"; return 1; }
        if _rate_mirrors_run "$label" "$subcmd" "$list_path"; then
            return 0
        fi
        log_error "[${label}] rate-mirrors failed – falling through"
    else
        log_info "[${label}] rate-mirrors not found"
    fi
 
    # Tier 3: rankmirrors
    if command -v rankmirrors &>/dev/null; then
        local orig="${list_path}.orig"
        [[ -f "$orig" ]] || sudo cp "$list_path" "$orig" 2>/dev/null || true
        if _rankmirrors_run "$label" "$orig" "$list_path"; then
            return 0
        fi
    else
        log_info "[${label}] rankmirrors not found"
    fi
 
    log_error "[${label}] All ranking methods failed – mirrorlist unchanged"
    return 1
}
 
rank_arch_mirrors() {
    local label="Arch Mirrors"
    local list_path="/etc/pacman.d/mirrorlist"
    local tmpfile
 
    # Tier 1: rate-mirrors
    # arch subcommand supports: --max-delay, --sort-mirrors-by, --country-test-mirrors-per-country
    # --sort-mirrors-by=score_asc: health-filtered before speed
    if command -v rate-mirrors &>/dev/null; then
        tmpfile=$(mktemp) || { log_error "[${label}] mktemp failed"; return 1; }
 
        log_info "[${label}] rate-mirrors arch | protocol=${MIRROR_PROTOCOL} concurrency=${MIRROR_CONCURRENCY} max-jumps=${MIRROR_MAX_JUMPS} retest-top=${MIRROR_RETEST_TOP} count=${MIRROR_COUNT} max-delay=${MIRROR_MAX_DELAY} per-country=${MIRROR_PER_COUNTRY} sort=score_asc"
 
        sudo rate-mirrors \
            --allow-root \
            --save="$tmpfile" \
            --disable-comments-in-file \
            --concurrency="$MIRROR_CONCURRENCY" \
            --max-jumps="$MIRROR_MAX_JUMPS" \
            --top-mirrors-number-to-retest="$MIRROR_RETEST_TOP" \
            --protocol="$MIRROR_PROTOCOL" \
            arch \
            --max-delay="$MIRROR_MAX_DELAY" \
            --sort-mirrors-by=score_asc \
            --country-test-mirrors-per-country="$MIRROR_PER_COUNTRY" \
            --max-mirrors-to-output="$MIRROR_COUNT" \
            2>&1 \
        && [[ -s "$tmpfile" ]] && {
            sudo cp "$list_path" "${list_path}.orig" 2>/dev/null || true
            sudo mv "$tmpfile" "$list_path"
            sudo chmod 644 "$list_path"
            log_info "[${label}] Mirrorlist written → ${list_path}"
            return 0
        }
 
        log_error "[${label}] rate-mirrors failed – falling through"
        rm -f "$tmpfile"
    else
        log_info "[${label}] rate-mirrors not found"
    fi
 
    # Tier 2: rankmirrors
    if command -v rankmirrors &>/dev/null; then
        local orig="${list_path}.orig"
        [[ -f "$orig" ]] || sudo cp "$list_path" "$orig" 2>/dev/null || true
        if _rankmirrors_run "$label" "$orig" "$list_path"; then
            return 0
        fi
    else
        log_info "[${label}] rankmirrors not found"
    fi
 
    log_error "[${label}] All ranking methods failed – mirrorlist unchanged"
    return 1
}
 
rank_optional_repos() {
    log_header "Optional Repository Mirrors"
 
    # chaotic-aur and blackarch have minimal subcommand options — no --max-delay support
    declare -A OPTIONAL_REPOS=(
        ["Chaotic-AUR"]="chaotic-aur:/etc/pacman.d/chaotic-mirrorlist"
        ["BlackArch"]="blackarch:/etc/pacman.d/blackarch-mirrorlist"
    )
 
    local name mapping subcmd list_path orig
    for name in "${!OPTIONAL_REPOS[@]}"; do
        mapping="${OPTIONAL_REPOS[$name]}"
        subcmd="${mapping%%:*}"
        list_path="${mapping##*:}"
 
        [[ -f "$list_path" ]] || continue
 
        if ! ask_yes_no "Rank ${name} mirrors?" "N"; then
            log_info "Skipped ${name}"
            continue
        fi
 
        # Tier 1: rate-mirrors
        if command -v rate-mirrors &>/dev/null; then
            if _rate_mirrors_run "${name} Mirrors" "$subcmd" "$list_path"; then
                continue
            fi
            log_error "[${name}] rate-mirrors failed – trying rankmirrors"
        else
            log_info "[${name}] rate-mirrors not found"
        fi
 
        # Tier 2: rankmirrors
        if command -v rankmirrors &>/dev/null; then
            orig="${list_path}.orig"
            [[ -f "$orig" ]] || sudo cp "$list_path" "$orig" 2>/dev/null || true
            _rankmirrors_run "${name} Mirrors" "$orig" "$list_path" || \
                log_error "[${name}] rankmirrors also failed – mirrorlist unchanged"
        else
            log_error "[${name}] No ranking tool available – mirrorlist unchanged"
        fi
    done
}
 
mirrorlist() {
    log_header "Update System Mirrors"
 
    local distro
    distro=$(detect_distro)
    log_info "Detected distro: ${distro}"
 
    # Step 1: distro-specific mirrors
    case "$distro" in
        arch)
            log_info "Plain Arch – no extra distro mirrorlist to rank"
            ;;
        *)
            local mapping
            mapping=$(map_distro "$distro")
            if [[ -n "$mapping" ]]; then
                if ask_yes_no "Rank ${distro^} mirrors?" "N"; then
                    rank_distro_mirrors "$distro"
                else
                    log_info "Skipped ${distro^} mirrors"
                fi
            else
                log_info "No distro-specific mirrorlist entry for: ${distro}"
            fi
            ;;
    esac
 
    # Step 2: base Arch mirrorlist
    if ask_yes_no "Rank Arch mirrors?" "N"; then
        rank_arch_mirrors
    else
        log_info "Skipped Arch mirrors"
    fi
 
    # Step 3: optional repos
    rank_optional_repos
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
    sudo pacman -Syy || true

    log_info "Performing full system upgrade..."
    sudo pacman -Su || true

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
        sudo pacman -Sc || true
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
    timeout 300 yay -Su 2>&1 || true

    if ask_yes_no "Clean yay cache?" "N"; then
        log_info "Cleaning yay cache..."
        yay -Sc 2>&1 || true
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
# Yazi UPDATE FUNCTIONS
#============================================================

update_yazi() {
    log_header "Update yazi packages"

    if ! ask_yes_no "Update Yazi" "N"; then
        log_info "Yazi update skipped."
        return 0
    fi
    zsh -ic "ya pkg upgrade" || true

    zsh -ic "yazi --debug" || true
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

    if command -v zsh&>/dev/null; then
        update_shell
    fi

    if command -v yazi &>/dev/null; then
        update_yazi
    fi

    final
}

#============================================================
# SCRIPT EXECUTION
#============================================================

main
exit $?
