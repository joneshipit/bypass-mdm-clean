#!/bin/bash

# Bypass MDM - Step 1
# Run from Recovery Mode. Creates a temporary user to boot the system.
# Based on bypass-mdm by Assaf Dori (https://github.com/assafdori/bypass-mdm)

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Bypass MDM - Step 1 (Recovery Mode)              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

do_bypass() {
	echo -e "${YEL}Bypassing MDM from Recovery...${NC}"
	echo ""

	# Normalize Data volume name — same as assafdori/bypass-mdm
	if [ -d "/Volumes/Macintosh HD - Data" ]; then
		diskutil rename "Macintosh HD - Data" "Data"
	fi

	# Create user account
	dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/user"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/user" UserShell "/bin/zsh"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/user" RealName "User"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/user" UniqueID "501"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/user" PrimaryGroupID "20"
	mkdir "/Volumes/Data/Users/user"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/user" NFSHomeDirectory "/Users/user"
	dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/user" "1234"
	dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership user

	# Block MDM hosts + remove MDM config — on system volume, same as assafdori
	echo "0.0.0.0 deviceenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
	echo "0.0.0.0 mdmenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
	echo "0.0.0.0 iprofiles.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts

	# Remove MDM records + create bypass markers — same as assafdori
	touch /Volumes/Data/private/var/db/.AppleSetupDone
	rm -f /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
	rm -f /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
	touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
	touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound

	echo ""
	echo -e "${GRN}MDM enrollment has been bypassed!${NC}"
	echo ""
}

PS3='Please enter your choice: '
options=(
	"Quick Setup (2 steps total — no Recovery again)"
	"Clean Setup (3 steps total — most thorough)"
	"Reboot & Exit"
)

echo -e "${CYAN}Choose your path:${NC}"
echo ""
echo -e "  ${GRN}Option 1: Quick Setup (2 steps)${NC}"
echo -e "  Recovery → macOS → reboot → done."
echo -e "  Keeps the 'user' account, triggers setup on next login."
echo ""
echo -e "  ${GRN}Option 2: Clean Setup (3 steps)${NC}"
echo -e "  Recovery → macOS → Recovery → done."
echo -e "  Deletes all users, full fresh Setup Assistant."
echo ""

select opt in "${options[@]}"; do
	case $opt in
	"Quick Setup (2 steps total — no Recovery again)")
		do_bypass

		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal and reboot"
		echo -e "  2. Log in as: ${GRN}user${NC} / password: ${GRN}1234${NC}"
		echo -e "  3. Skip all setup prompts (click 'Set Up Later' / 'Not Now')"
		echo -e "  4. Once on the desktop, open ${GRN}Terminal${NC} and run:"
		echo ""
		echo -e "  ${YEL}curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-quick.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh${NC}"
		echo ""
		echo -e "  5. Reboot, log in as ${GRN}user${NC} / ${GRN}1234${NC}"
		echo -e "  6. Setup appears — Apple ID, iCloud, Touch ID, Siri"
		echo ""
		break
		;;
	"Clean Setup (3 steps total — most thorough)")
		do_bypass

		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal and reboot"
		echo -e "  2. Log in as: ${GRN}user${NC} / password: ${GRN}1234${NC}"
		echo -e "  3. Skip all setup prompts (click 'Set Up Later' / 'Not Now')"
		echo -e "  4. Once on the desktop, open ${GRN}Terminal${NC} and run:"
		echo ""
		echo -e "  ${YEL}curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh${NC}"
		echo ""
		echo -e "  5. ${YEL}Shut down${NC} the Mac, boot into Recovery again"
		echo -e "  6. Run Step 3 from Recovery (instructions shown after Step 2)"
		echo -e "  7. Setup Assistant appears — create account, Apple ID, Touch ID"
		echo ""
		break
		;;
	"Reboot & Exit")
		echo "Rebooting..."
		reboot
		break
		;;
	*)
		echo -e "${RED}Invalid option $REPLY${NC}"
		;;
	esac
done
