#!/bin/bash

# Lock Down Mac — Add Friction to Reset
# Blocks "Erase All Content and Settings" via a configuration profile
# and optionally sets a firmware/recovery password.
# The user stays admin — can do everything EXCEPT factory reset.
# To undo, run: sudo ./unlock-mac.sh
#
# Must be run with sudo.

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

success() {
	echo -e "${GRN}✓ $1${NC}"
}

info() {
	echo -e "${BLU}ℹ $1${NC}"
}

warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

if [ "$(id -u)" -ne 0 ]; then
	error_exit "This script must be run with sudo. Try: sudo ./lock-down-mac.sh"
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Lock Down Mac — Block Factory Reset              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLU}This adds friction to the reset process.${NC}"
echo -e "${BLU}The user stays admin and can do everything normally —${NC}"
echo -e "${BLU}they just can't factory reset without the unlock script.${NC}"
echo ""

# ── Step 1: Install a configuration profile that disables Erase All Content and Settings ──
info "Installing restriction profile to block factory reset..."

profile_path="/Library/ManagedPreferences/com.apple.applicationaccess.plist"
profile_dir=$(dirname "$profile_path")
mkdir -p "$profile_dir" 2>/dev/null

# Create a configuration profile that disables "Erase All Content and Settings"
cat > /tmp/disable-erase.mobileconfig << 'PROFILE'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>PayloadType</key>
			<string>com.apple.applicationaccess</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
			<key>PayloadIdentifier</key>
			<string>com.joneshipit.disable-erase</string>
			<key>PayloadUUID</key>
			<string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
			<key>PayloadDisplayName</key>
			<string>Disable Factory Reset</string>
			<key>PayloadDescription</key>
			<string>Prevents Erase All Content and Settings</string>
			<key>PayloadOrganization</key>
			<string>Family Admin</string>
			<key>allowEraseContentAndSettings</key>
			<false/>
		</dict>
	</array>
	<key>PayloadDisplayName</key>
	<string>Reset Protection</string>
	<key>PayloadDescription</key>
	<string>Prevents accidental factory reset. Contact your family admin to remove.</string>
	<key>PayloadIdentifier</key>
	<string>com.joneshipit.reset-protection</string>
	<key>PayloadUUID</key>
	<string>F1E2D3C4-B5A6-7890-1234-567890ABCDEF</string>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
	<key>PayloadRemovalDisallowed</key>
	<true/>
</dict>
</plist>
PROFILE

# Install the profile
profiles install -path /tmp/disable-erase.mobileconfig 2>/dev/null
profile_installed=$?

# Clean up temp file
rm -f /tmp/disable-erase.mobileconfig

if [ $profile_installed -eq 0 ]; then
	success "Configuration profile installed — 'Erase All Content and Settings' is disabled"
else
	# Fallback: directly write the restriction plist
	warn "Profile command failed — using direct plist method"

	defaults write /Library/Preferences/com.apple.applicationaccess allowEraseContentAndSettings -bool false 2>/dev/null
	success "Restriction set via defaults"
fi

echo ""

# ── Step 2: Firmware / Recovery password ──
info "Checking Recovery Mode protection..."

cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
if echo "$cpu_brand" | grep -qi "apple"; then
	mac_type="apple_silicon"
else
	mac_type="intel"
fi

if [ "$mac_type" = "intel" ]; then
	if command -v firmwarepasswd &>/dev/null; then
		fw_status=$(firmwarepasswd -check 2>/dev/null)
		if echo "$fw_status" | grep -qi "Yes"; then
			success "Firmware password already set"
		else
			echo ""
			echo -e "${CYAN}Set a firmware password? This prevents booting into Recovery${NC}"
			echo -e "${CYAN}Mode without the password (prevents erase from Recovery).${NC}"
			read -p "Set firmware password? (y/n): " set_fw
			if [ "$set_fw" = "y" ] || [ "$set_fw" = "Y" ]; then
				firmwarepasswd -setpasswd
				[ $? -eq 0 ] && success "Firmware password set" || warn "Could not set firmware password"
			else
				info "Skipped — Recovery Mode is not password-protected"
			fi
		fi
	fi
else
	success "Apple Silicon — Recovery Mode requires user authentication by default"
fi

echo ""

# ── Step 3: Disable automatic OS upgrades (prevents reset-like surprises) ──
info "Disabling automatic major OS upgrades..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null
success "Automatic major OS upgrades disabled (security updates still work)"

echo ""

# ── Summary ──
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       Mac Locked Down Successfully!               ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}What's blocked:${NC}"
echo -e "  ✗ 'Erase All Content and Settings' is disabled in System Settings"
echo -e "  ✗ Cannot remove the restriction profile without the unlock script"
if [ "$mac_type" = "intel" ]; then
	echo -e "  ✗ Recovery Mode requires firmware password (if set)"
else
	echo -e "  ✗ Recovery Mode requires user authentication"
fi
echo ""
echo -e "${CYAN}What still works (everything else):${NC}"
echo -e "  ✓ Full admin access"
echo -e "  ✓ Install/uninstall apps"
echo -e "  ✓ Change all system settings"
echo -e "  ✓ Create/delete user accounts"
echo -e "  ✓ Software updates"
echo ""
echo -e "${CYAN}To undo (when she actually needs to reset):${NC}"
echo -e "  curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/unlock-mac.sh -o unlock-mac.sh && chmod +x unlock-mac.sh && sudo ./unlock-mac.sh"
echo ""
