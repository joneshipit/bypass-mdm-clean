# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without creating a temporary user account**. Unlike other MDM bypass scripts that create a throwaway admin account you have to delete later, this script lets you create your own account directly — no cleanup needed.

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## How It Works

The script runs from Recovery Mode and exploits a macOS behavior: when `.AppleSetupDone` exists but **no user accounts** are present, macOS runs a **reduced Setup Assistant** that only handles account creation — skipping the full initial setup flow including the Remote Management (MDM) pane.

Specifically, the script:

1. **Blocks MDM domains** — adds `0.0.0.0` entries to `/etc/hosts` for 6 Apple enrollment servers
2. **Nukes all MDM data** — removes every `.cloudConfig*` file, the `ConfigProfiles.binary` CoreData store, and enrollment profiles on both system and data volumes
3. **Creates bypass markers** — writes `.cloudConfigProfileInstalled` and `.cloudConfigRecordNotFound` on both volumes
4. **Creates `.AppleSetupDone` with no users** — this is the key trick that skips the full Setup Assistant (and its MDM pane) while still prompting for account creation
5. **Cleans up leftover accounts** — removes any user accounts from previous bypass attempts

## Features

- **No temporary user** — the account you create is YOUR account
- **No erase/reinstall required** — works on existing macOS installations
- **SSV-aware** — focuses on data volume modifications that survive Signed System Volume protections
- **Deep clean** — clears the CoreData binary store, not just flag files
- **Dual-volume cleanup** — cleans both system and data volumes
- **Automatic volume detection** — no need to know your volume names
- **Idempotent** — safe to run multiple times
- **Error handling** — color-coded output with validation at each step

## Step-by-Step Instructions

### 1. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until you see "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until you see the Apple logo. |

### 2. Connect to WiFi

Connect to a WiFi network from Recovery Mode. This is needed to download the script.

### 3. Open Terminal

From the menu bar: **Utilities → Terminal**

### 4. Run the Script

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

### 5. Select Option 1

The script will auto-detect your volumes and present a menu. Select **1) Bypass MDM (Clean Setup)**.

### 6. Reboot

Close the terminal and reboot your Mac. macOS will detect no user accounts and prompt you to create one. This is your real account — not a temporary one. Set up Apple ID, Touch ID, etc. from System Settings after login.

## Original Script vs. Clean Setup

| | Original (bypass-mdm) | Clean Setup (this repo) |
|---|---|---|
| Creates temp user | Yes — you must delete it later | No |
| Requires erase/reinstall | No | No |
| Setup Assistant | Skipped entirely | Reduced (account creation only) |
| Account creation | Via `dscl` command (temp user) | macOS prompts you directly |
| Post-install cleanup | Delete temp user, fix permissions | None needed |
| Apple ID / Touch ID | Manual setup after login | Manual setup after login |

## Troubleshooting

### macOS still shows Remote Management
Run the script again from Recovery Mode. If it persists, try erasing and reinstalling macOS first, then boot into Recovery before first setup and run the script.

### Account creation screen doesn't appear
If macOS boots to a login screen instead of account creation, the script may not have successfully created `.AppleSetupDone` or there may be a leftover user account. Boot into Recovery and run the script again.

### Volume detection fails
The script looks for volumes with a `/System` directory (system volume) and volumes ending in "Data" (data volume). Ensure you're running from Recovery Mode with macOS installed on the disk.

### Permission errors
Make sure you're running from the Recovery Mode terminal, which has root access.

## Disclaimer

> This script prevents MDM profiles from being configured locally. The device serial number may still appear in the organization's MDM inventory. This tool is provided for educational purposes. Use responsibly and at your own risk. Ensure you have proper authorization before using this on any device.

## Credits

- Original concept: [Assaf Dori](https://github.com/assafdori/bypass-mdm)
- Clean setup adaptation: [joneshipit](https://github.com/joneshipit)
