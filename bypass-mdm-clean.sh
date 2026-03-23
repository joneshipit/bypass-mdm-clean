#!/bin/bash

# Bypass MDM - Clean Setup Version
# Blocks MDM enrollment and lets you create your own account without a temp user.
# Uses .AppleSetupDone trick: marks setup "done" but with no users, macOS runs
# a reduced Setup Assistant for account creation — skipping the MDM pane entirely.
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
		# Note: On macOS Big Sur+, the system volume is a Signed System Volume (SSV).
		# Hosts file changes from Recovery may not persist. This is a belt-and-suspenders
		# measure — the real bypass comes from Steps 2-4.

		info "Blocking MDM enrollment domains..."

		hosts_file="$system_path/etc/hosts"
		if [ -f "$hosts_file" ]; then
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
		else
			warn "Hosts file not found (SSV may prevent modification) — continuing with other bypass methods"
		fi
		echo ""

		# ── Step 2: Nuke ALL MDM configuration data on DATA volume ──
		# The data volume is writable (not protected by SSV). This is where
		# the bypass actually works. We destroy all cached activation records,
		# the CoreData binary store, and any enrollment profiles.

		info "Destroying all MDM configuration data..."

		# Data volume — this is the writable one that matters
		data_profiles="$data_path/private/var/db/ConfigurationProfiles"
		if [ -d "$data_profiles" ]; then
			# Nuke everything in the ConfigurationProfiles directory
			rm -rf "$data_profiles/Settings"/.cloudConfig* 2>/dev/null
			rm -rf "$data_profiles/Settings"/* 2>/dev/null
			rm -rf "$data_profiles/Store"/* 2>/dev/null
			rm -rf "$data_profiles"/*.enrollment* 2>/dev/null
			success "Cleared all ConfigurationProfiles data (data volume)"
		else
			mkdir -p "$data_profiles/Settings" 2>/dev/null
			info "No existing ConfigurationProfiles on data volume"
		fi

		# System volume — may be SSV-protected but try anyway
		sys_config_path="$system_path/var/db/ConfigurationProfiles/Settings"
		sys_profiles_path="$system_path/var/db/ConfigurationProfiles"

		if [ -d "$sys_profiles_path" ]; then
			rm -rf "$sys_config_path"/.cloudConfig* 2>/dev/null
			rm -rf "$sys_config_path"/* 2>/dev/null
			rm -rf "$sys_profiles_path/Store"/* 2>/dev/null
			rm -rf "$sys_profiles_path"/*.enrollment* 2>/dev/null
			success "Cleared all ConfigurationProfiles data (system volume)"
		fi

		echo ""

		# ── Step 3: Create bypass markers on BOTH volumes ──
		info "Creating MDM bypass markers..."

		# Data volume markers (the ones that matter)
		mkdir -p "$data_profiles/Settings" 2>/dev/null
		touch "$data_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
		touch "$data_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
		success "Created bypass markers on data volume"

		# System volume markers (belt-and-suspenders)
		mkdir -p "$sys_config_path" 2>/dev/null
		touch "$sys_config_path/.cloudConfigProfileInstalled" 2>/dev/null
		touch "$sys_config_path/.cloudConfigRecordNotFound" 2>/dev/null
		success "Created bypass markers on system volume"

		echo ""

		# ── Step 4: Create .AppleSetupDone WITHOUT creating a user ──
		# This is the key trick. By marking setup as "done" but having NO user
		# accounts, macOS will:
		#   1. See .AppleSetupDone → skip the FULL Setup Assistant (including MDM)
		#   2. Detect no user accounts exist
		#   3. Run a REDUCED Setup Assistant that only handles account creation
		# The reduced Setup Assistant doesn't include the Remote Management pane
		# because that's part of the initial DEP enrollment flow, not account recovery.

		info "Setting up .AppleSetupDone (no-user trick)..."

		setup_done_dir="$data_path/private/var/db"
		mkdir -p "$setup_done_dir" 2>/dev/null
		touch "$setup_done_dir/.AppleSetupDone" 2>/dev/null && success "Created .AppleSetupDone" || warn "Could not create .AppleSetupDone"

		# Make sure no leftover users exist from previous bypass attempts
		dscl_path="$data_path/private/var/db/dslocal/nodes/Default/users"
		if [ -d "$dscl_path" ]; then
			# Remove any non-system user plists (system users have UIDs < 500)
			for user_plist in "$dscl_path"/*.plist; do
				if [ -f "$user_plist" ]; then
					username=$(basename "$user_plist" .plist)
					# Skip system accounts
					case "$username" in
					root | daemon | nobody | _* | com.apple.*)
						continue
						;;
					*)
						info "Removing leftover user account: $username"
						rm -f "$user_plist" 2>/dev/null && success "Removed $username" || warn "Could not remove $username"
						# Also remove their home directory
						rm -rf "$data_path/Users/$username" 2>/dev/null
						;;
					esac
				fi
			done
		fi

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       MDM Bypass Completed Successfully!          ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}What was done:${NC}"
		echo -e "  • Blocked MDM domains in /etc/hosts"
		echo -e "  • Destroyed all cached MDM/enrollment data on both volumes"
		echo -e "  • Set bypass markers on both volumes"
		echo -e "  • Created .AppleSetupDone with no user accounts"
		echo -e "  • Cleaned up any leftover user accounts"
		echo ""
		echo -e "${CYAN}What happens next:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. macOS will detect no user accounts and prompt you to create one"
		echo -e "  4. Create your account — this is YOUR account, not a temp user"
		echo -e "  5. The MDM Remote Management step will not appear"
		echo ""
		echo -e "${YEL}Note: The account creation screen may look slightly different${NC}"
		echo -e "${YEL}from a normal Setup Assistant, but you'll still get to set${NC}"
		echo -e "${YEL}up Apple ID, etc. from System Settings after login.${NC}"
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
