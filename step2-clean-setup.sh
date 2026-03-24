#!/bin/bash

# Bypass MDM - Clean Setup (Step 2 of 2)
# Run from within macOS (as the temp user from Step 1).
# This script:
#   1. Permanently blocks MDM domains in /etc/hosts (from within the OS,
#      bypassing SSV issues that plague Recovery-only approaches)
#   2. Nukes all MDM configuration data and sets bypass markers
#   3. Installs a hosts guard daemon for boot persistence
#   4. Optionally installs reset protection (prevent-reset)
#   5. Deletes the temporary user account
#   6. Removes .AppleSetupDone
#   7. Reboots into a clean Setup Assistant — no MDM, no temp user
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
warn() { echo -e "${YEL}WARNING: $1${NC}"; }
success() { echo -e "${GRN}✓ $1${NC}"; }
info() { echo -e "${BLU}ℹ $1${NC}"; }

# Must be root
if [ "$(id -u)" -ne 0 ]; then
	error_exit "This script must be run with sudo. Try: sudo ./step2.sh"
fi

# Header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Clean Setup (Step 2 of 2)          ║${NC}"
echo -e "${CYAN}║  Run from within macOS                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}This will:${NC}"
echo -e "  • Permanently block MDM domains"
echo -e "  • Install MDM hosts guard daemon"
echo -e "  • Delete the temporary user account"
echo -e "  • Remove .AppleSetupDone"
echo -e "  • Reboot into clean Setup Assistant"
echo ""
echo -e "${YEL}After reboot, you'll go through the full macOS setup${NC}"
echo -e "${YEL}experience — Apple ID, Touch ID, Siri — without MDM.${NC}"
echo ""
read -p "Continue? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
	echo "Aborted."
	exit 0
fi

echo ""

# ── Step 1: Block MDM domains in /etc/hosts (FROM WITHIN THE OS) ──
# This is the key difference from Recovery-only approaches.
# Writing to /etc/hosts from a running macOS goes through the firmlink
# to the data volume — it actually persists, unlike Recovery which
# writes to the SSV-protected system volume.

info "Blocking MDM domains in /etc/hosts..."

mdm_domains=(
	"deviceenrollment.apple.com"
	"mdmenrollment.apple.com"
	"iprofiles.apple.com"
	"acmdm.apple.com"
	"axm-adm-mdm.apple.com"
	"gdmf.apple.com"
)

for domain in "${mdm_domains[@]}"; do
	grep -q "$domain" /etc/hosts 2>/dev/null || echo "0.0.0.0 $domain" >>/etc/hosts
done
success "Blocked ${#mdm_domains[@]} MDM domains (persistent — written from within OS)"
echo ""

# ── Step 2: Nuke all MDM configuration data ──
info "Destroying all MDM configuration data..."

config_settings="/var/db/ConfigurationProfiles/Settings"
config_profiles="/var/db/ConfigurationProfiles"

if [ -d "$config_profiles" ]; then
	rm -rf "$config_settings"/.cloudConfig* 2>/dev/null
	rm -rf "$config_settings"/* 2>/dev/null
	rm -rf "$config_profiles/Store"/* 2>/dev/null
	rm -rf "$config_profiles"/*.enrollment* 2>/dev/null
	success "Cleared all ConfigurationProfiles data"
else
	mkdir -p "$config_settings" 2>/dev/null
fi

# Create bypass markers
mkdir -p "$config_settings" 2>/dev/null
touch "$config_settings/.cloudConfigProfileInstalled" 2>/dev/null
touch "$config_settings/.cloudConfigRecordNotFound" 2>/dev/null
success "Created MDM bypass markers"
echo ""

# ── Step 3: Install hosts guard daemon ──
# Ensures MDM domain blocks persist across macOS updates
# (which can reset /etc/hosts)

info "Installing MDM hosts guard daemon..."

mkdir -p /usr/local/bin 2>/dev/null

cat > /usr/local/bin/mdm-hosts-guard.sh << 'HOSTSGUARD'
#!/bin/bash
domains="deviceenrollment.apple.com mdmenrollment.apple.com iprofiles.apple.com acmdm.apple.com axm-adm-mdm.apple.com gdmf.apple.com"
for domain in $domains; do
    grep -q "$domain" /etc/hosts 2>/dev/null || echo "0.0.0.0 $domain" >> /etc/hosts
done
HOSTSGUARD
chmod +x /usr/local/bin/mdm-hosts-guard.sh

cat > /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist << 'HOSTSPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.joneshipit.mdm-hosts-guard</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>/usr/local/bin/mdm-hosts-guard.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
HOSTSPLIST

chown root:wheel /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist
chmod 644 /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist

# Load it now
launchctl bootstrap system /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null

success "MDM hosts guard installed — domain blocks persist across updates"
echo ""

# ── Step 4: Optional reset protection ──
echo -e "${CYAN}Would you like to prevent factory reset?${NC}"
echo -e "${BLU}This silently blocks 'Erase All Content and Settings'.${NC}"
echo -e "${BLU}The option looks normal but just won't work.${NC}"
echo -e "${BLU}(See: github.com/joneshipit/prevent-reset)${NC}"
echo ""
read -p "Install reset protection? (y/n): " install_rp

if [ "$install_rp" = "y" ] || [ "$install_rp" = "Y" ]; then
	info "Installing reset protection..."

	cat > /usr/local/bin/block-erase.sh << 'BLOCKSCRIPT'
#!/bin/bash
pkill -9 -f "Erase Assistant" 2>/dev/null
pkill -9 -f "erasetool" 2>/dev/null
pkill -9 -f "systemreset" 2>/dev/null
BLOCKSCRIPT
	chmod +x /usr/local/bin/block-erase.sh

	cat > /Library/LaunchDaemons/com.joneshipit.block-erase.plist << 'ERASEPLIST'
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
	<key>StartInterval</key>
	<integer>2</integer>
</dict>
</plist>
ERASEPLIST

	chown root:wheel /Library/LaunchDaemons/com.joneshipit.block-erase.plist
	chmod 644 /Library/LaunchDaemons/com.joneshipit.block-erase.plist

	launchctl bootstrap system /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null || \
		launchctl load -w /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null

	success "Reset protection installed"
	echo -e "  ${BLU}To undo later: github.com/joneshipit/prevent-reset (unlock script)${NC}"
else
	info "Skipped reset protection"
fi
echo ""

# ── Step 5: Delete temp user and prepare for Setup Assistant ──
info "Cleaning up temporary user account..."

# Find and delete the temp user
current_user=$(logname 2>/dev/null || echo "$SUDO_USER")
if [ -n "$current_user" ] && [ "$current_user" != "root" ]; then
	info "Will delete user: $current_user"
else
	# Fallback: look for tmpsetup user
	current_user="tmpsetup"
	info "Will delete user: $current_user"
fi

# Delete the user account using sysadminctl (cleanest method)
sysadminctl -deleteUser "$current_user" 2>/dev/null
if [ $? -eq 0 ]; then
	success "Deleted user account: $current_user"
else
	# Fallback: manual deletion
	warn "sysadminctl failed, trying manual deletion..."
	dscl . -delete "/Users/$current_user" 2>/dev/null
	rm -rf "/Users/$current_user" 2>/dev/null
	dscl . -delete /Groups/admin GroupMembership "$current_user" 2>/dev/null
	success "Manually deleted user: $current_user"
fi
echo ""

# ── Step 6: Remove .AppleSetupDone ──
info "Removing .AppleSetupDone to trigger Setup Assistant..."
rm -f /private/var/db/.AppleSetupDone 2>/dev/null && success "Removed .AppleSetupDone" || warn "Could not remove .AppleSetupDone"
echo ""

# ── Step 7: Summary and reboot ──
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       Step 2 Complete! Ready for Clean Setup.     ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}What was done:${NC}"
echo -e "  ✓ MDM domains permanently blocked in /etc/hosts"
echo -e "  ✓ MDM configuration data destroyed"
echo -e "  ✓ Hosts guard daemon installed (survives OS updates)"
echo -e "  ✓ Temporary user account deleted"
echo -e "  ✓ .AppleSetupDone removed"
echo ""
echo -e "${CYAN}What happens next:${NC}"
echo -e "  The Mac will reboot into the full macOS Setup Assistant."
echo -e "  Create your account with Apple ID, Touch ID, Siri — the works."
echo -e "  The MDM enrollment step will be skipped."
echo ""
echo -e "${YEL}Rebooting in 5 seconds...${NC}"
sleep 5
reboot
