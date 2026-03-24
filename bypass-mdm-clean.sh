#!/bin/bash

# Bypass MDM - Clean Setup (Step 1 of 2)
# Run from Recovery Mode. Creates a temporary user to boot the system,
# then Step 2 (run from within macOS) locks down MDM permanently and
# removes the temp user so Setup Assistant runs clean.
#
# Based on bypass-mdm by Assaf Dori (https://github.com/assafdori/bypass-mdm)

set -o pipefail

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
warn() { echo -e "${YEL}WARNING: $1${NC}"; }
success() { echo -e "${GRN}✓ $1${NC}"; }
info() { echo -e "${BLU}ℹ $1${NC}"; }

# ─────────────────────────────────────────────
# Detect system volumes
# ─────────────────────────────────────────────
detect_volumes() {
	local system_vol="" data_vol=""
	info "Detecting system volumes..." >&2

	# Use nullglob so empty globs produce no iterations
	local _old_nullglob
	_old_nullglob=$(shopt -p nullglob 2>/dev/null) || true
	shopt -s nullglob

	for vol in /Volumes/*; do
		[ -d "$vol" ] || continue
		vol_name=$(basename "$vol")
		# Unquoted regex RHS — required for bash 3.2 (macOS Recovery)
		if [[ ! "$vol_name" =~ Data$ ]] && [[ ! "$vol_name" =~ Recovery ]] && [ -d "$vol/System" ]; then
			system_vol="$vol_name"
			info "Found system volume: $system_vol" >&2
			break
		fi
	done

	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ]; then
				system_vol=$(basename "$vol")
				warn "Using volume with /System directory: $system_vol" >&2
				break
			fi
		done
	fi

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

	# Restore nullglob
	eval "$_old_nullglob" 2>/dev/null || true

	[ -z "$system_vol" ] && error_exit "Could not detect system volume. Ensure you're in Recovery Mode with macOS installed."
	[ -z "$data_vol" ] && error_exit "Could not detect data volume. Ensure you're in Recovery Mode with macOS installed."

	echo "$system_vol|$data_vol"
}

# Detect volumes
volume_info=$(detect_volumes)
IFS='|' read -r system_volume data_volume <<< "$volume_info"

# Header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Clean Setup (Step 1 of 2)          ║${NC}"
echo -e "${CYAN}║  Run from Recovery Mode                          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume: $system_volume"
success "Data Volume: $data_volume"
echo ""
echo -e "${CYAN}This creates a temporary user to boot the system.${NC}"
echo -e "${CYAN}After logging in, run Step 2 to finish the bypass${NC}"
echo -e "${CYAN}and get a clean Setup Assistant experience.${NC}"
echo ""

PS3='Please enter your choice: '
options=("Bypass MDM (Step 1)" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM (Step 1)")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Step 1: Recovery Mode Setup${NC}"
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

		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"

		# ── Block MDM domains (best effort from Recovery) ──
		# NOTE: On SSV-protected macOS (Big Sur+), these writes to the system
		# volume will be invisible after boot. Step 2 handles this properly
		# by writing from within the running OS.
		info "Blocking MDM enrollment domains (best effort — Step 2 makes this permanent)..."
		hosts_file="$system_path/etc/hosts"
		mdm_domains=(
			"deviceenrollment.apple.com"
			"mdmenrollment.apple.com"
			"iprofiles.apple.com"
			"acmdm.apple.com"
			"axm-adm-mdm.apple.com"
			"axm-adm-enroll.apple.com"
			"albert.apple.com"
			"identity.apple.com"
		)
		if [ -f "$hosts_file" ]; then
			for domain in "${mdm_domains[@]}"; do
				grep -qF "$domain" "$hosts_file" 2>/dev/null || echo "0.0.0.0 $domain" >>"$hosts_file"
			done
			success "Blocked ${#mdm_domains[@]} MDM domains in hosts file (best effort)"
		else
			warn "Hosts file not found (SSV prevents this — Step 2 will handle it)"
		fi
		echo ""

		# ── Nuke MDM configuration data ──
		info "Destroying MDM configuration data..."

		data_profiles="$data_path/private/var/db/ConfigurationProfiles"
		if [ -d "$data_profiles" ]; then
			rm -rf "$data_profiles/Settings"/.cloudConfig* 2>/dev/null
			rm -rf "$data_profiles/Settings"/* 2>/dev/null
			rm -rf "$data_profiles/Store"/* 2>/dev/null
			rm -rf "$data_profiles"/*.enrollment* 2>/dev/null
			success "Cleared ConfigurationProfiles (data volume)"
		else
			mkdir -p "$data_profiles/Settings" || error_exit "Failed to create ConfigurationProfiles directory"
			info "No existing ConfigurationProfiles on data volume"
		fi

		sys_profiles="$system_path/var/db/ConfigurationProfiles"
		if [ -d "$sys_profiles" ]; then
			rm -rf "$sys_profiles/Settings"/* 2>/dev/null
			rm -rf "$sys_profiles/Store"/* 2>/dev/null
			success "Cleared ConfigurationProfiles (system volume)"
		fi
		echo ""

		# ── Create bypass markers ──
		info "Creating MDM bypass markers..."
		mkdir -p "$data_profiles/Settings" || error_exit "Failed to create Settings directory"
		touch "$data_profiles/Settings/.cloudConfigProfileInstalled" || error_exit "Failed to create bypass marker"
		touch "$data_profiles/Settings/.cloudConfigRecordNotFound" || error_exit "Failed to create bypass marker"
		success "Created bypass markers"
		echo ""

		# ── Create temporary user ──
		info "Creating temporary user account..."
		echo -e "${BLU}This account is just to boot the system. Step 2 will delete it.${NC}"
		echo ""

		tmp_user="tmpsetup"
		tmp_pass="1234"

		# Find available UID using PlistBuddy (reliable plist array parsing)
		last_uid=500
		if [ -d "$dscl_path/users" ]; then
			shopt -s nullglob
			for plist in "$dscl_path/users"/*.plist; do
				[ -f "$plist" ] || continue
				# PlistBuddy correctly reads the uid array element
				uid_val=$(/usr/libexec/PlistBuddy -c "Print :uid:0" "$plist" 2>/dev/null)
				if [ -n "$uid_val" ] && [ "$uid_val" -gt "$last_uid" ] 2>/dev/null; then
					last_uid=$uid_val
				fi
			done
			shopt -u nullglob
		fi
		new_uid=$((last_uid + 1))
		info "Assigning UID $new_uid to temporary user"

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" \
			|| error_exit "Failed to create user record — is the data volume writable?"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" UserShell "/bin/zsh" \
			|| error_exit "Failed to set user shell"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" RealName "Temporary Setup" \
			|| error_exit "Failed to set user RealName"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" UniqueID "$new_uid" \
			|| error_exit "Failed to set user UID"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" PrimaryGroupID "20" \
			|| error_exit "Failed to set user group"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" NFSHomeDirectory "/Users/$tmp_user" \
			|| error_exit "Failed to set user home directory"
		dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$tmp_user" "$tmp_pass" \
			|| warn "Password set may have failed — if login fails, try Recovery again"
		dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$tmp_user" \
			|| warn "Failed to add user to admin group"
		mkdir -p "$data_path/Users/$tmp_user" || error_exit "Failed to create user home directory"

		success "Created temporary user: $tmp_user (password: $tmp_pass)"
		echo ""

		# ── Embed Step 2 script on the desktop ──
		info "Embedding Step 2 script on the desktop..."
		step2_dir="$data_path/Users/$tmp_user/Desktop"
		mkdir -p "$step2_dir" || error_exit "Failed to create Desktop directory"
		# Copy step2 from the same source (if available alongside this script)
		script_dir="$(cd "$(dirname "$0")" && pwd)"
		if [ -f "$script_dir/step2-clean-setup.sh" ]; then
			cp "$script_dir/step2-clean-setup.sh" "$step2_dir/step2.sh" \
				|| error_exit "Failed to copy Step 2 script"
			chmod +x "$step2_dir/step2.sh"
			success "Step 2 script placed on desktop (no download needed)"
		else
			info "Step 2 script not found alongside Step 1 — user will need to download it"
		fi
		echo ""

		# ── Mark setup as done ──
		touch "$data_path/private/var/db/.AppleSetupDone" || error_exit "Failed to create .AppleSetupDone"
		success "Created .AppleSetupDone"
		echo ""

		# ── Done ──
		echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       Step 1 Complete!                            ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. Log in as: ${GRN}$tmp_user${NC} / password: ${GRN}$tmp_pass${NC}"
		echo -e "  4. Skip all setup prompts (click 'Set Up Later' / 'Not Now')"
		echo -e "  5. Once on the desktop, open ${GRN}Terminal${NC}"
		if [ -f "$step2_dir/step2.sh" ]; then
			echo -e "  6. Run: ${YEL}sudo ~/Desktop/step2.sh${NC}"
		else
			echo -e "  6. Run this command:"
			echo ""
			echo -e "  ${YEL}curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh${NC}"
		fi
		echo ""
		echo -e "  7. The Mac will reboot into a clean Setup Assistant"
		echo -e "     — create your real account with Apple ID, Touch ID, etc."
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
