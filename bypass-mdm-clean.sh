#!/bin/bash

# Bypass MDM - Clean Setup Version
# Instead of creating a temporary user, this version only blocks MDM enrollment
# and lets macOS Setup Assistant run normally so you can create your own account.
#
# Based on bypass-mdm by Assaf Dori (https://github.com/assafdori/bypass-mdm)

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

success() {
	echo -e "${GRN}✓ $1${NC}"
}

info() {
	echo -e "${BLU}ℹ $1${NC}"
}

# Function to detect system volumes
detect_volumes() {
	local system_vol=""
	local data_vol=""

	info "Detecting system volumes..." >&2

	# Look for system volume (has /System directory, not a Data volume)
	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			vol_name=$(basename "$vol")
			if [[ ! "$vol_name" =~ "Data"$ ]] && [[ ! "$vol_name" =~ "Recovery" ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"
				info "Found system volume: $system_vol" >&2
				break
			fi
		fi
	done

	# Fallback: any volume with /System directory
	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ]; then
				system_vol=$(basename "$vol")
				warn "Using volume with /System directory: $system_vol" >&2
				break
			fi
		done
	fi

	# Find data volume
	if [ -d "/Volumes/Data" ]; then
		data_vol="Data"
		info "Found data volume: $data_vol" >&2
	elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data" ]; then
		data_vol="$system_vol - Data"
		info "Found data volume: $data_vol" >&2
	else
		for vol in /Volumes/*Data; do
			if [ -d "$vol" ]; then
				data_vol=$(basename "$vol")
				warn "Found data volume: $data_vol" >&2
				break
			fi
		done
	fi

	if [ -z "$system_vol" ]; then
		error_exit "Could not detect system volume. Ensure you're in Recovery Mode with macOS installed."
	fi

	if [ -z "$data_vol" ]; then
		error_exit "Could not detect data volume. Ensure you're in Recovery Mode with macOS installed."
	fi

	echo "$system_vol|$data_vol"
}

# Detect volumes
volume_info=$(detect_volumes)
system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

# Header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Clean Setup (No Temp User)         ║${NC}"
echo -e "${CYAN}║  Based on bypass-mdm by Assaf Dori               ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume: $system_volume"
success "Data Volume: $data_volume"
echo ""

PS3='Please enter your choice: '
options=("Bypass MDM (Clean Setup)" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM (Clean Setup)")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Starting Clean MDM Bypass${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"

		# Validate paths
		info "Validating system paths..."
		[ ! -d "$system_path" ] && error_exit "System volume path does not exist: $system_path"
		[ ! -d "$data_path" ] && error_exit "Data volume path does not exist: $data_path"
		success "All system paths validated"
		echo ""

		# ── Step 1: Block MDM enrollment domains ──
		info "Blocking MDM enrollment domains..."

		hosts_file="$system_path/etc/hosts"
		if [ ! -f "$hosts_file" ]; then
			warn "Hosts file does not exist, creating it"
			touch "$hosts_file" || error_exit "Failed to create hosts file"
		fi

		grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >>"$hosts_file"
		grep -q "mdmenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com" >>"$hosts_file"
		grep -q "iprofiles.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com" >>"$hosts_file"

		success "MDM domains blocked in hosts file"
		echo ""

		# ── Step 2: Nuke ALL MDM configuration data ──
		# Remove everything first, then create only the bypass markers.
		# This is critical: the cached activation record (.cloudConfigActivationRecord)
		# is separate from the flag (.cloudConfigHasActivationRecord). If the cached
		# record exists, Setup Assistant will show the MDM pane even with the flags removed.

		info "Removing all MDM configuration data..."

		config_path="$system_path/var/db/ConfigurationProfiles/Settings"
		profiles_path="$system_path/var/db/ConfigurationProfiles"

		if [ ! -d "$config_path" ]; then
			mkdir -p "$config_path" 2>/dev/null && success "Created configuration directory" || warn "Could not create configuration directory"
		fi

		# Remove ALL cloudConfig files — cached records, flags, everything
		cloudconfig_count=$(ls -1 "$config_path"/.cloudConfig* 2>/dev/null | wc -l)
		rm -rf "$config_path"/.cloudConfig* 2>/dev/null
		if [ "$cloudconfig_count" -gt 0 ]; then
			success "Removed $cloudconfig_count cloudConfig files (including cached activation records)"
		else
			info "No cloudConfig files found"
		fi

		# Remove any enrolled configuration profiles
		rm -rf "$profiles_path"/*.enrollment* 2>/dev/null && success "Removed enrollment profiles" || info "No enrollment profiles found"

		# Remove Setup Assistant MDM state from data volume
		sa_state="$data_path/private/var/db/ConfigurationProfiles"
		if [ -d "$sa_state" ]; then
			rm -rf "$sa_state/Settings"/.cloudConfig* 2>/dev/null && success "Removed data volume cloudConfig cache" || info "No data volume cloudConfig cache"
			rm -rf "$sa_state"/*.enrollment* 2>/dev/null
		fi

		echo ""

		# ── Step 3: Create bypass markers ──
		info "Creating MDM bypass markers..."

		touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null && success "Created profile installed marker" || warn "Could not create profile marker"
		touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null && success "Created record not found marker" || warn "Could not create not found marker"

		echo ""

		# ── Step 4: Ensure .AppleSetupDone does NOT exist ──
		# By NOT creating .AppleSetupDone and NOT creating a user, macOS will
		# boot into the normal Setup Assistant. With the MDM data nuked and
		# servers blocked, the enrollment step will be skipped.

		info "Ensuring Setup Assistant will run on next boot..."

		setup_done_file="$data_path/private/var/db/.AppleSetupDone"
		if [ -f "$setup_done_file" ]; then
			info "Removing .AppleSetupDone to ensure Setup Assistant runs..."
			rm -f "$setup_done_file" 2>/dev/null && success "Removed .AppleSetupDone" || warn "Could not remove .AppleSetupDone"
		else
			success ".AppleSetupDone not present — Setup Assistant will run on boot"
		fi

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       MDM Bypass Completed Successfully!          ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}What happens next:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. macOS Setup Assistant will start normally"
		echo -e "  4. Create your account like a brand new Mac"
		echo -e "  5. The MDM enrollment step will be skipped"
		echo ""
		echo -e "${YEL}IMPORTANT: This works best on a fresh macOS install.${NC}"
		echo -e "${YEL}If Setup Assistant still shows MDM enrollment:${NC}"
		echo -e "${YEL}  1. Boot into Recovery Mode${NC}"
		echo -e "${YEL}  2. Erase the drive (Disk Utility)${NC}"
		echo -e "${YEL}  3. Reinstall macOS${NC}"
		echo -e "${YEL}  4. Boot into Recovery BEFORE first setup${NC}"
		echo -e "${YEL}  5. Run this script again${NC}"
		echo -e "${YEL}  6. Then reboot into Setup Assistant${NC}"
		echo ""
		break
		;;
	"Reboot & Exit")
		echo ""
		info "Rebooting system..."
		reboot
		break
		;;
	*)
		echo -e "${RED}Invalid option $REPLY${NC}"
		;;
	esac
done
