#!/bin/bash

# Bypass MDM - Quick Setup (Step 2 of 2 — alternate path)
# Run from within macOS (as the temp user from Step 1).
#
# This is the SIMPLER alternative to the 3-step flow.
# It does everything in one script:
#   1. Permanently blocks MDM domains in /etc/hosts
#   2. Installs a hosts guard daemon for boot persistence
#   3. Removes MDM profiles + disables enrollment daemons
#   4. Writes Setup Assistant skip keys
#   5. Installs reset protection (blocks factory reset)
#   6. Installs a one-shot cleanup daemon that on next reboot:
#      - Deletes all user accounts (including tmpsetup)
#      - Removes .AppleSetupDone → triggers Setup Assistant
#      - Self-destructs
#
# After reboot, the Mac enters the full Setup Assistant experience.
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
	error_exit "This script must be run with sudo. Try: sudo ./step2-quick.sh"
fi

# Header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Quick Setup (Step 2 of 2)          ║${NC}"
echo -e "${CYAN}║  Run from within macOS                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}This will:${NC}"
echo -e "  • Permanently block MDM domains"
echo -e "  • Disable MDM enrollment daemons"
echo -e "  • Block factory reset"
echo -e "  • Delete ALL users + trigger Setup Assistant on reboot"
echo -e "  • ${YEL}Reboot automatically${NC}"
echo ""
echo -e "${YEL}After reboot, you'll get the full macOS setup${NC}"
echo -e "${YEL}experience — Apple ID, Touch ID, Siri — without MDM.${NC}"
echo ""
read -p "Continue? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
	echo "Aborted."
	exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════
# 1. Block MDM domains in /etc/hosts
# ═══════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════
# 2. Install hosts guard daemon
# ═══════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════
# 3. Remove MDM profiles (before killing daemons)
# ═══════════════════════════════════════════════════════════
info "Removing MDM configuration profiles..."

profiles remove -all 2>/dev/null && success "Removed enrolled profiles" || info "No enrolled profiles to remove (or SIP blocked)"

profiles_dir="/var/db/ConfigurationProfiles"
if [ -d "$profiles_dir" ]; then
	rm -f "$profiles_dir/Settings/.cloudConfigHasActivationRecord" 2>/dev/null
	rm -f "$profiles_dir/Settings/.cloudConfigRecordFound" 2>/dev/null
	rm -f "$profiles_dir/Settings/.cloudConfigActivationRecord" 2>/dev/null
	touch "$profiles_dir/Settings/.cloudConfigProfileInstalled" 2>/dev/null
	touch "$profiles_dir/Settings/.cloudConfigRecordNotFound" 2>/dev/null
	if [ -f "$profiles_dir/Settings/.cloudConfigRecordNotFound" ]; then
		success "MDM bypass markers set"
	else
		warn "Could not write bypass markers (SIP blocking — Setup Assistant skip keys will compensate)"
	fi
else
	info "ConfigurationProfiles not accessible — skip keys will compensate"
fi
echo ""

# ═══════════════════════════════════════════════════════════
# 4. Disable MDM enrollment daemons
# ═══════════════════════════════════════════════════════════
info "Disabling MDM enrollment daemons..."

mdm_daemons=(
	"com.apple.cloudconfigurationd"
	"com.apple.DeviceManagement.enrollmentd"
	"com.apple.ManagedClient.cloudconfigurationd"
	"com.apple.ManagedClient.enroll"
	"com.apple.ManagedClient"
	"com.apple.ManagedClient.startup"
	"com.apple.mdmclient.daemon"
	"com.apple.mdmclient"
)

disabled_count=0
for svc in "${mdm_daemons[@]}"; do
	if launchctl disable "system/$svc" 2>/dev/null; then
		disabled_count=$((disabled_count + 1))
	fi
	launchctl bootout "system/$svc" 2>/dev/null
done

# User-domain agent
logged_in_uid=$(id -u "${SUDO_USER:-}" 2>/dev/null || echo "")
if [ -n "$logged_in_uid" ]; then
	if launchctl disable "gui/$logged_in_uid/com.apple.mdmclient.agent" 2>/dev/null; then
		disabled_count=$((disabled_count + 1))
	fi
	launchctl bootout "gui/$logged_in_uid/com.apple.mdmclient.agent" 2>/dev/null
fi

if [ $disabled_count -gt 0 ]; then
	success "Disabled $disabled_count MDM services via launchctl"
else
	warn "Could not disable services (may require different approach on this macOS version)"
fi
echo ""

# ═══════════════════════════════════════════════════════════
# 5. Write Setup Assistant skip keys
# ═══════════════════════════════════════════════════════════
info "Writing Setup Assistant skip keys..."

managed_dir="/Library/Managed Preferences"
mkdir -p "$managed_dir" 2>/dev/null

cat > "$managed_dir/com.apple.SetupAssistant.plist" << 'SKIPEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SkipCloudSetup</key>
	<true/>
	<key>SkipDeviceManagement</key>
	<true/>
	<key>DidSeeCloudSetup</key>
	<true/>
</dict>
</plist>
SKIPEOF

if [ -f "$managed_dir/com.apple.SetupAssistant.plist" ]; then
	success "Skip keys written to Managed Preferences"
else
	warn "Failed to write skip keys"
fi

cp "$managed_dir/com.apple.SetupAssistant.plist" /Library/Preferences/com.apple.SetupAssistant.plist 2>/dev/null
success "Skip keys copied to /Library/Preferences"
echo ""

# ═══════════════════════════════════════════════════════════
# 6. Install reset protection
# ═══════════════════════════════════════════════════════════
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
echo ""

# ═══════════════════════════════════════════════════════════
# 7. Flush DNS cache
# ═══════════════════════════════════════════════════════════
dscacheutil -flushcache 2>/dev/null
killall -HUP mDNSResponder 2>/dev/null
success "DNS cache flushed"
echo ""

# ═══════════════════════════════════════════════════════════
# 8. Install one-shot cleanup daemon
# This runs on NEXT BOOT (before login) to:
#   - Delete all non-system user accounts (direct plist removal)
#   - Remove .AppleSetupDone to trigger Setup Assistant
#   - Self-destruct
# ═══════════════════════════════════════════════════════════
info "Installing cleanup daemon (runs once on next reboot)..."

cat > /usr/local/bin/mdm-cleanup-oneshot.sh << 'CLEANUPSCRIPT'
#!/bin/bash
# One-shot cleanup — runs at boot before login
# Deletes all user accounts and triggers Setup Assistant

logger -t mdm-cleanup "Starting one-shot cleanup..."

# Wait a moment for filesystems to be fully ready
sleep 3

# Delete all non-system user accounts (direct plist removal — no OpenDirectory needed)
DSLOCAL="/private/var/db/dslocal/nodes/Default/users"
deleted=0
if [ -d "$DSLOCAL" ]; then
    for plist in "$DSLOCAL"/*.plist; do
        [ -f "$plist" ] || continue
        username=$(basename "$plist" .plist)
        case "$username" in
            _*|root|daemon|nobody|Guest) continue ;;
        esac
        logger -t mdm-cleanup "Deleting user: $username"
        rm -f "$plist"
        rm -rf "/Users/$username" 2>/dev/null
        deleted=$((deleted + 1))
    done
fi

logger -t mdm-cleanup "Deleted $deleted user account(s)"

# Remove .AppleSetupDone to trigger Setup Assistant
rm -f /private/var/db/.AppleSetupDone 2>/dev/null
logger -t mdm-cleanup "Removed .AppleSetupDone — Setup Assistant will run"

# Self-destruct: remove this daemon and script
launchctl bootout system/com.joneshipit.mdm-cleanup 2>/dev/null
rm -f /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist
rm -f /usr/local/bin/mdm-cleanup-oneshot.sh
logger -t mdm-cleanup "Cleanup daemon self-destructed. Rebooting..."

# Reboot so Setup Assistant appears fresh
reboot
CLEANUPSCRIPT
chmod +x /usr/local/bin/mdm-cleanup-oneshot.sh

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
		<string>/usr/local/bin/mdm-cleanup-oneshot.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
CLEANUPPLIST

chown root:wheel /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist
chmod 644 /Library/LaunchDaemons/com.joneshipit.mdm-cleanup.plist

# Do NOT bootstrap now — it would run immediately and kill us.
# It will load automatically on next boot via RunAtLoad.
success "Cleanup daemon installed (will run on next reboot)"
echo ""

# ═══════════════════════════════════════════════════════════
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       All done! Rebooting now...                  ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}What happens next:${NC}"
echo -e "  1. Mac reboots"
echo -e "  2. Cleanup daemon deletes all users + triggers Setup Assistant"
echo -e "  3. Mac reboots again automatically"
echo -e "  4. Full Setup Assistant appears — create account, Apple ID, Touch ID"
echo ""
echo -e "${YEL}This will happen automatically. Do not interrupt.${NC}"
echo -e "${YEL}The Mac will reboot TWICE before Setup Assistant appears.${NC}"
echo ""

# Give user a moment to read
sleep 5
reboot
