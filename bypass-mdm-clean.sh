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
# Normalize the Data volume to /Volumes/Data
# This is the proven approach from assafdori/bypass-mdm:
# rename whatever the Data volume is called to "Data"
# so all paths are predictable.
# ─────────────────────────────────────────────
if [ -d "/Volumes/Macintosh HD - Data" ]; then
	diskutil rename "Macintosh HD - Data" "Data"
elif [ ! -d "/Volumes/Data" ]; then
	# Try to find any volume ending in "Data" and rename it
	for vol in /Volumes/*Data; do
		if [ -d "$vol" ] && [ "$vol" != "/Volumes/Data" ]; then
			vol_name=$(basename "$vol")
			diskutil rename "$vol_name" "Data" 2>/dev/null && break
		fi
	done
fi

# At this point /Volumes/Data must exist
[ ! -d "/Volumes/Data" ] && error_exit "Could not find or create /Volumes/Data. Is macOS installed?"

# Header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Clean Setup (Step 1 of 2)          ║${NC}"
echo -e "${CYAN}║  Run from Recovery Mode                          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
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

		# All paths are hardcoded to /Volumes/Data — proven to work
		dscl_path="/Volumes/Data/private/var/db/dslocal/nodes/Default"

		# ── Block MDM domains (best effort from Recovery) ──
		# NOTE: On SSV-protected macOS (Big Sur+), these writes to the system
		# volume will be invisible after boot. Step 2 handles this properly
		# by writing from within the running OS.
		info "Blocking MDM enrollment domains (best effort — Step 2 makes this permanent)..."
		hosts_file="/Volumes/Macintosh HD/etc/hosts"
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

		# Data volume profiles
		data_profiles="/Volumes/Data/private/var/db/ConfigurationProfiles"
		if [ -d "$data_profiles" ]; then
			rm -rf "$data_profiles/Settings"/.cloudConfig* 2>/dev/null
			rm -rf "$data_profiles/Settings"/* 2>/dev/null
			rm -rf "$data_profiles/Store"/* 2>/dev/null
			rm -rf "$data_profiles"/*.enrollment* 2>/dev/null
			success "Cleared ConfigurationProfiles (data volume)"
		fi

		# System volume profiles
		sys_profiles="/Volumes/Macintosh HD/var/db/ConfigurationProfiles"
		if [ -d "$sys_profiles" ]; then
			rm -rf "$sys_profiles/Settings/.cloudConfigHasActivationRecord" 2>/dev/null
			rm -rf "$sys_profiles/Settings/.cloudConfigRecordFound" 2>/dev/null
			rm -rf "$sys_profiles/Settings"/* 2>/dev/null
			rm -rf "$sys_profiles/Store"/* 2>/dev/null
			success "Cleared ConfigurationProfiles (system volume)"
		fi
		echo ""

		# ── Create bypass markers ──
		info "Creating MDM bypass markers..."
		mkdir -p "$data_profiles/Settings" 2>/dev/null
		touch "$data_profiles/Settings/.cloudConfigProfileInstalled" || warn "Could not create bypass marker on data volume"
		touch "$data_profiles/Settings/.cloudConfigRecordNotFound" || warn "Could not create bypass marker on data volume"
		# Also on system volume (matches assafdori approach)
		if [ -d "$sys_profiles/Settings" ] || mkdir -p "$sys_profiles/Settings" 2>/dev/null; then
			touch "$sys_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
			touch "$sys_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
		fi
		success "Created bypass markers"
		echo ""

		# ── Create temporary user ──
		info "Creating temporary user account..."

		tmp_user="tmpsetup"
		tmp_pass="1234"

		# Create home directory first (matches assafdori order)
		mkdir -p "/Volumes/Data/Users/$tmp_user"

		# Create user via dscl — same commands as assafdori/bypass-mdm
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" UserShell "/bin/zsh"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" RealName "Temporary Setup"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" UniqueID "501"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" PrimaryGroupID "20"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$tmp_user" NFSHomeDirectory "/Users/$tmp_user"
		dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$tmp_user" "$tmp_pass"
		dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$tmp_user"

		success "Created temporary user: $tmp_user (password: $tmp_pass)"
		echo ""

		# ── Mark setup as done ──
		touch "/Volumes/Data/private/var/db/.AppleSetupDone"
		success "Created .AppleSetupDone"
		echo ""

		# ── Embed Step 2 script on the desktop ──
		step2_dir="/Volumes/Data/Users/$tmp_user/Desktop"
		mkdir -p "$step2_dir" 2>/dev/null
		script_dir="$(cd "$(dirname "$0")" && pwd)"
		if [ -f "$script_dir/step2-clean-setup.sh" ]; then
			cp "$script_dir/step2-clean-setup.sh" "$step2_dir/step2.sh"
			chmod +x "$step2_dir/step2.sh"
			success "Step 2 script placed on desktop"
		fi

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
