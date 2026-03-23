#!/bin/bash

# Lock Down Mac — Prevent Erase/Reset
# Run this AFTER macOS setup is complete.
# Creates a hidden admin account, demotes the main user to standard,
# and configures protections to prevent accidental factory reset.
#
# Must be run as admin (or with sudo).

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

success() {
	echo -e "${GRN}✓ $1${NC}"
}

info() {
	echo -e "${BLU}ℹ $1${NC}"
}

warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

# Check if running as root/sudo
if [ "$(id -u)" -ne 0 ]; then
	error_exit "This script must be run with sudo. Try: sudo ./lock-down-mac.sh"
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Lock Down Mac — Prevent Erase/Reset             ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Identify the user to lock down ──
echo -e "${CYAN}Current non-system users on this Mac:${NC}"
echo ""

# List real users (UID >= 500, not system accounts)
user_list=()
while IFS= read -r user; do
	uid=$(dscl . -read "/Users/$user" UniqueID 2>/dev/null | awk '{print $2}')
	if [ -n "$uid" ] && [ "$uid" -ge 500 ] 2>/dev/null; then
		is_admin=""
		if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$user"; then
			is_admin=" ${YEL}(admin)${NC}"
		else
			is_admin=" ${BLU}(standard)${NC}"
		fi
		user_list+=("$user")
		echo -e "  • $user$is_admin"
	fi
done < <(dscl . -list /Users | grep -v '^_' | grep -v '^root$' | grep -v '^daemon$' | grep -v '^nobody$' | sort)

echo ""

if [ ${#user_list[@]} -eq 0 ]; then
	error_exit "No regular user accounts found."
fi

read -p "Enter the username to lock down (the one your sister uses): " target_user

# Verify user exists
if ! dscl . -read "/Users/$target_user" &>/dev/null; then
	error_exit "User '$target_user' does not exist."
fi

echo ""

# ── Step 2: Create a hidden admin account ──
info "Setting up hidden admin account..."
echo ""
echo -e "${CYAN}This creates a hidden admin account that only YOU know about.${NC}"
echo -e "${CYAN}It won't appear on the login screen. You'll use it to manage the Mac.${NC}"
echo ""

read -p "Enter admin username (e.g., 'macadmin'): " admin_user

# Check if it already exists
if dscl . -read "/Users/$admin_user" &>/dev/null; then
	warn "User '$admin_user' already exists."
	if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$admin_user"; then
		success "'$admin_user' is already an admin"
	else
		dscl . -append /Groups/admin GroupMembership "$admin_user"
		success "Made '$admin_user' an admin"
	fi
else
	read -sp "Enter admin password: " admin_pass
	echo ""
	read -sp "Confirm admin password: " admin_pass2
	echo ""

	if [ "$admin_pass" != "$admin_pass2" ]; then
		error_exit "Passwords don't match."
	fi

	if [ ${#admin_pass} -lt 4 ]; then
		error_exit "Password must be at least 4 characters."
	fi

	# Find next available UID
	last_uid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
	new_uid=$((last_uid + 1))

	# Create the admin user
	sysadminctl -addUser "$admin_user" -password "$admin_pass" -admin 2>/dev/null
	if [ $? -ne 0 ]; then
		# Fallback to dscl
		dscl . -create "/Users/$admin_user"
		dscl . -create "/Users/$admin_user" UserShell /bin/zsh
		dscl . -create "/Users/$admin_user" RealName "Mac Admin"
		dscl . -create "/Users/$admin_user" UniqueID "$new_uid"
		dscl . -create "/Users/$admin_user" PrimaryGroupID 20
		dscl . -create "/Users/$admin_user" NFSHomeDirectory "/Users/$admin_user"
		dscl . -passwd "/Users/$admin_user" "$admin_pass"
		dscl . -append /Groups/admin GroupMembership "$admin_user"
		createhomedir -c -u "$admin_user" 2>/dev/null
	fi

	success "Created admin account: $admin_user"

	# Hide the admin account from login screen
	dscl . -create "/Users/$admin_user" IsHidden 1
	success "Hidden from login screen"

	# Hide from Users & Groups in System Settings (hide users with UID under 500 threshold)
	# Actually, we keep the UID >= 500 but set IsHidden
	defaults write /Library/Preferences/com.apple.loginwindow HiddenUsersList -array-add "$admin_user" 2>/dev/null
	success "Hidden from System Settings"

	# Hide home folder
	if [ -d "/Users/$admin_user" ]; then
		chflags hidden "/Users/$admin_user" 2>/dev/null
		success "Hidden home folder"
	fi
fi

echo ""

# ── Step 3: Demote the target user to standard ──
info "Demoting '$target_user' to standard user..."

if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$target_user"; then
	dscl . -delete /Groups/admin GroupMembership "$target_user" 2>/dev/null
	success "'$target_user' is now a standard (non-admin) user"
	echo -e "  ${BLU}→ Cannot access 'Erase All Content and Settings'${NC}"
	echo -e "  ${BLU}→ Cannot install system-level software${NC}"
	echo -e "  ${BLU}→ Cannot modify other user accounts${NC}"
else
	success "'$target_user' is already a standard user"
fi

echo ""

# ── Step 4: Disable the ability to boot into Recovery without authentication ──
info "Checking Recovery Mode protection..."

# Detect Mac type
cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
if echo "$cpu_brand" | grep -qi "apple"; then
	mac_type="apple_silicon"
else
	mac_type="intel"
fi

if [ "$mac_type" = "intel" ]; then
	# Intel: check for firmware password
	if command -v firmwarepasswd &>/dev/null; then
		fw_status=$(firmwarepasswd -check 2>/dev/null)
		if echo "$fw_status" | grep -qi "Yes"; then
			success "Firmware password is already set"
		else
			echo ""
			echo -e "${CYAN}Set a firmware password to prevent Recovery Mode access?${NC}"
			echo -e "${YEL}This prevents booting into Recovery without the password.${NC}"
			read -p "Set firmware password? (y/n): " set_fw
			if [ "$set_fw" = "y" ] || [ "$set_fw" = "Y" ]; then
				firmwarepasswd -setpasswd
				if [ $? -eq 0 ]; then
					success "Firmware password set"
				else
					warn "Could not set firmware password"
				fi
			else
				warn "Skipped firmware password — Recovery Mode is not password-protected"
			fi
		fi
	else
		warn "firmwarepasswd not available on this system"
	fi
else
	# Apple Silicon: Recovery always requires user authentication
	success "Apple Silicon detected — Recovery Mode requires user authentication by default"
	info "Only admin users (your hidden account) can access Recovery utilities"
fi

echo ""

# ── Step 5: Enable FileVault (if not already) ──
info "Checking FileVault status..."

fv_status=$(fdesetup status 2>/dev/null)
if echo "$fv_status" | grep -qi "On"; then
	success "FileVault is already enabled"
else
	echo ""
	echo -e "${CYAN}Enable FileVault disk encryption?${NC}"
	echo -e "${BLU}This encrypts the disk and requires a password to boot.${NC}"
	echo -e "${BLU}Prevents accessing data from Recovery/external boot.${NC}"
	read -p "Enable FileVault? (y/n): " enable_fv
	if [ "$enable_fv" = "y" ] || [ "$enable_fv" = "Y" ]; then
		fdesetup enable -user "$admin_user" 2>/dev/null
		if [ $? -eq 0 ]; then
			success "FileVault enabled"
			echo -e "${YEL}IMPORTANT: Save the recovery key that was displayed above!${NC}"
		else
			warn "Could not enable FileVault automatically"
			info "Enable it manually: System Settings > Privacy & Security > FileVault"
		fi
	else
		info "Skipped FileVault"
	fi
fi

echo ""

# ── Step 6: Disable SoftwareUpdate automatic OS upgrades (prevents reset-like behavior) ──
info "Configuring software update settings..."

# Prevent automatic major OS upgrades (minor security updates still allowed)
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null
success "Disabled automatic major OS upgrades"

echo ""

# ── Summary ──
echo -e "${GRN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║       Mac Locked Down Successfully!               ║${NC}"
echo -e "${GRN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}What's protected:${NC}"
echo -e "  ✓ '$target_user' is a standard user — cannot erase/reset the Mac"
echo -e "  ✓ Hidden admin account '$admin_user' for your management"
if [ "$mac_type" = "intel" ]; then
	echo -e "  ✓ Firmware password protects Recovery Mode (if set)"
else
	echo -e "  ✓ Apple Silicon requires admin auth for Recovery Mode"
fi
echo ""
echo -e "${CYAN}To manage the Mac later:${NC}"
echo -e "  • Log in as '$admin_user' from the login screen:"
echo -e "    Click 'Other User' and type the username manually"
echo -e "  • Or use: ${YEL}su - $admin_user${NC} from Terminal"
echo ""
echo -e "${CYAN}What '$target_user' CANNOT do:${NC}"
echo -e "  ✗ Erase All Content and Settings"
echo -e "  ✗ Create/delete user accounts"
echo -e "  ✗ Access Recovery Mode utilities (Apple Silicon)"
echo -e "  ✗ Change system-level settings"
echo ""
echo -e "${CYAN}What '$target_user' CAN still do:${NC}"
echo -e "  ✓ Install apps from App Store"
echo -e "  ✓ Use all apps normally"
echo -e "  ✓ Change their own password"
echo -e "  ✓ Customize their desktop/settings"
echo ""
