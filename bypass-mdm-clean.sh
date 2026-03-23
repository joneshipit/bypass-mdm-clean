#!/bin/bash

# Bypass MDM - Clean Setup Version
# Blocks MDM enrollment and lets you create your own account without a temp user.
# Two modes:
#   Option 1: Full Setup Assistant — erase/reinstall first, get the full macOS setup experience
#   Option 2: Quick Bypass — no erase needed, skips Setup Assistant, prompts for account creation
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

# ─────────────────────────────────────────────
# Shared function: block MDM domains & nuke data
# ─────────────────────────────────────────────
do_mdm_bypass() {
	local system_path="$1"
	local data_path="$2"

	# ── Block MDM enrollment domains ──
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
		warn "Hosts file not found (SSV may prevent modification)"
	fi
	echo ""

	# ── Nuke ALL MDM configuration data ──
	info "Destroying all MDM configuration data..."

	# Data volume (writable, not SSV-protected — this is what matters)
	data_profiles="$data_path/private/var/db/ConfigurationProfiles"
	if [ -d "$data_profiles" ]; then
		rm -rf "$data_profiles/Settings"/.cloudConfig* 2>/dev/null
		rm -rf "$data_profiles/Settings"/* 2>/dev/null
		rm -rf "$data_profiles/Store"/* 2>/dev/null
		rm -rf "$data_profiles"/*.enrollment* 2>/dev/null
		success "Cleared all ConfigurationProfiles data (data volume)"
	else
		mkdir -p "$data_profiles/Settings" 2>/dev/null
		info "No existing ConfigurationProfiles on data volume"
	fi

	# System volume (may be SSV-protected but try anyway)
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

	# ── Create bypass markers on BOTH volumes ──
	info "Creating MDM bypass markers..."

	mkdir -p "$data_profiles/Settings" 2>/dev/null
	touch "$data_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
	touch "$data_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
	success "Created bypass markers on data volume"

	mkdir -p "$sys_config_path" 2>/dev/null
	touch "$sys_config_path/.cloudConfigProfileInstalled" 2>/dev/null
	touch "$sys_config_path/.cloudConfigRecordNotFound" 2>/dev/null
	success "Created bypass markers on system volume"
	echo ""
}

# ─────────────────────────────────────────────
# Shared function: clean up leftover user accounts
# ─────────────────────────────────────────────
cleanup_users() {
	local data_path="$1"

	dscl_path="$data_path/private/var/db/dslocal/nodes/Default/users"
	if [ -d "$dscl_path" ]; then
		for user_plist in "$dscl_path"/*.plist; do
			if [ -f "$user_plist" ]; then
				username=$(basename "$user_plist" .plist)
				case "$username" in
				root | daemon | nobody | _* | com.apple.*)
					continue
					;;
				*)
					info "Removing leftover user account: $username"
					rm -f "$user_plist" 2>/dev/null && success "Removed $username" || warn "Could not remove $username"
					rm -rf "$data_path/Users/$username" 2>/dev/null
					;;
				esac
			fi
		done
	fi
}

# ─────────────────────────────────────────────
# Shared function: install reset protection for first boot
# ─────────────────────────────────────────────
install_reset_protection() {
	local data_path="$1"

	echo ""
	echo -e "${CYAN}Would you like to automatically prevent factory reset?${NC}"
	echo -e "${BLU}This silently blocks 'Erase All Content and Settings' after first boot.${NC}"
	echo -e "${BLU}The option will look normal but just won't work.${NC}"
	echo -e "${BLU}(See: github.com/joneshipit/prevent-reset)${NC}"
	echo ""
	read -p "Install reset protection? (y/n): " install_rp

	if [ "$install_rp" != "y" ] && [ "$install_rp" != "Y" ]; then
		info "Skipped reset protection"
		return
	fi

	info "Installing reset protection for first boot..."

	# Create the blocker script on the data volume
	local bin_dir="$data_path/usr/local/bin"
	mkdir -p "$bin_dir" 2>/dev/null

	cat > "$bin_dir/block-erase.sh" << 'BLOCKERSCRIPT'
#!/bin/bash
pkill -9 -f "Erase Assistant" 2>/dev/null
pkill -9 -f "erasetool" 2>/dev/null
pkill -9 -f "systemreset" 2>/dev/null
BLOCKERSCRIPT
	chmod +x "$bin_dir/block-erase.sh"
	success "Created erase blocker script"

	# Create the LaunchDaemons on the data volume
	local daemon_dir="$data_path/Library/LaunchDaemons"
	mkdir -p "$daemon_dir" 2>/dev/null

	# Event-driven daemon (WatchPaths)
	cat > "$daemon_dir/com.joneshipit.block-erase.plist" << 'WATCHDAEMON'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.joneshipit.block-erase</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>/usr/local/bin/block-erase.sh</string>
	</array>
	<key>WatchPaths</key>
	<array>
		<string>/System/Library/CoreServices/Erase Assistant.app</string>
	</array>
</dict>
</plist>
WATCHDAEMON

	# Fallback daemon (5s interval)
	cat > "$daemon_dir/com.joneshipit.block-erase-fallback.plist" << 'FALLDAEMON'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.joneshipit.block-erase-fallback</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>/usr/local/bin/block-erase.sh</string>
	</array>
	<key>StartInterval</key>
	<integer>5</integer>
</dict>
</plist>
FALLDAEMON

	# Set permissions
	chown root:wheel "$daemon_dir/com.joneshipit.block-erase.plist" 2>/dev/null
	chmod 644 "$daemon_dir/com.joneshipit.block-erase.plist" 2>/dev/null
	chown root:wheel "$daemon_dir/com.joneshipit.block-erase-fallback.plist" 2>/dev/null
	chmod 644 "$daemon_dir/com.joneshipit.block-erase-fallback.plist" 2>/dev/null

	success "Reset protection will activate automatically on first boot"
	echo -e "  ${BLU}To undo later: github.com/joneshipit/prevent-reset (unlock script)${NC}"
}

# ─────────────────────────────────────────────
# Detect volumes
# ─────────────────────────────────────────────
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
echo -e "${CYAN}Choose a bypass method:${NC}"
echo ""
echo -e "  ${GRN}1) Full Setup Assistant${NC}"
echo -e "     Removes .AppleSetupDone so macOS runs the complete Setup Assistant."
echo -e "     You get the full new-Mac experience (Apple ID, Siri, Touch ID, etc)."
echo -e "     ${YEL}⚠ Best on a fresh erase/reinstall. May show MDM error on cached systems.${NC}"
echo ""
echo -e "  ${GRN}2) Quick Bypass (Recommended)${NC}"
echo -e "     Creates .AppleSetupDone with no users. macOS skips Setup Assistant"
echo -e "     entirely (including MDM) and just prompts you to create an account."
echo -e "     ${GRN}✓ Works without erase/reinstall. No MDM pane at all.${NC}"
echo ""
echo -e "  ${GRN}3) Reboot & Exit${NC}"
echo ""

PS3='Please enter your choice: '
options=("Full Setup Assistant" "Quick Bypass (Recommended)" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in

	# ═══════════════════════════════════════════════════
	# OPTION 1: Full Setup Assistant
	# ═══════════════════════════════════════════════════
	"Full Setup Assistant")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Full Setup Assistant Mode${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"

		info "Validating system paths..."
		[ ! -d "$system_path" ] && error_exit "System volume path does not exist: $system_path"
		[ ! -d "$data_path" ] && error_exit "Data volume path does not exist: $data_path"
		success "All system paths validated"
		echo ""

		# Run shared MDM bypass
		do_mdm_bypass "$system_path" "$data_path"

		# Clean up leftover users
		cleanup_users "$data_path"

		# Remove .AppleSetupDone so full Setup Assistant runs
		info "Ensuring full Setup Assistant will run on next boot..."

		setup_done_file="$data_path/private/var/db/.AppleSetupDone"
		if [ -f "$setup_done_file" ]; then
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
		echo -e "  4. Create your account with Apple ID, Touch ID, Siri, etc."
		echo -e "  5. The MDM enrollment step should be skipped"
		echo ""
		echo -e "${YEL}⚠ If you still see the Remote Management screen, reboot${NC}"
		echo -e "${YEL}  into Recovery and try Option 2 (Quick Bypass) instead.${NC}"

		# Offer reset protection
		install_reset_protection "$data_path"

		echo ""
		break
		;;

	# ═══════════════════════════════════════════════════
	# OPTION 2: Quick Bypass (no-user trick)
	# ═══════════════════════════════════════════════════
	"Quick Bypass (Recommended)")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Quick Bypass Mode${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"

		info "Validating system paths..."
		[ ! -d "$system_path" ] && error_exit "System volume path does not exist: $system_path"
		[ ! -d "$data_path" ] && error_exit "Data volume path does not exist: $data_path"
		success "All system paths validated"
		echo ""

		# Run shared MDM bypass
		do_mdm_bypass "$system_path" "$data_path"

		# Clean up leftover users
		cleanup_users "$data_path"

		# Create .AppleSetupDone WITHOUT any user accounts
		# macOS sees "setup done" → skips full Setup Assistant (including MDM pane)
		# macOS detects no users → runs reduced Setup Assistant for account creation only
		info "Setting up .AppleSetupDone (no-user trick)..."

		setup_done_dir="$data_path/private/var/db"
		mkdir -p "$setup_done_dir" 2>/dev/null
		touch "$setup_done_dir/.AppleSetupDone" 2>/dev/null && success "Created .AppleSetupDone" || warn "Could not create .AppleSetupDone"

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       MDM Bypass Completed Successfully!          ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}What happens next:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. macOS will detect no user accounts and prompt you to create one"
		echo -e "  4. Create your account — this is YOUR account, not a temp user"
		echo -e "  5. The MDM Remote Management step will not appear"
		echo ""
		echo -e "${YEL}Note: Set up Apple ID, Touch ID, and Siri from${NC}"
		echo -e "${YEL}System Settings after you log in.${NC}"

		# Offer reset protection
		install_reset_protection "$data_path"

		echo ""
		break
		;;

	# ═══════════════════════════════════════════════════
	# OPTION 3: Reboot & Exit
	# ═══════════════════════════════════════════════════
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
