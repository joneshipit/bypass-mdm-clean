#!/bin/bash

# Bypass MDM - Clean Setup (Step 1 of 2)
# Run from Recovery Mode. Creates a temporary user to boot the system,
# then Step 2 (run from within macOS) locks down MDM permanently and
# removes the temp user so Setup Assistant runs clean.
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
warn() { echo -e "${YEL}WARNING: $1${NC}"; }
success() { echo -e "${GRN}✓ $1${NC}"; }
info() { echo -e "${BLU}ℹ $1${NC}"; }

# ─────────────────────────────────────────────
# Detect system volumes
# ─────────────────────────────────────────────
detect_volumes() {
	local system_vol="" data_vol=""
	info "Detecting system volumes..." >&2

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

	[ -z "$system_vol" ] && error_exit "Could not detect system volume. Ensure you're in Recovery Mode with macOS installed."
	[ -z "$data_vol" ] && error_exit "Could not detect data volume. Ensure you're in Recovery Mode with macOS installed."

	echo "$system_vol|$data_vol"
}

# Detect volumes
volume_info=$(detect_volumes)
system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

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

		# ── Block MDM domains (best effort from Recovery) ──
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
			warn "Hosts file not found (SSV may prevent — Step 2 will handle this)"
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
			mkdir -p "$data_profiles/Settings" 2>/dev/null
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
		mkdir -p "$data_profiles/Settings" 2>/dev/null
		touch "$data_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
		touch "$data_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
		success "Created bypass markers"
		echo ""

		# ── Create temporary user ──
		info "Creating temporary user account..."
		echo -e "${BLU}This account is just to boot the system. Step 2 will delete it.${NC}"
		echo ""

		tmp_user="tmpsetup"
		tmp_pass="1234"
		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"

		# Find available UID
		last_uid=500
		if [ -d "$dscl_path/users" ]; then
			for plist in "$dscl_path/users"/*.plist; do
				[ -f "$plist" ] || continue
				# Simple UID extraction — look for integer after UniqueID
				uid_val=$(defaults read "$plist" uid 2>/dev/null | head -1)
				if [ -n "$uid_val" ] && [ "$uid_val" -gt "$last_uid" ] 2>/dev/null; then
					last_uid=$uid_val
				fi
			done
		fi
		new_uid=$((last_uid + 1))

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" UserShell "/bin/zsh"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" RealName "Temporary Setup"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" UniqueID "$new_uid"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" PrimaryGroupID "20"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" NFSHomeDirectory "/Users/$tmp_user"
		dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$tmp_user" "$tmp_pass"
		dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$tmp_user"
		mkdir -p "$data_path/Users/$tmp_user" 2>/dev/null

		success "Created temporary user: $tmp_user (password: $tmp_pass)"
		echo ""

		# ── Mark setup as done ──
		touch "$data_path/private/var/db/.AppleSetupDone" 2>/dev/null
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
		echo -e "  6. Run this command:"
		echo ""
		echo -e "  ${YEL}curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh${NC}"
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
