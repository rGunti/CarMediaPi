#!/bin/bash
CURRENT_LOCATION="$(pwd -P)"
SCRIPT_LOCATION="$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd -P)"

# PARAMETERS
P_SKIP_ROOT=0

# Include dependencies
#source "${SCRIPT_LOCATION}/commons/screen.sh"
source "${SCRIPT_LOCATION}/commons/logging.sh"
source "${SCRIPT_LOCATION}/commons/input.sh"

#logInternal "Screen size is ${SCREEN_ROWS}x${SCREEN_COLS} (${SCREEN_SIZE})"

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

function configureDhcpcd {
    cat <<EOF > "/etc/dhcpcd.conf"
# ########################################### #
# DHCPCD CONFIGURATION                        #
# ########################################### #

hostname
clientid
persistent
option rapid_commit
option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes
require dhcp_server_identifier
slaac private

interface wlan0
        static ip_address=10.0.0.1/24
        nohook wpa_supplicant
EOF
}

function installHotspot {
    hotspot_name=$1
    hotspot_psk=$2

    logProcess "Installing Hotspot ..."
    apt -y install hostapd

    logProcess "Patching known hostapd crash ..."
    rm -f /etc/modprobe.d/blacklist-rtl8192cu.conf

    logProcess "Setting up hotspot configuration ..."
    mkdir "/boot/settings" 2> /dev/null
    createHotspotConfig "/boot/settings/hotspot.conf" "$hotspot_name" "$hotspot_psk"

    logProcess "Configuring hostapd service ..."
    systemctl unmask hostapd
    systemctl enable hostapd

    logProcess "Configuring local IP address ..."
    configureDhcpcd
}

function installIpForward {
    logProcess "Setting up IP forwarding ..."
    echo "net.ipv4.ip_forward=1" | tee -a /etc/sysctl.conf
    iptables -t nat -A  POSTROUTING -o eth0 -j MASQUERADE
    iptables -t nat -A  POSTROUTING -o wlan1 -j MASQUERADE
    sh -c "iptables-save > /etc/iptables.ipv4.nat"

    logWarn "We have to overwrite /etc/rc.local! We're creating a copy of your current file so you don't loose any changes."
    logProcess "Backing up /etc/rc.local ..."
    cp /etc/rc.local /etc/rc.local.ORIG
    cat <<EOF > /etc/rc.local
#!/bin/sh -e
# Generated by Car(Media)Pi installer

# - Restores iptables for NAT
iptables-restore < /etc/iptables.ipv4.nat

# --- Add your custom routines below this line ---

# --- Add your custom routines above this line ---

exit 0
EOF
}

function configureDhcpServer {
    logProcess "Configuring DHCP server ..."

    cat <<EOF > "/etc/dnsmasq.d/010-wifi-hotspot.conf"
# ########################################### #
# DNSMASQ CONFIGURATION                       #
# WiFi DHCP Configuration                     #
# ########################################### #

interface=wlan0
dhcp-range=10.0.0.100,10.0.0.200,255.255.255.0,1h

local=/pi/
domain=pi
EOF

    cat <<EOF > "/etc/dnsmasq.d/011-domains.conf"
# ########################################### #
# DNSMASQ CONFIGURATION                       #
# Domains Overwrite Configuration             #
# ########################################### #

address=/pi/10.0.0.1
address=/pi.net/10.0.0.1
EOF
}

function installPiHole {
    logProcess "Installing Pi-Hole ..."
    logInfo "The installation is interactive, please be ready to answer more questions!"
    logInfo "If the Pi-Hole installer asks you for a static IP address, enter the following values:"
    logBlank " - Interface:  wlan0"
    logBlank " - IP address: 10.0.0.1/24"
    logBlank " - Gateway:    10.0.0.1"

    _msg=$(logBlank "Press any key to continue ...")
    read -n1 -p "${_msg}"
    _msg=$(logProcess "Downloading and installing Pi-Hole ...")
    echo -e "\r${_msg}"

    curl -sSL https://install.pi-hole.net | bash

    if [[ $? -ne 0 ]]; then
        logFatal "Installation of Pi-Hole apperantly failed! Aborting ${CARMEDIAPI} installation as well ..."
        exit 100
    fi

    logInfo "Pi-Hole installation completed! Continuing with more configuration ..."
    configureDhcpServer

    logProcess "Patching permission issue with dnsmasq lease file ..."
    chown -R pihole:pihole /var/lib/misc/
}

function installDnsMasq {
    logProcess "Installing Dnsmasq ..."
    apt -y install dnsmasq

    logProcess "Adding dnsmasq configuration ..."
    mkdir "/etc/dnsmasq.d" 2> /dev/null
    cat <<EOF > "/etc/dnsmasq.conf"
# ########################################### #
# DNSMASQ CONFIGURATION                       #
# Default Configuration                       #
# ########################################### #

conf-dir=/etc/dnsmasq.d
EOF

    configureDhcpServer
}

function installSamba {
    logProcess "Installing Samba ..."
    apt -y install samba

    logProcess "Backing up original Samba configuration ..."
    mv /etc/samba/smb.conf /etc/samba/smb.conf.orig

    logProcess "Configuring Samba ..."
    cat <<EOF > /etc/samba/smb.conf
[global]
	workgroup = CARMEDIAPI
	log file = /var/log/samba/log.%m
	max log size = 1000
	logging = file
	panic action = /usr/share/samba/panic-action %d
	server role = standalone server
	obey pam restrictions = yes
	unix password sync = yes
	passwd program = /usr/bin/passwd %u
	passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
	pam password change = yes
	map to guest = bad user
	usershare allow guests = yes
[homes]
	comment = Home Directories
	browseable = no
	read only = yes
	create mask = 0700
	directory mask = 0700
	valid users = %S
[Media]
	comment = Media Drive
	path = /umedia
	create mask = 0777
	directory mask = 0777
	read only = no
	browsable = yes
	public = yes
	force user = pi
	only guest = no
EOF

    logProcess "Creating file share location ..."
    mkdir /umedia
    chown -R pi:pi /umedia
}

function installExfat {
    logProcess "Installing exFAT support ..."
    apt -y install exfat-fuse exfat-utils
}

function configureFstab {
    fileSystem=${1}

    logProcess "Configuring auto-mount ..."
    cat <<EOF | tee -a /etc/fstab
# ### CAR(MEDIA)PI ### #
/dev/disk/by-label/CARMEDIAPI	/umedia	${fileSystem}	defaults,nofail,auto,users,rw,umask=000,uid=1000,gid=1000	0	0
# #################### #
EOF
}

function updatePackageSources {
    logProcess "Updating package sources ..."
    apt update

    logProcess "Updating local packages ..."
    apt upgrade -y
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
        q=$(log "[?]" "Enter a Hotspot name (SSID) [Default: $HOSTNAME]: " "${COLOR_BLUE}")
        read -p "$q" response_hotspot_name

        if [ -z "$response_hotspot_name" ]; then
            logInfo "Using hostname $HOSTNAME as SSID"
            response_hotspot_name=$HOSTNAME
        fi

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
    response_exfat=0
    if [[ $response_samba -eq 1 ]]; then
        confirm "Install exFAT support?"
        response_exfat=$(($?==0))
    fi

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
        logBlank "- Setup file share"
        if [[ $response_exfat -eq 1 ]]; then
            logBlank "- Setup exFAT support for external storage"
        fi
    fi

    confirm "Do you want to proceed with the installation?"
    if [[ $? -eq 1 ]]; then
        logWarn "OK, installation is canceled"
        exit 1
    fi

    # Run Installation routines
    logInfo "OK, let's go!"
    updatePackageSources

    if [[ $response_pihole -eq 1 ]]; then
        installPiHole
    else
        installDnsMasq
    fi

    if [[ $response_hotspot -eq 1 ]]; then
        installHotspot "${response_hotspot_name}" "${response_hotspot_psk}"
    fi

    if [[ $response_ipforward -eq 1 ]]; then installIpForward; fi

    if [[ $response_samba -eq 1 ]]; then
        installSamba
        if [[ $response_exfat -eq 1 ]]; then
            installExfat
            configureFstab "exfat"
        else
            configureFstab "vfat"
        fi
    fi

    logInfo "Installation completed!"
    logWarn "A reboot is required to finish the installation!"
    confirm "Do you want to reboot now?"
    if [[ $? -eq 0 ]]; then
        logProcess "Alright, rebooting your system ..."
        reboot
        exit 0
    fi
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
