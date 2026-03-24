#!/bin/bash

# Bypass MDM - Clean Setup (Step 3 of 3)
# Run from Recovery Mode AFTER Step 2.
# Deletes all user accounts, re-applies MDM bypass markers,
# and removes .AppleSetupDone so the Mac boots into a clean
# Setup Assistant without MDM enrollment.

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MDM Bypass - Clean Setup (Step 3 of 3)          ║${NC}"
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

# ── Delete all user accounts ──
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

# ── Re-apply MDM bypass markers ──
# These get cleared when macOS boots. Must re-set them from Recovery
# (where SIP/SSV don't block writes) so Setup Assistant skips MDM.
echo -e "${CYAN}Re-applying MDM bypass markers...${NC}"

sys_profiles="/Volumes/Macintosh HD/var/db/ConfigurationProfiles/Settings"
if [ -d "/Volumes/Macintosh HD/var/db/ConfigurationProfiles" ]; then
	mkdir -p "$sys_profiles" 2>/dev/null
	rm -rf "$sys_profiles/.cloudConfigHasActivationRecord" 2>/dev/null
	rm -rf "$sys_profiles/.cloudConfigRecordFound" 2>/dev/null
	touch "$sys_profiles/.cloudConfigProfileInstalled" 2>/dev/null
	touch "$sys_profiles/.cloudConfigRecordNotFound" 2>/dev/null
	echo -e "${GRN}✓ MDM bypass markers set (system volume)${NC}"
fi

data_profiles="/Volumes/Data/private/var/db/ConfigurationProfiles/Settings"
mkdir -p "$data_profiles" 2>/dev/null
rm -rf "$data_profiles/.cloudConfigHasActivationRecord" 2>/dev/null
rm -rf "$data_profiles/.cloudConfigRecordFound" 2>/dev/null
touch "$data_profiles/.cloudConfigProfileInstalled" 2>/dev/null
touch "$data_profiles/.cloudConfigRecordNotFound" 2>/dev/null
echo -e "${GRN}✓ MDM bypass markers set (data volume)${NC}"
echo ""

# ── Block MDM domains in hosts (best effort) ──
hosts_file="/Volumes/Macintosh HD/etc/hosts"
if [ -f "$hosts_file" ]; then
	for domain in deviceenrollment.apple.com mdmenrollment.apple.com iprofiles.apple.com; do
		grep -qF "$domain" "$hosts_file" 2>/dev/null || echo "0.0.0.0 $domain" >>"$hosts_file"
	done
	echo -e "${GRN}✓ MDM domains blocked in hosts (best effort — Step 2 handles persistence)${NC}"
fi
echo ""

# ── Remove saved WiFi networks ──
# Prevents Setup Assistant from auto-connecting to WiFi.
# Without internet, MDM enrollment can't phone home and gets skipped.
echo -e "${CYAN}Removing saved WiFi networks...${NC}"
rm -f /Volumes/Data/private/var/db/SystemConfiguration/com.apple.wifi.known-networks.plist 2>/dev/null
rm -f "/Volumes/Data/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist" 2>/dev/null
rm -f "/Volumes/Data/Library/Preferences/SystemConfiguration/com.apple.wifi.message-tracer.plist" 2>/dev/null
echo -e "${GRN}✓ WiFi networks cleared — Setup Assistant won't auto-connect${NC}"
echo ""

# ── Remove .AppleSetupDone ──
rm -f /Volumes/Data/private/var/db/.AppleSetupDone 2>/dev/null
echo -e "${GRN}✓ Removed .AppleSetupDone${NC}"

echo ""
echo -e "${GRN}Done! Close this terminal and restart your Mac.${NC}"
echo ""
echo -e "${CYAN}During Setup Assistant:${NC}"
echo -e "  • When asked about WiFi, look for ${GRN}'Other options'${NC} or press ${GRN}Cmd+Q${NC}"
echo -e "  • Skip WiFi / continue without internet"
echo -e "  • Complete setup, then connect to WiFi from System Settings"
echo -e "  • The hosts guard daemon will block MDM enrollment"
echo ""
