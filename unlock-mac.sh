#!/bin/bash

# Unlock Mac — Remove Reset Protection
# Stops and removes the erase blocker daemon.
# Must be run with sudo.

RED='\033[1;31m'
GRN='\033[1;32m'
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

# Stop the daemons
launchctl unload -w /Library/LaunchDaemons/com.joneshipit.block-erase.plist 2>/dev/null
launchctl unload -w /Library/LaunchDaemons/com.joneshipit.block-erase-fallback.plist 2>/dev/null
echo -e "${GRN}✓ Stopped erase blocker${NC}"

# Remove the daemon plists
rm -f /Library/LaunchDaemons/com.joneshipit.block-erase.plist
rm -f /Library/LaunchDaemons/com.joneshipit.block-erase-fallback.plist
echo -e "${GRN}✓ Removed LaunchDaemons${NC}"

# Remove the blocker script
rm -f /usr/local/bin/block-erase.sh
echo -e "${GRN}✓ Removed blocker script${NC}"

# Kill any running instance
pkill -f block-erase.sh 2>/dev/null
echo -e "${GRN}✓ Killed running blocker process${NC}"

echo ""
echo -e "${GRN}Mac is unlocked. 'Erase All Content and Settings' will work normally.${NC}"
echo -e "${CYAN}To re-lock after reset, run lock-down-mac.sh again.${NC}"
echo ""
