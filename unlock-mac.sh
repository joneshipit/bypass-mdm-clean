#!/bin/bash

# Unlock Mac — Remove Reset Protection
# Removes the restriction profile so "Erase All Content and Settings" works again.
# Must be run with sudo.

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
	echo -e "${RED}ERROR: This script must be run with sudo. Try: sudo ./unlock-mac.sh${NC}" >&2
	exit 1
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Unlock Mac — Remove Reset Protection             ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# Remove the configuration profile
profiles remove -identifier com.joneshipit.reset-protection 2>/dev/null
echo -e "${GRN}✓ Removed restriction profile${NC}"

# Remove the direct plist restriction (fallback method)
defaults delete /Library/Preferences/com.apple.applicationaccess allowEraseContentAndSettings 2>/dev/null
echo -e "${GRN}✓ Removed plist restriction${NC}"

# Re-enable automatic OS upgrades
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true 2>/dev/null
echo -e "${GRN}✓ Re-enabled automatic OS upgrades${NC}"

echo ""
echo -e "${GRN}Mac is unlocked. 'Erase All Content and Settings' is available again.${NC}"
echo -e "${BLU}To re-lock after reset, run the lock-down-mac.sh script again.${NC}"
echo ""
