#!/bin/bash

# Bypass MDM - Clean Setup (Step 3)
# Run from Recovery Mode AFTER Step 2.
# Deletes all user accounts and removes .AppleSetupDone
# so the Mac boots into a clean Setup Assistant.

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Clean Setup (Step 3)               ║${NC}"
echo -e "${CYAN}║  Run from Recovery Mode                          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# Normalize Data volume
if [ -d "/Volumes/Macintosh HD - Data" ]; then
	diskutil rename "Macintosh HD - Data" "Data"
fi

if [ ! -d "/Volumes/Data" ]; then
	echo -e "${RED}ERROR: /Volumes/Data not found. Is macOS installed?${NC}"
	exit 1
fi

DSLOCAL="/Volumes/Data/private/var/db/dslocal/nodes/Default/users"

echo -e "${CYAN}Deleting all user accounts...${NC}"
echo ""

deleted=0
for plist in "$DSLOCAL"/*.plist; do
	[ -f "$plist" ] || continue
	username=$(basename "$plist" .plist)

	case "$username" in
		_*|root|daemon|nobody) continue ;;
	esac

	echo -e "${YEL}  Deleting: $username${NC}"
	rm -f "$plist"
	rm -rf "/Volumes/Data/Users/$username" 2>/dev/null
	deleted=$((deleted + 1))
done

if [ $deleted -eq 0 ]; then
	echo -e "${BLU}  No user accounts found to delete${NC}"
else
	echo ""
	echo -e "${GRN}✓ Deleted $deleted user account(s)${NC}"
fi

echo ""

# Remove .AppleSetupDone
rm -f /Volumes/Data/private/var/db/.AppleSetupDone 2>/dev/null
echo -e "${GRN}✓ Removed .AppleSetupDone${NC}"

echo ""
echo -e "${GRN}Done! Reboot into a clean Setup Assistant.${NC}"
echo -e "${CYAN}Close this terminal and restart your Mac.${NC}"
echo ""
