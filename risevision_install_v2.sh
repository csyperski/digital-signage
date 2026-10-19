#!/usr/bin/env bash
#
# Raspberry Pi OS (64-bit) Debian Trixie with the Raspberry Pi Desktop
# https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2026-10-06/2026-10-06-raspios-trixie-arm64.img.xz
#
# Rise Vision Player installer for Raspberry Pi 5 (also works on Pi 3B/4B)
# Based on: https://help.risevision.com/hc/en-us/articles/115001872303
# 
set -uo pipefail

TITLE="Rise Vision Player Installer"
BASE_URL="https://storage.googleapis.com/install-versions.risevision.com"
DL_DIR="$HOME/Downloads"
RV_DIR="$HOME/rvplayer"
LOG="$HOME/risevision_install.log"
STATE_FILE="$HOME/.config/risevision_install.state"
AUTOSTART_FILE="$HOME/.config/autostart/risevision-install-resume.desktop"
SCRIPT_PATH="$(readlink -f "$0")"
SUDO_KEEPALIVE_PID=""

# ---------------------------------------------------------------- helpers ---

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

term_size() {
    local rows cols
    rows=$(tput lines 2>/dev/null || echo 24)
    cols=$(tput cols 2>/dev/null || echo 80)
    WT_H=$(( rows - 4 < 20 ? rows - 4 : 20 ))
    WT_W=$(( cols - 10 < 74 ? cols - 10 : 74 ))
    WT_MENU_H=$(( WT_H - 10 ))
}

msg()   { whiptail --title "$TITLE" --msgbox "$1" "$WT_H" "$WT_W"; }
yesno() { whiptail --title "$TITLE" --yesno "$1" "$WT_H" "$WT_W" "${@:2}"; }

die() {
    log "FATAL: $1"
    whiptail --title "$TITLE - Error" --msgbox "$1\n\nSee log: $LOG" "$WT_H" "$WT_W"
    exit 1
}

cleanup() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
}
trap cleanup EXIT

start_sudo() {
    clear
    echo "Administrator (sudo) access is needed for system updates and configuration."
    sudo -v || die "Could not obtain sudo privileges."
    # Keep the sudo timestamp fresh until this script exits
    ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

# ---------------------------------------------------------------- checks ---

preflight() {
    command -v whiptail >/dev/null || { echo "whiptail is required: sudo apt install whiptail"; exit 1; }
    term_size

    [[ $EUID -eq 0 ]] && die "Do not run this script as root or with sudo.\n\nRise Player installs into the current user's home folder (~/rvplayer). Run it as the user that will log in to the display."

    MODEL=$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo "Unknown")
    if [[ "$MODEL" != *"Raspberry Pi"* ]]; then
        yesno "This does not look like a Raspberry Pi (detected: $MODEL).\n\nContinue anyway?" --defaultno || exit 1
    elif [[ "$MODEL" != *"Raspberry Pi 5"* ]]; then
        yesno "Detected: $MODEL\n\nThis script targets the Pi 5, but Rise Vision also supports the Pi 3B and 4B. Continue?" || exit 1
    fi

    case "$(uname -m)" in
        aarch64) ARCH_LABEL="64-bit"; INSTALLER="installer-lnx-arm64.sh" ;;
        armv7l)  ARCH_LABEL="32-bit"; INSTALLER="installer-lnx-armv7l.sh" ;;
        *) die "Unsupported architecture: $(uname -m)\nRise Player for Raspberry Pi needs armv7l or aarch64." ;;
    esac
    # A 64-bit kernel with 32-bit userland reports aarch64; trust userland
    if [[ "$ARCH_LABEL" == "64-bit" && "$(getconf LONG_BIT)" == "32" ]]; then
        ARCH_LABEL="32-bit"; INSTALLER="installer-lnx-armv7l.sh"
    fi

    if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
        yesno "No desktop session detected.\n\nRise Vision does not support headless/SSH installs. The installer must be run from a Terminal on the Pi's desktop with a monitor attached.\n\nContinue anyway (not recommended)?" --defaultno || exit 1
    fi

    if ! curl -sfI --max-time 10 "$BASE_URL/$INSTALLER" >/dev/null; then
        die "Cannot reach the Rise Vision download server.\nCheck the network connection and try again."
    fi

    OS_NAME=$(. /etc/os-release && echo "$PRETTY_NAME")
    log "Preflight OK: model='$MODEL' os='$OS_NAME' arch=$ARCH_LABEL installer=$INSTALLER"
}

# ---------------------------------------------------------------- steps ---

# Runs apt-get and drives a whiptail gauge from apt's machine-readable status
apt_gauge() {
    local caption=$1; shift
    log "apt-get $*"
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
        -o APT::Status-Fd=3 "$@" 3>&1 1>>"$LOG" 2>&1 \
    | awk -F: '/^(pm|dl)status/ { printf "XXX\n%d\n%s\n\n%s\nXXX\n", $3, cap, $4; fflush() }' cap="$caption" \
    | whiptail --title "$TITLE" --gauge "$caption" 10 "$WT_W" 0
    return "${PIPESTATUS[0]}"
}

# Returns 0 if the hostname changed (caller should reboot), 1 if unchanged
step_hostname() {
    local current new
    current=$(hostname)
    while true; do
        new=$(whiptail --title "$TITLE" --inputbox \
            "Enter a new hostname for this display.\n\nAllowed: letters a-z, digits 0-9 and hyphens (not at the start or end), max 63 characters.\n\nCurrent: $current" \
            "$WT_H" "$WT_W" "$current" 3>&1 1>&2 2>&3) || return 1
        new=${new,,}
        if [[ "$new" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
            break
        fi
        msg "\"$new\" is not a valid hostname. Please try again."
    done
    if [[ "$new" == "$current" ]]; then
        log "Hostname unchanged ($current)"
        return 1
    fi
    log "Changing hostname: $current -> $new"
    sudo raspi-config nonint do_hostname "$new" >>"$LOG" 2>&1 || die "Failed to set hostname to $new."
    return 0
}

step_apt() {
    apt_gauge "Removing unused packages (apt autoremove)..." autoremove || die "apt autoremove failed."
    { echo 10; sudo apt-get update >>"$LOG" 2>&1; echo $? >"$LOG.rc"; echo 100; } \
        | whiptail --title "$TITLE" --gauge "Refreshing package lists (apt update)..." 8 "$WT_W" 0
    [[ "$(cat "$LOG.rc")" == 0 ]] || { rm -f "$LOG.rc"; die "apt update failed."; }
    rm -f "$LOG.rc"
    apt_gauge "Upgrading packages (apt upgrade)..." upgrade || die "apt upgrade failed."
    NEED_REBOOT=1
}

step_password() {
    local pw1 pw2
    while true; do
        pw1=$(whiptail --title "$TITLE" --passwordbox "Enter a new password for user '$USER':" 10 "$WT_W" 3>&1 1>&2 2>&3) || return
        pw2=$(whiptail --title "$TITLE" --passwordbox "Confirm the new password:" 10 "$WT_W" 3>&1 1>&2 2>&3) || return
        if [[ -z "$pw1" ]]; then
            msg "The password cannot be empty."
        elif [[ "$pw1" != "$pw2" ]]; then
            msg "The passwords do not match. Please try again."
        else
            break
        fi
    done
    printf '%s:%s\n' "$USER" "$pw1" | sudo chpasswd || die "Failed to change the password."
    log "Password changed for $USER"
    PASSWORD_CHANGED=1
}

step_pi_settings() {
    local -a settings=(
        "US keyboard layout|do_configure_keyboard us"
        "Disable screen blanking|do_blanking 1"
        "Disable on-screen keyboard|do_squeekboard S3"
        "Wi-Fi country US|do_wifi_country US"
    )
    local n=${#settings[@]} i=0 entry label cmd
    for entry in "${settings[@]}"; do
        label=${entry%%|*}; cmd=${entry#*|}
        echo "$(( i * 100 / n ))" | whiptail --title "$TITLE" --gauge "Applying Pi settings: $label..." 8 "$WT_W" 0
        log "raspi-config nonint $cmd"
        # shellcheck disable=SC2086
        sudo raspi-config nonint $cmd >>"$LOG" 2>&1 || die "Failed: $label (raspi-config nonint $cmd)"
        i=$(( i + 1 ))
    done
    NEED_REBOOT=1
}

step_autologin() {
    log "Enabling desktop autologin for $USER"
    sudo raspi-config nonint do_boot_behaviour B4 >>"$LOG" 2>&1 || die "Failed to enable desktop autologin."
    NEED_REBOOT=1
}

step_fonts() {
    # Pre-accept the Microsoft fonts EULA so the Rise installer won't stop on it
    log "Pre-accepting ttf-mscorefonts EULA"
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
        | sudo debconf-set-selections
    if apt-cache show ttf-mscorefonts-installer &>/dev/null; then
        apt_gauge "Installing Microsoft core fonts..." install ttf-mscorefonts-installer \
            || log "WARN: ttf-mscorefonts-installer failed (non-fatal)"
    else
        log "WARN: ttf-mscorefonts-installer not available (contrib repo disabled?) - skipping"
    fi
}

step_download() {
    mkdir -p "$DL_DIR"
    local dest="$DL_DIR/$INSTALLER" url="$BASE_URL/$INSTALLER" total
    total=$(curl -sfIL "$url" | awk 'tolower($1)=="content-length:" {v=$2} END {gsub("\r","",v); print v+0}')
    log "Downloading $url ($total bytes) -> $dest"
    rm -f "$dest"
    curl -sfL -o "$dest" "$url" >>"$LOG" 2>&1 &
    local pid=$!
    (
        while kill -0 "$pid" 2>/dev/null; do
            local have; have=$(stat -c %s "$dest" 2>/dev/null || echo 0)
            (( total > 0 )) && echo $(( have * 100 / total ))
            sleep 0.5
        done
        echo 100
    ) | whiptail --title "$TITLE" --gauge "Downloading Rise Player ($ARCH_LABEL)..." 8 "$WT_W" 0
    wait "$pid" || die "Download failed: $url"
    chmod +x "$dest"
}

step_install() {
    whiptail --title "$TITLE" --msgbox "The official Rise Vision installer will now run in this terminal.\n\n\
 1. Press  y  to confirm the installation.\n\
 2. If asked for your password, type it and press Enter\n    (keystrokes are hidden).\n\
 3. If asked about Microsoft Fonts, select OK.\n\
 4. When asked to start Rise Player automatically, choose\n    YES for a dedicated signage display.\n\
 5. Follow the activation screen to link the display.\n\n\
Tip: Ctrl+Shift+Q closes the Player." "$WT_H" "$WT_W"
    clear
    log "Running $DL_DIR/$INSTALLER"
    ( cd "$DL_DIR" && "./$INSTALLER" ) 2>&1 | tee -a "$LOG"
    local rc=${PIPESTATUS[0]}
    log "Installer exited with code $rc"
    [[ $rc -eq 0 ]] || die "The Rise Vision installer exited with code $rc."
    [[ -d "$RV_DIR" ]] || die "Install finished but $RV_DIR was not created."
}

# ---------------------------------------------------------------- flows ---

do_install() {
    if [[ -d "$RV_DIR" ]]; then
        yesno "Rise Player is already installed in $RV_DIR.\n\nReinstall / update it?" || return
    fi

    local choices
    choices=$(whiptail --title "$TITLE" --separate-output --checklist \
        "Device: $MODEL ($(hostname))\nOS: $OS_NAME ($ARCH_LABEL)\n\nSelect the steps to run (SPACE toggles, ENTER confirms):" \
        "$WT_H" "$WT_W" "$WT_MENU_H" \
        HOSTNAME  "Change hostname, then reboot"               ON \
        APT       "apt autoremove, update, upgrade"            ON \
        PASSWORD  "Change password for '$USER'"                ON \
        SETTINGS  "Keyboard US, no blanking, OSK off, WiFi US"  ON \
        AUTOLOGIN "Desktop auto-login as '$USER'"              ON \
        FONTS     "Pre-install Microsoft fonts (accept EULA)"  ON \
        RISE      "Download & install Rise Vision Player"      ON \
        3>&1 1>&2 2>&3) || return
    [[ -z "$choices" ]] && { msg "Nothing selected."; return; }

    # shellcheck disable=SC2086
    run_steps $choices
}

# Saves the remaining steps and registers a one-time autostart entry so the
# script reopens in a terminal after the reboot
schedule_resume() {
    mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$AUTOSTART_FILE")"
    echo "$*" >"$STATE_FILE"
    cat >"$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Resume Rise Vision install
Exec=x-terminal-emulator -e "$SCRIPT_PATH" --resume
Terminal=false
EOF
    log "Scheduled resume after reboot with steps: $*"
}

clear_resume() {
    rm -f "$STATE_FILE" "$AUTOSTART_FILE"
}

run_steps() {
    local steps=("$@")
    start_sudo
    NEED_REBOOT=0
    PASSWORD_CHANGED=0
    local done_list="" i
    for (( i = 0; i < ${#steps[@]}; i++ )); do
        case ${steps[i]} in
            HOSTNAME)
                if step_hostname; then
                    local rest=("${steps[@]:i+1}")
                    if (( ${#rest[@]} > 0 )); then
                        schedule_resume "${rest[@]}"
                        msg "Hostname changed to $(cat /etc/hostname).\n\nThe Pi will now reboot. After you are logged back in to the desktop, a terminal will open automatically and continue with:\n\n  ${rest[*]}"
                    else
                        msg "Hostname changed to $(cat /etc/hostname).\n\nThe Pi will now reboot."
                    fi
                    log "Rebooting after hostname change"
                    sudo reboot
                    exit 0
                fi
                done_list+="  - Hostname unchanged\n" ;;
            APT)       step_apt;       done_list+="  - Packages autoremoved, updated, upgraded\n" ;;
            PASSWORD)  step_password
                       [[ $PASSWORD_CHANGED -eq 1 ]] && done_list+="  - Password changed for $USER\n" ;;
            SETTINGS)  step_pi_settings
                       done_list+="  - Keyboard US, blanking off, on-screen keyboard off, Wi-Fi country US\n" ;;
            AUTOLOGIN) step_autologin; done_list+="  - Desktop auto-login enabled\n" ;;
            FONTS)     step_fonts;     done_list+="  - Microsoft fonts installed\n" ;;
            RISE)      step_download; step_install; done_list+="  - Rise Vision Player installed\n" ;;
        esac
    done
    clear_resume

    term_size
    msg "Done!\n\nHostname: $(hostname)\n${done_list}\nPlayer location: $RV_DIR\nRelaunch: Raspberry menu > Other > Start Rise Vision Player\nLog: $LOG"
    if [[ $NEED_REBOOT -eq 1 ]] && yesno "A reboot is recommended to apply the changes.\n\nReboot now?"; then
        log "Rebooting"
        sudo reboot
    fi
}

check_resume() {
    [[ -s "$STATE_FILE" ]] || return 0
    local pending; pending=$(<"$STATE_FILE")
    if yesno "An unfinished install was found (hostname is now $(hostname)).\n\nRemaining steps:\n  $pending\n\nContinue now?"; then
        # shellcheck disable=SC2086
        run_steps $pending
    elif yesno "Discard the unfinished install?" --defaultno; then
        clear_resume
        log "Discarded pending steps: $pending"
    fi
}

do_uninstall() {
    local script="$RV_DIR/scripts/uninstall.sh"
    [[ -x "$script" ]] || die "Uninstaller not found at $script"
    yesno "Remove Rise Vision Player from this device?" --defaultno || return
    clear
    log "Running $script"
    "$script" 2>&1 | tee -a "$LOG"
    msg "Rise Vision Player has been uninstalled."
}

main() {
    preflight
    check_resume
    while true; do
        local items=(INSTALL "Install / update Rise Vision Player")
        [[ -d "$RV_DIR" ]] && items+=(UNINSTALL "Uninstall Rise Vision Player")
        items+=(LOG "View install log" EXIT "Exit")

        local choice
        choice=$(whiptail --title "$TITLE" --menu \
            "Device: $MODEL\nOS: $OS_NAME ($ARCH_LABEL)\nPlayer: $([[ -d $RV_DIR ]] && echo "installed" || echo "not installed")" \
            "$WT_H" "$WT_W" "$WT_MENU_H" "${items[@]}" 3>&1 1>&2 2>&3) || break
        case $choice in
            INSTALL)   do_install ;;
            UNINSTALL) do_uninstall ;;
            LOG)       [[ -f $LOG ]] && whiptail --title "$LOG" --scrolltext --textbox "$LOG" "$WT_H" "$WT_W" || msg "No log yet." ;;
            EXIT)      break ;;
        esac
    done
    clear
}

main "$@"
