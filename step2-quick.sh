#!/bin/bash

# Bypass MDM - Quick Setup (Step 2 of 2)
# Run from within macOS as the "user" account from Step 1.
#
# This script:
#   1. Permanently blocks MDM domains in /etc/hosts
#   2. Installs a hosts guard daemon for boot persistence
#   3. Installs reset protection (blocks factory reset)
#   4. Removes .AppleSetupDone → triggers user setup on next login
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
success() { echo -e "${GRN}✓ $1${NC}"; }
info() { echo -e "${BLU}ℹ $1${NC}"; }
warn() { echo -e "${YEL}WARNING: $1${NC}"; }

if [ "$(id -u)" -ne 0 ]; then
	error_exit "This script must be run with sudo. Try: sudo ./step2.sh"
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Quick Setup (Step 2 of 2)          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}This will:${NC}"
echo -e "  • Permanently block MDM domains"
echo -e "  • Block factory reset"
echo -e "  • Trigger user setup on next login"
echo ""
read -p "Continue? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
	echo "Aborted."
	exit 0
fi
echo ""

# ── 1. Block MDM domains in /etc/hosts ──
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

for domain in "${mdm_domains[@]}"; do
	if ! grep -qF "$domain" /etc/hosts 2>/dev/null; then
		echo "0.0.0.0 $domain" >>/etc/hosts
	fi
done

if grep -qF "deviceenrollment.apple.com" /etc/hosts 2>/dev/null; then
	success "MDM domains blocked"
else
	error_exit "Failed to write to /etc/hosts"
fi

# ── 2. Install hosts guard daemon ──
info "Installing hosts guard daemon..."

mkdir -p /usr/local/bin

cat > /usr/local/bin/mdm-hosts-guard.sh << 'GUARD'
#!/bin/bash
domains="deviceenrollment.apple.com mdmenrollment.apple.com iprofiles.apple.com acmdm.apple.com axm-adm-mdm.apple.com axm-adm-enroll.apple.com albert.apple.com identity.apple.com"
for domain in $domains; do
    grep -qF "$domain" /etc/hosts 2>/dev/null || echo "0.0.0.0 $domain" >> /etc/hosts
done
GUARD
chmod +x /usr/local/bin/mdm-hosts-guard.sh

cat > /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist << 'PLIST'
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
PLIST

chown root:wheel /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist
chmod 644 /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist
launchctl bootstrap system /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist 2>/dev/null

success "Hosts guard installed"

# ── 3. Install reset protection ──
info "Installing reset protection..."

cat > /usr/local/bin/block-erase.sh << 'BLOCK'
#!/bin/bash
for proc in "Erase Assistant" "erasetool" "systemreset"; do
    pkill -9 -f "$proc" 2>/dev/null && logger -t block-erase "Blocked: $proc"
done
BLOCK
chmod +x /usr/local/bin/block-erase.sh

cat > /Library/LaunchDaemons/com.joneshipit.block-erase.plist << 'PLIST'
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
PLIST

chown root:wheel /Library/LaunchDaemons/com.joneshipit.block-erase.plist
chmod 644 /Library/LaunchDaemons/com.joneshipit.block-erase.plist
launchctl bootstrap system /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null

success "Reset protection installed"

# ── 4. Remove .AppleSetupDone ──
info "Removing .AppleSetupDone..."

rm -f /private/var/db/.AppleSetupDone 2>/dev/null

if [ ! -f /private/var/db/.AppleSetupDone ]; then
	success "Setup will trigger on next login"
else
	warn "Could not remove .AppleSetupDone"
fi

# Flush DNS
dscacheutil -flushcache 2>/dev/null
killall -HUP mDNSResponder 2>/dev/null

echo ""
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       Done! Reboot to finish.                     ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  1. Reboot the Mac"
echo -e "  2. Log in as ${GRN}user${NC} / password ${GRN}1234${NC}"
echo -e "  3. Setup will appear — Apple ID, iCloud, Touch ID, Siri"
echo ""
