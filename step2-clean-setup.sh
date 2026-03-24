#!/bin/bash

# Bypass MDM - Clean Setup (Step 2 of 2)
# Run from within macOS (as the temp user from Step 1).
# This script:
#   1. Permanently blocks MDM domains in /etc/hosts
#   2. Installs a hosts guard daemon for boot persistence
#   3. Optionally installs reset protection (prevent-reset)
#   4. Installs a one-shot cleanup daemon that runs on next boot to:
#      - Delete all user accounts
#      - Remove .AppleSetupDone
#      - Trigger Setup Assistant
#   5. Reboots
#
# Must be run with sudo.

set -o pipefail

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
echo -e "  • Delete ALL user accounts on next reboot"
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

# ── Step 1: Block MDM domains in /etc/hosts ──
info "Blocking MDM domains in /etc/hosts..."

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

blocked_count=0
for domain in "${mdm_domains[@]}"; do
	if ! grep -qF "$domain" /etc/hosts 2>/dev/null; then
		echo "0.0.0.0 $domain" >>/etc/hosts || warn "Failed to write $domain to /etc/hosts"
		blocked_count=$((blocked_count + 1))
	fi
done
if grep -qF "deviceenrollment.apple.com" /etc/hosts 2>/dev/null; then
	success "Blocked ${#mdm_domains[@]} MDM domains ($blocked_count new entries added)"
else
	error_exit "Failed to write to /etc/hosts — SIP or permissions may be blocking writes"
fi
echo ""

# ── Step 2: Install hosts guard daemon ──
info "Installing MDM hosts guard daemon..."

mkdir -p /usr/local/bin || error_exit "Failed to create /usr/local/bin"

cat > /usr/local/bin/mdm-hosts-guard.sh << 'HOSTSGUARD'
#!/bin/bash
domains="deviceenrollment.apple.com mdmenrollment.apple.com iprofiles.apple.com acmdm.apple.com axm-adm-mdm.apple.com axm-adm-enroll.apple.com albert.apple.com identity.apple.com"
changed=0
for domain in $domains; do
    if ! grep -qF "$domain" /etc/hosts 2>/dev/null; then
        echo "0.0.0.0 $domain" >> /etc/hosts
        changed=1
    fi
done
if [ "$changed" -eq 1 ]; then
    logger -t mdm-hosts-guard "Re-applied MDM domain blocks to /etc/hosts"
fi
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
	<key>WatchPaths</key>
	<array>
		<string>/etc/hosts</string>
	</array>
</dict>
</plist>
HOSTSPLIST

chown root:wheel /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist
chmod 644 /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist

launchctl bootstrap system /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null

success "MDM hosts guard installed"
echo ""

# ── Step 3: Optional reset protection ──
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
killed=0
for proc in "Erase Assistant" "erasetool" "systemreset"; do
    if pkill -9 -f "$proc" 2>/dev/null; then
        killed=1
    fi
done
if [ "$killed" -eq 1 ]; then
    logger -t block-erase "Blocked erase attempt — killed erase-related process"
fi
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
	<integer>5</integer>
</dict>
</plist>
ERASEPLIST

	chown root:wheel /Library/LaunchDaemons/com.joneshipit.block-erase.plist
	chmod 644 /Library/LaunchDaemons/com.joneshipit.block-erase.plist

	launchctl bootstrap system /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null || \
		launchctl load -w /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null

	success "Reset protection installed"
else
	info "Skipped reset protection"
fi
echo ""

# ── Step 4: Install one-shot cleanup daemon ──
# This is the key trick: you can't delete a user while logged in as
# that user. Instead, we install a LaunchDaemon that runs ONCE on
# next boot — before any user session starts — to:
#   1. Delete all user accounts (UID >= 500)
#   2. Remove .AppleSetupDone
#   3. Remove itself
# Then loginwindow sees no users + no .AppleSetupDone = Setup Assistant.

info "Installing cleanup daemon (runs on next boot)..."

cat > /usr/local/bin/mdm-cleanup.sh << 'CLEANUP'
#!/bin/bash
# One-shot cleanup — runs at boot before login window.
# Deletes all user accounts, removes .AppleSetupDone, then self-destructs.

logger -t mdm-cleanup "Starting user cleanup..."

# Delete all users with UID >= 500
for user in $(dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 { print $1 }'); do
    logger -t mdm-cleanup "Deleting user: $user"
    dscl . -delete "/Users/$user" 2>/dev/null
    dscl . -delete /Groups/admin GroupMembership "$user" 2>/dev/null
    rm -rf "/Users/$user" 2>/dev/null
done

# Remove .AppleSetupDone to trigger Setup Assistant
rm -f /private/var/db/.AppleSetupDone 2>/dev/null

logger -t mdm-cleanup "Cleanup complete. Setup Assistant will launch."

# Self-destruct — remove the daemon and this script
launchctl bootout system /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist 2>/dev/null
rm -f /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist
rm -f /usr/local/bin/mdm-cleanup.sh
CLEANUP
chmod +x /usr/local/bin/mdm-cleanup.sh

cat > /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist << 'CLEANUPPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.joneshipit.mdm-cleanup</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>/usr/local/bin/mdm-cleanup.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
CLEANUPPLIST

chown root:wheel /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist
chmod 644 /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist

success "Cleanup daemon installed — will delete all users on next boot"
echo ""

# ── Done ──
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       Step 2 Complete!                            ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}What happens on reboot:${NC}"
echo -e "  1. Cleanup daemon runs (before login window)"
echo -e "  2. All user accounts deleted"
echo -e "  3. .AppleSetupDone removed"
echo -e "  4. Cleanup daemon self-destructs"
echo -e "  5. Setup Assistant launches — create your real account"
echo ""
echo -e "${CYAN}To uninstall MDM bypass later, remove:${NC}"
echo -e "  /usr/local/bin/mdm-hosts-guard.sh"
echo -e "  /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist"
echo -e "  /usr/local/bin/block-erase.sh (if installed)"
echo -e "  /Library/LaunchDaemons/com.joneshipit.block-erase.plist (if installed)"
echo -e "  Then remove the 0.0.0.0 lines from /etc/hosts"
echo ""
echo -e "${YEL}Rebooting in 5 seconds...${NC}"
sleep 5
sync
reboot
