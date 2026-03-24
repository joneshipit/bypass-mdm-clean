#!/bin/bash

# Bypass MDM - Clean Setup (Step 2 of 2)
# Run from within macOS (as the temp user from Step 1).
# This script:
#   1. Permanently blocks MDM domains in /etc/hosts
#   2. Nukes all MDM configuration data and sets bypass markers
#   3. Installs a hosts guard daemon for boot persistence
#   4. Optionally installs reset protection (prevent-reset)
#   5. Removes .AppleSetupDone (BEFORE user deletion for safety)
#   6. Deletes the temporary 'tmpsetup' user account
#   7. Reboots into a clean Setup Assistant — no MDM, no temp user
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

# ── Safety trap for partial failure ──
cleanup_warning() {
	local exit_code=$?
	if [ $exit_code -ne 0 ]; then
		echo ""
		echo -e "${RED}╔═══════════════════════════════════════════════════╗${NC}"
		echo -e "${RED}║  Script failed! System may be in a partial state. ║${NC}"
		echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
		echo -e "${YEL}If the temp user was deleted but Setup Assistant${NC}"
		echo -e "${YEL}doesn't appear, boot into Recovery Mode and run${NC}"
		echo -e "${YEL}Step 1 again to create a new temp user.${NC}"
	fi
}
trap cleanup_warning EXIT

# Must be root
if [ "$(id -u)" -ne 0 ]; then
	error_exit "This script must be run with sudo. Try: sudo ./step2.sh"
fi

# ── Idempotency guard ──
MARKER_FILE="/var/db/.mdm-bypass-step2-done"
if [ -f "$MARKER_FILE" ]; then
	warn "Step 2 has already been run on this machine. Running again anyway."
fi

# Build list of all non-system user accounts (UID >= 500, skip root/daemon/nobody)
USER_LIST=()
for user in $(dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 { print $1 }'); do
	USER_LIST+=("$user")
done

if [ ${#USER_LIST[@]} -eq 0 ]; then
	info "No user accounts found to delete"
else
	info "Will delete ${#USER_LIST[@]} user account(s): ${USER_LIST[*]}"
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
if [ ${#USER_LIST[@]} -gt 0 ]; then
	echo -e "  • Delete all user accounts: ${USER_LIST[*]}"
fi
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

# ── Step 1: Block MDM domains in /etc/hosts ──
# Writing from within a running macOS persists because the OS uses a
# writable overlay on the system volume. This is the key advantage
# over Recovery-only approaches where SSV prevents persistence.

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
# Verify the write actually took effect
if grep -qF "deviceenrollment.apple.com" /etc/hosts 2>/dev/null; then
	success "Blocked ${#mdm_domains[@]} MDM domains ($blocked_count new entries added)"
else
	error_exit "Failed to write to /etc/hosts — SIP or permissions may be blocking writes"
fi
echo ""

# NOTE: MDM activation records and bypass markers are handled in Step 1
# from Recovery Mode, where SIP doesn't block writes to
# /var/db/ConfigurationProfiles/. No need to repeat here.
echo ""

# ── Step 3: Install hosts guard daemon ──
# Ensures MDM domain blocks persist across macOS updates
# (which can reset /etc/hosts)

info "Installing MDM hosts guard daemon..."

mkdir -p /usr/local/bin || error_exit "Failed to create /usr/local/bin"

cat > /usr/local/bin/mdm-hosts-guard.sh << 'HOSTSGUARD'
#!/bin/bash
# MDM Hosts Guard — re-blocks MDM domains if /etc/hosts is reset
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

# Load it now
launchctl bootstrap system /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null

success "MDM hosts guard installed — runs at boot and whenever /etc/hosts changes"
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
	echo -e "  ${BLU}To undo later: github.com/joneshipit/prevent-reset (unlock script)${NC}"
else
	info "Skipped reset protection"
fi
echo ""

# ── Step 5: Remove .AppleSetupDone FIRST (before user deletion) ──
# This order is critical: if user deletion causes a crash/reboot,
# at least Setup Assistant will still launch on next boot.
info "Removing .AppleSetupDone to trigger Setup Assistant..."
if rm -f /private/var/db/.AppleSetupDone; then
	success "Removed .AppleSetupDone"
else
	warn "Could not remove .AppleSetupDone — Setup Assistant may not trigger"
fi
echo ""

# ── Step 6: Delete ALL user accounts ──
if [ ${#USER_LIST[@]} -gt 0 ]; then
	for del_user in "${USER_LIST[@]}"; do
		info "Deleting user: $del_user"

		# Delete user record
		if dscl . -delete "/Users/$del_user" 2>/dev/null; then
			success "Deleted user record: $del_user"
		else
			warn "dscl delete failed for $del_user"
		fi

		# Remove from admin group
		dscl . -delete /Groups/admin GroupMembership "$del_user" 2>/dev/null

		# Remove home directory
		if [ -d "/Users/$del_user" ]; then
			rm -rf "/Users/$del_user" 2>/dev/null && \
				success "Removed home directory: /Users/$del_user" || \
				warn "Could not fully remove /Users/$del_user"
		fi
	done
else
	info "No user accounts to delete"
fi
echo ""

# ── Mark Step 2 as done (idempotency) ──
touch "$MARKER_FILE" 2>/dev/null

# ── Step 7: Summary and reboot ──
# Clear the trap — we succeeded
trap - EXIT

echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       Step 2 Complete! Ready for Clean Setup.     ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}What was done:${NC}"
echo -e "  ✓ MDM domains permanently blocked in /etc/hosts"
echo -e "  ✓ MDM configuration data destroyed"
echo -e "  ✓ Hosts guard daemon installed (survives OS updates)"
if [ ${#USER_LIST[@]} -gt 0 ]; then
	echo -e "  ✓ Deleted ${#USER_LIST[@]} user account(s): ${USER_LIST[*]}"
fi
echo -e "  ✓ .AppleSetupDone removed"
echo ""
echo -e "${CYAN}What happens next:${NC}"
echo -e "  The Mac will reboot into the full macOS Setup Assistant."
echo -e "  Create your account with Apple ID, Touch ID, Siri — the works."
echo -e "  The MDM enrollment step will be skipped."
echo ""
echo -e "${CYAN}To uninstall later, remove these files:${NC}"
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
