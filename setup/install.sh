#!/bin/bash
CURRENT_LOCATION="$(pwd -P)"
SCRIPT_LOCATION="$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd -P)"

# PARAMETERS
P_SKIP_ROOT=0

# Include dependencies
source "${SCRIPT_LOCATION}/commons/screen.sh"
source "${SCRIPT_LOCATION}/commons/logging.sh"
source "${SCRIPT_LOCATION}/commons/input.sh"

logInternal "Screen size is ${SCREEN_ROWS}x${SCREEN_COLS} (${SCREEN_SIZE})"

CARMEDIAPI="${COLOR_BLUE}CAR${COLOR_DGRAY}(${COLOR_GREEN}MEDIA${COLOR_DGRAY})${COLOR_RED}PI${COLOR_NONE}"

function createHotspotConfig {
    path=$1
    hotspot_name=$2
    hotspot_psk=$3

    cat <<EOF > $path
# ########################################### #
# HOTSPOT CONFIGURATION                       #
# ########################################### #
interface=wlan0
driver=nl80211
hw_mode=g
channel=1
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
ssid=${hotspot_name}
wpa=2
wpa_passphrase=${hotspot_psk}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
ieee80211n=1
wmm_enabled=1
basic_rates=180 240 360 480 540
beacon_int=50
dtim_period=20
EOF

    ln -s "$path" /etc/hostapd/hostapd.conf
}

function installHotspot {
    hotspot_name=$1
    hotspot_psk=$2

    logProcess "Installing Hotspot ..."
    apt -y install hostapd

    logProcess "Patching known hostapd crash ..."
    rm -f /etc/modprobe.d/blacklist-rtl8192cu.conf

    logProcess "Setting up hotspot configuration ..."
    createHotspotConfig "/boot/settings/hotspot.conf" "$hotspot_name" "$hotspot_psk"

    logProcess "Configuring hostapd service ..."
    systemctl unmask hostapd
    systemctl enable hostapd
}

function installIpForward {
    logProcess "Setting up IP forwarding ..."
}

function installPiHole {
    logProcess "Installing Pi-Hole ..."
}

function installDnsMasq {
    logProcess "Installing Dnsmasq ..."
}

function installSamba {
    logProcess "Installing Samba ..."
}

function main {
    if [[ $P_SKIP_ROOT -ne 1 ]]; then
        if [[ $EUID -ne 0 ]]; then
            logFatal "This script must be run as root"
            exit 401
        fi
    else
        logWarn "Skipped root check, you might experience issues when running the installation"
        logBlank ""
    fi

    logBlank "WELCOME TO THE ${CARMEDIAPI} INSTALLER!"

    logBlank "This script will install ${CARMEDIAPI} on your Raspbian installation."
    logBlank "To ensure a smooth installation, make sure you are running a clean and up-to-date version of Raspbian."
    logBlank ""

    # Ask for components to install
    logBlank "Before we install ${CARMEDIAPI}, let me ask you a few questions."
    logBlank ""

    logBlank "Components to install:"

    confirm "Install Hotspot? (recommended)"
    response_hotspot=$(($?==0))
    response_hotspot_name=0
    response_hotspot_psk=0

    if [[ $response_hotspot -eq 1 ]]; then
        q=$(log "[?]" "Enter a Hotspot name (SSID): " "${COLOR_BLUE}")
        read -p "$q" response_hotspot_name

        q=$(log "[?]" "Enter a Hotspot password (WPA2-PSK): " "${COLOR_BLUE}")
        read -p "$q" response_hotspot_psk
    fi

    confirm "Forward network connection? (default: yes)"
    response_ipforward=$(($?==0))

    response_pihole=0
    if [[ $response_ipforward -eq 1 ]]; then
        confirm "Install Pi-Hole, the network-wide adblocker? (recommended)"
        response_pihole=$(($?==0))
    fi

    confirm "Install Samba (SMB File Share)? (default: yes)"
    response_samba=$(($?==0))

    # Log changes to be applied and ask user for confirmation
    logInfo "The following changes will be applied:"
    if [[ $response_hotspot -eq 1 ]]; then
        logBlank "- Install package \"hostapd\""
        logBlank "  - Configure hostapd with SSID \"${response_hotspot_name}\""
        logBlank "  - Configure hostapd with WPA PSK \"${response_hotspot_psk}\""
    fi
    if [[ $response_ipforward -eq 1 ]]; then
        logBlank "- Setup IP forwarding (NAT)"
    fi
    if [[ $response_pihole -eq 1 ]]; then
        logBlank "- Install Pi-Hole"
    else
        logBlank "- Install package \"dnsmasq\""
    fi
    if [[ $response_samba -eq 1 ]]; then
        logBlank "- Install package \"samba\" and \"samba-common-bin\""
    fi

    confirm "Do you want to proceed with the installation?"
    if [[ $? -eq 1 ]]; then
        logWarn "OK, installation is canceled"
        exit 1
    fi

    logInfo "OK, let's go!"
    if [[ $response_hotspot -eq 1 ]]; then
        installHotspot "${response_hotspot_name}" "${response_hotspot_psk}"
    fi
    if [[ $response_ipforward -eq 1 ]]; then installIpForward; fi
    if [[ $response_pihole -eq 1 ]]; then
        installPiHole
    else
        installDnsMasq
    fi
    if [[ $response_samba -eq 1 ]]; then installSamba; fi
}

# ### Arguments ###
POSITIONAL=()
while [[ $# -gt 0 ]]
do
    key="$1"

    case ${key} in
        --skip-root)
        P_SKIP_ROOT=1
        shift
        ;;
        *)
        logFatal "Invalid parameter provided: $1"
        exit 1
        ;;
    esac
done

main
