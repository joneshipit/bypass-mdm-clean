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

		# ── Step 1: Block ALL MDM enrollment domains ──
		info "Blocking MDM enrollment domains..."

		hosts_file="$system_path/etc/hosts"
		if [ ! -f "$hosts_file" ]; then
			warn "Hosts file does not exist, creating it"
			touch "$hosts_file" || error_exit "Failed to create hosts file"
		fi

		mdm_domains=(
			"deviceenrollment.apple.com"
			"mdmenrollment.apple.com"
			"iprofiles.apple.com"
			"acmdm.apple.com"
			"axm-adm-mdm.apple.com"
			"gdmf.apple.com"
		)

		for domain in "${mdm_domains[@]}"; do
			grep -q "$domain" "$hosts_file" 2>/dev/null || echo "0.0.0.0 $domain" >>"$hosts_file"
		done

		success "Blocked ${#mdm_domains[@]} MDM domains in hosts file"
		echo ""

		# ── Step 2: Nuke ALL MDM configuration data ──
		# Setup Assistant checks for DEP enrollment via cloudconfigurationd which
		# caches the activation record in multiple locations. We must destroy ALL
		# of them — the Settings flags, the cached activation record, AND the
		# CoreData binary store that persists enrollment state independently.

		info "Destroying all MDM configuration data..."

		config_path="$system_path/var/db/ConfigurationProfiles/Settings"
		profiles_path="$system_path/var/db/ConfigurationProfiles"

		if [ ! -d "$config_path" ]; then
			mkdir -p "$config_path" 2>/dev/null && success "Created configuration directory" || warn "Could not create configuration directory"
		fi

		# Remove ALL cloudConfig files on system volume — cached records, flags, everything
		cloudconfig_count=$(ls -1 "$config_path"/.cloudConfig* 2>/dev/null | wc -l)
		rm -rf "$config_path"/.cloudConfig* 2>/dev/null
		if [ "$cloudconfig_count" -gt 0 ]; then
			success "Removed $cloudconfig_count cloudConfig files from system volume"
		else
			info "No cloudConfig files on system volume"
		fi

		# Remove the ConfigProfiles CoreData store — this is a binary database
		# that caches compiled enrollment/policy data independently of the Settings flags
		if [ -d "$profiles_path/Store" ]; then
			rm -rf "$profiles_path/Store"/* 2>/dev/null && success "Cleared ConfigProfiles binary store (system)" || warn "Could not clear Store"
		fi

		# Remove any enrollment profiles
		rm -rf "$profiles_path"/*.enrollment* 2>/dev/null

		# Clean the data volume too — it has its own copy of everything
		data_profiles="$data_path/private/var/db/ConfigurationProfiles"
		if [ -d "$data_profiles" ]; then
			rm -rf "$data_profiles/Settings"/.cloudConfig* 2>/dev/null && success "Removed cloudConfig files from data volume" || info "No cloudConfig files on data volume"
			if [ -d "$data_profiles/Store" ]; then
				rm -rf "$data_profiles/Store"/* 2>/dev/null && success "Cleared ConfigProfiles binary store (data)" || info "No Store on data volume"
			fi
			rm -rf "$data_profiles"/*.enrollment* 2>/dev/null
		fi

		echo ""

		# ── Step 3: Disable MDM daemons ──
		# cloudconfigurationd fetches the activation record from Apple's servers
		# at boot — potentially before the hosts file is read. Disabling the
		# daemon prevents it from ever running, which is more reliable than
		# DNS blocking alone.

		info "Disabling MDM enrollment daemons..."

		launch_daemons="$system_path/System/Library/LaunchDaemons"
		launch_agents="$system_path/System/Library/LaunchAgents"
		disabled_daemons="$system_path/System/Library/LaunchDaemonsDisabled"
		disabled_agents="$system_path/System/Library/LaunchAgentsDisabled"

		# Create disabled directories
		mkdir -p "$disabled_daemons" 2>/dev/null
		mkdir -p "$disabled_agents" 2>/dev/null

		# Move ManagedClient daemons (cloudconfigurationd, enrollment, etc.)
		daemon_count=0
		for plist in "$launch_daemons"/com.apple.ManagedClient*.plist; do
			if [ -f "$plist" ]; then
				mv "$plist" "$disabled_daemons/" 2>/dev/null && daemon_count=$((daemon_count + 1))
			fi
		done
		if [ "$daemon_count" -gt 0 ]; then
			success "Disabled $daemon_count ManagedClient LaunchDaemons"
		else
			info "ManagedClient LaunchDaemons already disabled or not found"
		fi

		# Move ManagedClient agents
		agent_count=0
		for plist in "$launch_agents"/com.apple.ManagedClientAgent*.plist; do
			if [ -f "$plist" ]; then
				mv "$plist" "$disabled_agents/" 2>/dev/null && agent_count=$((agent_count + 1))
			fi
		done
		if [ "$agent_count" -gt 0 ]; then
			success "Disabled $agent_count ManagedClient LaunchAgents"
		else
			info "ManagedClient LaunchAgents already disabled or not found"
		fi

		echo ""

		# ── Step 4: Create bypass markers ──
		info "Creating MDM bypass markers..."

		touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null && success "Created profile installed marker" || warn "Could not create profile marker"
		touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null && success "Created record not found marker" || warn "Could not create not found marker"

		# Also set markers on data volume
		if [ -d "$data_profiles/Settings" ] || mkdir -p "$data_profiles/Settings" 2>/dev/null; then
			touch "$data_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
			touch "$data_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
			success "Created bypass markers on data volume"
		fi

		echo ""

		# ── Step 5: Ensure .AppleSetupDone does NOT exist ──
		# By NOT creating .AppleSetupDone and NOT creating a user, macOS will
		# boot into the normal Setup Assistant. With the MDM daemons disabled,
		# data nuked, and servers blocked, the enrollment step cannot run.

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
		echo -e "${CYAN}What was done:${NC}"
		echo -e "  • Blocked ${#mdm_domains[@]} MDM domains in /etc/hosts"
		echo -e "  • Destroyed all cached activation records & enrollment data"
		echo -e "  • Cleared ConfigProfiles binary store on both volumes"
		echo -e "  • Disabled cloudconfigurationd & enrollment daemons"
		echo -e "  • Set bypass markers on both volumes"
		echo ""
		echo -e "${CYAN}What happens next:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. macOS Setup Assistant will start normally"
		echo -e "  4. Create your account like a brand new Mac"
		echo -e "  5. The MDM enrollment step will be skipped"
		echo ""
		echo -e "${YEL}IMPORTANT: For best results, erase & reinstall macOS first,${NC}"
		echo -e "${YEL}then boot into Recovery BEFORE first setup to run this script.${NC}"
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
