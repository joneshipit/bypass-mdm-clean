#!/bin/bash

# Bypass MDM - Clean Setup (Step 3 of 3)
# Run from Recovery Mode AFTER Step 2.
# Multi-pronged attack to prevent MDM enrollment from appearing
# in Setup Assistant, then clean up users for a fresh start.

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

[ ! -d "/Volumes/Data" ] && { echo -e "${RED}ERROR: /Volumes/Data not found${NC}"; exit 1; }

echo -e "${CYAN}Launching multi-pronged MDM bypass...${NC}"
echo ""

# ═══════════════════════════════════════════════════════
# ATTACK 1: Clear NVRAM
# The DEP activation record may be cached in NVRAM.
# ═══════════════════════════════════════════════════════
echo -e "${YEL}[1/6] Clearing NVRAM...${NC}"
nvram -c 2>/dev/null && echo -e "${GRN}  ✓ NVRAM cleared${NC}" || echo -e "${BLU}  ℹ Could not clear NVRAM${NC}"
echo ""

# ═══════════════════════════════════════════════════════
# ATTACK 2: Nuke ALL MDM/enrollment data on data volume
# ═══════════════════════════════════════════════════════
echo -e "${YEL}[2/6] Destroying MDM enrollment data...${NC}"

data_profiles="/Volumes/Data/private/var/db/ConfigurationProfiles"
if [ -d "$data_profiles" ]; then
	rm -rf "$data_profiles/Settings/.cloudConfigHasActivationRecord" 2>/dev/null
	rm -rf "$data_profiles/Settings/.cloudConfigRecordFound" 2>/dev/null
	rm -rf "$data_profiles/Settings/.cloudConfigActivationRecord" 2>/dev/null
	rm -rf "$data_profiles/Store" 2>/dev/null
	mkdir -p "$data_profiles/Store" 2>/dev/null
	rm -rf "$data_profiles"/*.enrollment* 2>/dev/null
fi

# Create bypass markers
mkdir -p "$data_profiles/Settings" 2>/dev/null
touch "$data_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
touch "$data_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
echo -e "${GRN}  ✓ MDM data destroyed, bypass markers set (data volume)${NC}"

# Same on system volume
sys_profiles="/Volumes/Macintosh HD/var/db/ConfigurationProfiles"
if [ -d "$sys_profiles" ]; then
	rm -rf "$sys_profiles/Settings/.cloudConfigHasActivationRecord" 2>/dev/null
	rm -rf "$sys_profiles/Settings/.cloudConfigRecordFound" 2>/dev/null
	rm -rf "$sys_profiles/Settings/.cloudConfigActivationRecord" 2>/dev/null
	mkdir -p "$sys_profiles/Settings" 2>/dev/null
	touch "$sys_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
	touch "$sys_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
	echo -e "${GRN}  ✓ Bypass markers set (system volume)${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════
# ATTACK 3: Disable MDM-related daemons
# Prevent cloudconfigurationd and related services from
# running. If the daemon doesn't run, Setup Assistant
# can't check enrollment.
# ═══════════════════════════════════════════════════════
echo -e "${YEL}[3/6] Disabling MDM enrollment daemons...${NC}"

# Rename the daemon plists so launchd doesn't load them
mdm_daemons=(
	"com.apple.ManagedClient.cloudconfigurationd.plist"
	"com.apple.ManagedClient.enroll.plist"
	"com.apple.ManagedClient.plist"
	"com.apple.ManagedClient.startup.plist"
	"com.apple.mdmclient.daemon.plist"
	"com.apple.mdmclient.agent.plist"
)

sys_daemons="/Volumes/Macintosh HD/System/Library/LaunchDaemons"
sys_agents="/Volumes/Macintosh HD/System/Library/LaunchAgents"

for daemon in "${mdm_daemons[@]}"; do
	for dir in "$sys_daemons" "$sys_agents"; do
		if [ -f "$dir/$daemon" ]; then
			mv "$dir/$daemon" "$dir/${daemon}.disabled" 2>/dev/null && \
				echo -e "${GRN}  ✓ Disabled: $daemon${NC}" || \
				echo -e "${BLU}  ℹ Could not disable: $daemon (SSV protected)${NC}"
		fi
	done
done
echo ""

# ═══════════════════════════════════════════════════════
# ATTACK 4: Managed preferences skip keys
# Tell Setup Assistant to skip cloud/MDM setup panes.
# ═══════════════════════════════════════════════════════
echo -e "${YEL}[4/6] Writing Setup Assistant skip keys...${NC}"

# Global managed preferences
managed_prefs="/Volumes/Data/Library/Preferences"
mkdir -p "$managed_prefs" 2>/dev/null

cat > "$managed_prefs/com.apple.SetupAssistant.managed.plist" << 'SKIPEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SkipCloudSetup</key>
	<true/>
	<key>SkipDeviceManagement</key>
	<true/>
</dict>
</plist>
SKIPEOF
echo -e "${GRN}  ✓ Skip keys written to managed prefs${NC}"

# Also try the MCX managed preferences path
mcx_prefs="/Volumes/Data/Library/Managed Preferences"
mkdir -p "$mcx_prefs" 2>/dev/null
cp "$managed_prefs/com.apple.SetupAssistant.managed.plist" "$mcx_prefs/" 2>/dev/null

# Try writing to the system volume too
sys_prefs="/Volumes/Macintosh HD/Library/Preferences"
cp "$managed_prefs/com.apple.SetupAssistant.managed.plist" "$sys_prefs/" 2>/dev/null
echo ""

# ═══════════════════════════════════════════════════════
# ATTACK 5: Clear WiFi networks
# Prevent Setup Assistant from reaching MDM servers.
# ═══════════════════════════════════════════════════════
echo -e "${YEL}[5/6] Clearing saved WiFi networks...${NC}"

rm -f "/Volumes/Data/private/var/db/SystemConfiguration/com.apple.wifi.known-networks.plist" 2>/dev/null
rm -f "/Volumes/Data/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist" 2>/dev/null
rm -f "/Volumes/Data/Library/Preferences/SystemConfiguration/com.apple.wifi.message-tracer.plist" 2>/dev/null
echo -e "${GRN}  ✓ WiFi networks cleared${NC}"
echo ""

# ═══════════════════════════════════════════════════════
# ATTACK 6: Delete all users & remove .AppleSetupDone
# ═══════════════════════════════════════════════════════
echo -e "${YEL}[6/6] Deleting all user accounts...${NC}"

DSLOCAL="/Volumes/Data/private/var/db/dslocal/nodes/Default/users"
deleted=0
for plist in "$DSLOCAL"/*.plist; do
	[ -f "$plist" ] || continue
	username=$(basename "$plist" .plist)
	case "$username" in
		_*|root|daemon|nobody) continue ;;
	esac
	echo -e "  ${YEL}Deleting: $username${NC}"
	rm -f "$plist"
	rm -rf "/Volumes/Data/Users/$username" 2>/dev/null
	deleted=$((deleted + 1))
done

[ $deleted -gt 0 ] && echo -e "${GRN}  ✓ Deleted $deleted account(s)${NC}" || echo -e "${BLU}  ℹ No accounts to delete${NC}"

rm -f /Volumes/Data/private/var/db/.AppleSetupDone 2>/dev/null
echo -e "${GRN}  ✓ Removed .AppleSetupDone${NC}"
echo ""

# ═══════════════════════════════════════════════════════
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       All attacks deployed. Reboot and see.       ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Close this terminal and restart your Mac.${NC}"
echo -e "${CYAN}Setup Assistant should launch without MDM.${NC}"
echo ""
echo -e "${YEL}If MDM STILL appears:${NC}"
echo -e "  The device has a hardware-level activation record"
echo -e "  that can only be removed by the organization's"
echo -e "  MDM admin, or by Apple directly."
echo -e "  In that case, use the pre-made account approach"
echo -e "  (re-run this script with --create-user flag)."
echo ""
