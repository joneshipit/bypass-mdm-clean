#!/bin/bash

# Bypass MDM - Clean Setup (Step 1 of 3)
# Run from Recovery Mode. Creates a temporary user to boot the system,
# then Step 2 (run from within macOS) locks down MDM permanently and
# removes the temp user so Setup Assistant runs clean.
#
# Based on bypass-mdm by Assaf Dori (https://github.com/assafdori/bypass-mdm)

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}Bypass MDM - Clean Setup (Step 1 of 3)${NC}"
echo ""

PS3='Please enter your choice: '
options=("Bypass MDM (Step 1)" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM (Step 1)")
		echo -e "${YEL}Bypass MDM from Recovery${NC}"

		# Normalize Data volume name — same as assafdori/bypass-mdm
		if [ -d "/Volumes/Macintosh HD - Data" ]; then
			diskutil rename "Macintosh HD - Data" "Data"
		fi

		# Create temporary user — identical to assafdori/bypass-mdm
		dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/tmpsetup"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/tmpsetup" UserShell "/bin/zsh"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/tmpsetup" RealName "Temporary Setup"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/tmpsetup" UniqueID "501"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/tmpsetup" PrimaryGroupID "20"
		mkdir "/Volumes/Data/Users/tmpsetup"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/tmpsetup" NFSHomeDirectory "/Users/tmpsetup"
		dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/tmpsetup" "1234"
		dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership tmpsetup

		# Block MDM hosts + remove MDM config — on system volume, same as assafdori
		echo "0.0.0.0 deviceenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
		echo "0.0.0.0 mdmenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
		echo "0.0.0.0 iprofiles.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts

		# Remove MDM records + create bypass markers — same as assafdori
		touch /Volumes/Data/private/var/db/.AppleSetupDone
		rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
		rm -rf /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
		touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
		touch /Volumes/Macintosh\ HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound

		echo -e "${GRN}MDM enrollment has been bypassed!${NC}"
		echo ""
		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal and reboot"
		echo -e "  2. Log in as: ${GRN}tmpsetup${NC} / password: ${GRN}1234${NC}"
		echo -e "  3. Skip all setup prompts (click 'Set Up Later' / 'Not Now')"
		echo -e "  4. Once on the desktop, open ${GRN}Terminal${NC} and run:"
		echo ""
		echo -e "  ${YEL}curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh${NC}"
		echo ""
		echo -e "  5. The Mac will reboot into a clean Setup Assistant"
		echo -e "     — create your real account with Apple ID, Touch ID, etc."
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
