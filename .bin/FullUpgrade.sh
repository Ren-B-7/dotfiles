#!/usr/bin/env bash

#============================================================
# SYSTEM UPGRADE SCRIPT FOR ARCH/ENDEAVOUROS AND DEBIAN/UBUNTU
# Supports: pacman (+ yay/AUR), apt, flatpak, firmware, shell/yazi
# Converted from Python to Bash
#============================================================

set -o pipefail

# Error handling
# (SIGKILL/SIGSTOP cannot be trapped; SIGTSTP is left alone so Ctrl+Z still works)
# Error handling
SUDO_KEEPALIVE_PID=""

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT
trap 'log_error "Script interrupted (SIGINT)"; exit 130' INT
trap 'log_error "Script terminated (SIGTERM)"; exit 143' TERM

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

# Global flags (go BEFORE the subcommand):
#   --concurrency, --max-jumps, --top-mirrors-number-to-retest,
#   --max-mirrors-to-output, --country-test-mirrors-per-country,
#   --protocol, --save, --disable-comments-in-file
#
# Subcommand-specific flags (go AFTER the subcommand):
#   --max-delay             : arch, endeavouros, manjaro only
#   --sort-mirrors-by       : arch only

readonly MIRROR_COUNT=20
readonly MIRROR_CONCURRENCY=8
readonly MIRROR_MAX_JUMPS=5
readonly MIRROR_RETEST_TOP=5
readonly MIRROR_PER_COUNTRY=3
readonly MIRROR_PROTOCOL="https"
readonly MIRROR_MAX_DELAY=86400

# Keep a pristine ".orig" (created once, never overwritten) and a rolling
# ".bak" (the list as it was before this run).
backup_mirrorlist() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    [[ -f "${path}.orig" ]] || sudo cp -p "$path" "${path}.orig" 2>/dev/null || true
    sudo cp -p "$path" "${path}.bak" 2>/dev/null || true
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # subshell so os-release variables don't leak into this script
        # shellcheck disable=SC1091
        ( . /etc/os-release; echo "${ID,,}" )
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

# Subcommands that support --max-delay
_subcmd_supports_delay() {
    case "$1" in
        arch|endeavouros|manjaro) return 0 ;;
        *) return 1 ;;
    esac
}

_rate_mirrors_run() {
    local label="$1" subcmd="$2" out_path="$3"
    local tmpfile
    tmpfile=$(sudo mktemp) || { log_error "[${label}] mktemp failed"; return 1; }

    # Build subcommand-specific args
    local subcmd_args=()
    if _subcmd_supports_delay "$subcmd"; then
        subcmd_args+=( --max-delay="$MIRROR_MAX_DELAY" )
    fi

    log_info "[${label}] rate-mirrors ${subcmd} | protocol=${MIRROR_PROTOCOL} concurrency=${MIRROR_CONCURRENCY} max-jumps=${MIRROR_MAX_JUMPS} retest-top=${MIRROR_RETEST_TOP} per-country=${MIRROR_PER_COUNTRY} count=${MIRROR_COUNT}${subcmd_args:+ max-delay=${MIRROR_MAX_DELAY}}"

    sudo rate-mirrors \
        --allow-root \
        --save="$tmpfile" \
        --disable-comments-in-file \
        --concurrency="$MIRROR_CONCURRENCY" \
        --max-jumps="$MIRROR_MAX_JUMPS" \
        --top-mirrors-number-to-retest="$MIRROR_RETEST_TOP" \
        --max-mirrors-to-output="$MIRROR_COUNT" \
        --country-test-mirrors-per-country="$MIRROR_PER_COUNTRY" \
        --protocol="$MIRROR_PROTOCOL" \
        "$subcmd" \
        "${subcmd_args[@]}" \
        2>&1 \
        || {
        log_error "[${label}] rate-mirrors failed"
        sudo rm -f "$tmpfile"
        return 1
    }

    if [[ ! -s "$tmpfile" ]]; then
        log_error "[${label}] rate-mirrors produced empty output"
        sudo rm -f "$tmpfile"
        return 1
    fi

    backup_mirrorlist "$out_path"
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
                backup_mirrorlist "$list_path"
                if sudo eos-rankmirrors; then
                    return 0
                fi
                log_error "[${label}] eos-rankmirrors failed – falling through"
            fi
            ;;
        cachyos)
            if command -v cachyos-rate-mirrors &>/dev/null; then
                log_info "[${label}] Using cachyos-rate-mirrors …"
                backup_mirrorlist "$list_path"
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
        backup_mirrorlist "$list_path"
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
    # --sort-mirrors-by=score_asc: health-filtered before speed (arch only)
    if command -v rate-mirrors &>/dev/null; then
        tmpfile=$(sudo mktemp) || { log_error "[${label}] mktemp failed"; return 1; }

        log_info "[${label}] rate-mirrors arch | protocol=${MIRROR_PROTOCOL} concurrency=${MIRROR_CONCURRENCY} max-jumps=${MIRROR_MAX_JUMPS} retest-top=${MIRROR_RETEST_TOP} per-country=${MIRROR_PER_COUNTRY} count=${MIRROR_COUNT} max-delay=${MIRROR_MAX_DELAY} sort=score_asc"

        sudo rate-mirrors \
            --allow-root \
            --save="$tmpfile" \
            --disable-comments-in-file \
            --concurrency="$MIRROR_CONCURRENCY" \
            --max-jumps="$MIRROR_MAX_JUMPS" \
            --top-mirrors-number-to-retest="$MIRROR_RETEST_TOP" \
            --max-mirrors-to-output="$MIRROR_COUNT" \
            --country-test-mirrors-per-country="$MIRROR_PER_COUNTRY" \
            --protocol="$MIRROR_PROTOCOL" \
            arch \
            --max-delay="$MIRROR_MAX_DELAY" \
            --sort-mirrors-by=score_asc \
            2>&1 \
            && [[ -s "$tmpfile" ]] && {
            backup_mirrorlist "$list_path"
            sudo mv "$tmpfile" "$list_path"
            sudo chmod 644 "$list_path"
            log_info "[${label}] Mirrorlist written → ${list_path}"
            return 0
        }

        log_error "[${label}] rate-mirrors failed – falling through"
        sudo rm -f "$tmpfile"
    else
        log_info "[${label}] rate-mirrors not found"
    fi

    # Tier 2: rankmirrors
    if command -v rankmirrors &>/dev/null; then
        local orig="${list_path}.orig"
        backup_mirrorlist "$list_path"
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
            backup_mirrorlist "$list_path"
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

    log_info "Refreshing firmware metadata..."
    sudo fwupdmgr refresh || true

    log_info "Getting firmware update info"
    sudo fwupdmgr get-updates || true

    # get-updates only *lists* updates; nothing is installed unless we ask
    if ask_yes_no "Install available firmware updates?" "N"; then
        sudo fwupdmgr update || true
    fi
}

#============================================================
# PACKAGE MANAGER FUNCTIONS
#============================================================

# Leftover download-XXXXXX dirs from interrupted downloads make `pacman -Sc`
# fail with "could not open file ... Error reading fd".
clean_stale_pacman_downloads() {
    if [[ -e /var/lib/pacman/db.lck ]]; then
        log_error "pacman lock exists (/var/lib/pacman/db.lck) – skipping stale download cleanup"
        return 1
    fi
    log_info "Removing stale partial downloads (download-*)..."
    sudo rm -rf /var/cache/pacman/pkg/download-*
}

update_pacman() {
    log_header "Pacman Update"

    if ! ask_yes_no "Update pacman?" "N"; then
        log_info "Pacman update skipped."
        return 0
    fi

    # Single -Syu: never sync and upgrade in separate steps (partial upgrades)
    log_info "Syncing databases and performing full system upgrade..."
    if ! sudo pacman -Syu; then
        log_error "pacman upgrade failed – skipping orphan removal, cache cleanup and AUR"
        return 1
    fi

    log_info "Checking for orphaned packages..."
    local -a orphans=()
    mapfile -t orphans < <(pacman -Qdtq 2>/dev/null)
    if (( ${#orphans[@]} > 0 )); then
        log_info "Orphans: ${orphans[*]}"
        # pacman shows the full removal list and asks for confirmation itself
        sudo pacman -Rns "${orphans[@]}" || log_error "Orphan removal failed or was declined"
    else
        log_info "No orphaned packages found"
    fi

    if ask_yes_no "Clean pacman cache?" "Y"; then
        log_info "Cleaning pacman cache..."
        clean_stale_pacman_downloads || true
        sudo pacman -Sc || true
    fi
    return 0
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

    # -Sua = AUR only (repo packages are handled by update_pacman, so no
    # partial-upgrade risk). VCS packages (-git etc.) only update with --devel.
    local -a yay_args=(-Sua)
    if ask_yes_no "Also check VCS packages (-git/-svn, --devel)?" "N"; then
        yay_args+=(--devel)
    fi

    # No `timeout` here: it kills builds mid-way and breaks interactive prompts
    log_info "Updating AUR packages..."
    yay "${yay_args[@]}" || log_error "yay finished with errors"

    if ask_yes_no "Clean yay cache?" "N"; then
        log_info "Cleaning yay cache..."
        clean_stale_pacman_downloads || true
        yay -Sc || true
    fi
    return 0
}

#============================================================
# APT FUNCTIONS (Debian / Ubuntu / Mint / Pop!_OS / ...)
#============================================================

# Returns 0 if another apt/dpkg process currently holds the dpkg lock
apt_locked() {
    local lock
    for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock; do
        [[ -e "$lock" ]] || continue
        if sudo fuser "$lock" &>/dev/null; then
            return 0
        fi
    done
    return 1
}

update_apt() {
    log_header "APT Update"

    if ! ask_yes_no "Update apt?" "N"; then
        log_info "Apt update skipped."
        return 0
    fi

    if command -v fuser &>/dev/null && apt_locked; then
        log_error "Another apt/dpkg process is running (lock held) – skipping apt update"
        return 1
    fi

    log_info "Refreshing package lists..."
    if ! sudo apt update; then
        log_error "apt update failed – skipping upgrade and cleanup"
        return 1
    fi

    log_info "Upgradable packages:"
    apt list --upgradable 2>/dev/null | tail -n +2

    # full-upgrade (= dist-upgrade) may install/remove packages to resolve
    # dependency changes, which is what a rolling kernel/library bump needs
    log_info "Performing full system upgrade..."
    if ! sudo apt full-upgrade; then
        log_error "apt full-upgrade failed – skipping autoremove and cache cleanup"
        return 1
    fi

    log_info "Checking for packages that are no longer required..."
    # apt shows the removal list and asks for confirmation itself
    sudo apt autoremove --purge || log_error "Autoremove failed or was declined"

    # Packages removed with plain `remove` leave config files behind (dpkg state "rc")
    local -a residual=()
    mapfile -t residual < <(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}')
    if (( ${#residual[@]} > 0 )); then
        log_info "Packages with leftover config files: ${residual[*]}"
        if ask_yes_no "Purge leftover config files of removed packages?" "N"; then
            sudo apt purge "${residual[@]}" || log_error "Purge failed or was declined"
        fi
    else
        log_info "No leftover package configs found"
    fi

    if ask_yes_no "Clean apt cache?" "Y"; then
        log_info "Cleaning apt cache..."
        sudo apt clean || true
        sudo apt autoclean || true
    fi
    return 0
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
        # `sudo flatpak repair` alone only touches the SYSTEM installation
        log_info "Repairing flatpak user installation..."
        flatpak repair --user || true
        log_info "Repairing flatpak system installation..."
        sudo flatpak repair --system || true
        log_info "Flatpak repair complete"
    fi
}

#============================================================
# SHELL UPDATE FUNCTIONS
#============================================================

update_shell() {
    log_header "Update zsh shell"

    if ask_yes_no "Update Zinit itself?" "N"; then
        zsh -ic "zinit self-update" || true
    else
        log_info "Zinit self-update skipped."
    fi

    # Independent of the self-update prompt above
    if ask_yes_no "Update zinit plugins?" "Y"; then
        zsh -ic "zinit update --all" || true
        zsh -ic "zinit zstatus" || true
    else
        log_info "Zinit plugin update skipped."
    fi
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

    # NOTE: `yazi -- --debug` treats "--debug" as a path and opens the TUI,
    # blocking the script. The flag must come before any `--`.
    if ask_yes_no "Print yazi debug info?" "N"; then
        zsh -ic "yazi --debug" || true
    fi
}

#============================================================
# LOG CLEANUP FUNCTIONS
#============================================================

logs_journalctl() {
    log_header "Cleaning logs"

    # Note: this measures used space on / as a whole, not just logs
    local used_before used_after delta
    used_before=$(df --output=used -B1 / | tail -1 | tr -d ' ') || used_before=0
    log_info "Disk used before cleanup: $((used_before / 1024 / 1024)) MB"

    if ask_yes_no "Vacuum journalctl down?" "N"; then
        log_info "Shrinking journalctl total size, and rotating logs"

        sudo journalctl --sync 2>/dev/null || true
        sudo journalctl --flush 2>/dev/null || true
        sudo journalctl --rotate 2>/dev/null || true
        sudo journalctl --vacuum-size=10M 2>/dev/null || true

        if command -v logrotate &>/dev/null; then
            log_info "Forcing logrotate"
            sudo logrotate -f /etc/logrotate.conf 2>/dev/null || true
        fi
    else
        log_info "Skipping journalctl vacuum"
    fi

    if ask_yes_no "Shorten ACTIVE log files? (Highly invasive)" "N"; then
        # pacman.log, dpkg.log and apt's history.log are kept: they are your
        # upgrade history. journald is not stopped: its sockets would just restart it.
        log_info "Emptying current log files (pacman/dpkg/apt history preserved)"
        sudo find /var/log -maxdepth 2 -type f -name "*.log" \
            ! -name "pacman.log" ! -name "dpkg.log" ! -name "history.log" \
            -exec truncate -s 0 {} + 2>/dev/null || true

        log_info "Removing rotated log files"
        sudo find /var/log -type f -name "*.log.*" \
            ! -name "pacman.log*" ! -name "dpkg.log*" ! -name "history.log*" \
            -delete 2>/dev/null || true
    else
        log_info "Skipping removal of current log files"
    fi

    if ask_yes_no "Clear coredumps?" "N"; then
        log_info "Cleaning coredump files..."

        # /tmp and /var/tmp deliberately NOT included: wiping /tmp under a
        # running session removes live sockets (X11, tmux, ...).
        local dirs_to_clean=(
            "/var/lib/systemd/coredump"
            "/var/crash"
            "/var/dumps"
        )

        local dir_path
        for dir_path in "${dirs_to_clean[@]}"; do
            if [[ -d "$dir_path" ]]; then
                log_info "Contents of ${dir_path}:"
                sudo ls -lah "$dir_path" 2>/dev/null || true

                if ask_yes_no "Delete all contents of ${dir_path}?" "N"; then
                    # find -delete can't remove non-empty subdirs at maxdepth 1
                    sudo find "$dir_path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
                    log_info "Cleaned ${dir_path}"
                else
                    log_info "Skipped ${dir_path}"
                fi
            fi
        done
        log_info "Coredump cleanup complete"
    else
        log_info "Skipping coredump removal"
    fi

    log_info "Syncing filesystem..."
    sync
    sleep 2

    used_after=$(df --output=used -B1 / | tail -1 | tr -d ' ') || used_after=0
    delta=$((used_after - used_before))

    log_info "Disk used before: $((used_before / 1024 / 1024)) MB"
    log_info "Disk used after : $((used_after / 1024 / 1024)) MB"
    log_info "Change          : $((delta / 1024 / 1024)) MB"
}

#============================================================
# POST-UPGRADE CHECKS
#============================================================

check_post_upgrade() {
    log_header "Post-upgrade checks"

    if command -v pacman &>/dev/null; then
        # Unmerged config files (this also catches a new pacman mirrorlist.pacnew
        # that would silently supersede your ranked mirrorlist)
        local pacnew
        pacnew=$(sudo find /etc \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null)
        if [[ -n "$pacnew" ]]; then
            log_info "Unmerged config files found (merge with 'sudo pacdiff' from pacman-contrib):"
            echo "$pacnew"
        else
            log_info "No .pacnew/.pacsave files found"
        fi
    fi

    if command -v apt &>/dev/null; then
        # Config files dpkg/ucf left for manual merging
        local dpkgnew
        dpkgnew=$(sudo find /etc \( -name '*.dpkg-new' -o -name '*.dpkg-dist' -o -name '*.dpkg-old' \
            -o -name '*.ucf-new' -o -name '*.ucf-dist' -o -name '*.ucf-old' \) 2>/dev/null)
        if [[ -n "$dpkgnew" ]]; then
            log_info "Unmerged config files found (compare with 'diff' and merge manually):"
            echo "$dpkgnew"
        else
            log_info "No .dpkg-*/.ucf-* files found"
        fi

        # Debian/Ubuntu flag a needed reboot with this file
        if [[ -f /var/run/reboot-required ]]; then
            log_info "Reboot required by upgraded packages:"
            cat /var/run/reboot-required.pkgs 2>/dev/null | sort -u | sed 's/^/  /'
        fi
    fi

    # Kernel modules for the running kernel vanish once the kernel is upgraded
    if [[ ! -d "/usr/lib/modules/$(uname -r)" && ! -d "/lib/modules/$(uname -r)" ]]; then
        log_info "Running kernel ($(uname -r)) no longer matches installed modules – reboot recommended"
    fi

    if command -v systemctl &>/dev/null; then
        local failed
        failed=$(systemctl --failed --no-legend 2>/dev/null)
        if [[ -n "$failed" ]]; then
            log_info "Failed systemd units:"
            echo "$failed"
        fi
    fi
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
            log_info "Rebooting system in 10 seconds (Ctrl+C to abort)..."
            sleep 10
            sudo reboot
        fi
    fi

    return 0
}

#============================================================
# SUDO KEEPALIVE
#============================================================

# Long upgrades can outlive sudo's credential cache and re-prompt mid-run.
start_sudo_keepalive() {
    sudo -v || return 1
    (
        while kill -0 "$$" 2>/dev/null; do
            sudo -n true 2>/dev/null
            sleep 50
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
}

#============================================================
# MAIN ENTRY POINT
#============================================================

main() {
    log_header "Starting Full System Upgrade"

    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run as root: flatpak --user, zsh and yay need your normal user (sudo is used where needed)"
        return 1
    fi

    for cmd in sudo df awk; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    start_sudo_keepalive || { log_error "sudo authentication failed"; return 1; }

    show_disk_space "Initial disk space"

    if command -v pacman &>/dev/null; then
        mirrorlist
    fi

    if command -v fwupdmgr &>/dev/null; then
        update_firmware
    fi

    if command -v pacman &>/dev/null; then
        # AUR step is skipped if the repo upgrade itself failed
        update_pacman && update_aur
    fi

    if command -v apt &>/dev/null && command -v dpkg &>/dev/null; then
        update_apt
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

    if command -v yazi &>/dev/null; then
        update_yazi
    fi

    if command -v pacman &>/dev/null || command -v apt &>/dev/null; then
        check_post_upgrade
    fi

    final
}

#============================================================
# SCRIPT EXECUTION
#============================================================

main
exit $?
