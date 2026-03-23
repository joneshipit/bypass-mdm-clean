# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without creating a temporary user account**. Unlike other MDM bypass scripts that create a throwaway admin account you have to delete later, this script lets you create your own account directly — no cleanup needed.

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## Two Bypass Modes

### Option 1: Full Setup Assistant
Removes `.AppleSetupDone` so macOS boots into the **complete Setup Assistant** — the full new-Mac experience with Apple ID, Siri, Touch ID, iCloud, and everything else. Best used after a fresh erase/reinstall. May show a "Remote Management" error on systems with cached MDM data.

### Option 2: Quick Bypass (Recommended)
Creates `.AppleSetupDone` with **no user accounts**. macOS sees setup as "done," skips the full Setup Assistant (including the MDM pane entirely), then detects no users and prompts you to create an account. Works without erasing or reinstalling. Set up Apple ID, Touch ID, etc. from System Settings after login.

## How It Works

Both modes share the same MDM bypass steps:

1. **Blocks MDM domains** — adds `0.0.0.0` entries to `/etc/hosts` for 6 Apple enrollment servers
2. **Nukes all MDM data** — removes every `.cloudConfig*` file, the `ConfigProfiles.binary` CoreData store, and enrollment profiles on both system and data volumes
3. **Creates bypass markers** — writes `.cloudConfigProfileInstalled` and `.cloudConfigRecordNotFound` on both volumes
4. **Cleans up leftover accounts** — removes user accounts from previous bypass attempts

Then each mode differs in the final step:
- **Full Setup Assistant** → removes `.AppleSetupDone` so Setup Assistant runs
- **Quick Bypass** → creates `.AppleSetupDone` with no users so macOS skips Setup Assistant but still prompts for account creation

## Features

- **No temporary user** — the account you create is YOUR account
- **Two modes** — try the full setup experience, fall back to quick bypass if MDM persists
- **No erase/reinstall required** (Quick Bypass mode)
- **SSV-aware** — focuses on data volume modifications that survive Signed System Volume protections
- **Deep clean** — clears the CoreData binary store, not just flag files
- **Dual-volume cleanup** — cleans both system and data volumes
- **Automatic volume detection** — no need to know your volume names
- **Idempotent** — safe to run multiple times

## Step-by-Step Instructions

### 1. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until you see "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until you see the Apple logo. |

### 2. (Optional) Erase & Reinstall macOS

Only needed if you want to use **Option 1 (Full Setup Assistant)**. Open **Disk Utility** from Recovery Mode, erase the internal drive (APFS format), close Disk Utility, and select **Reinstall macOS**. After install completes, boot into Recovery Mode again before first setup.

For **Option 2 (Quick Bypass)**, skip this step entirely.

### 3. Connect to WiFi

Connect to a WiFi network from Recovery Mode. This is needed to download the script.

### 4. Open Terminal

From the menu bar: **Utilities → Terminal**

### 5. Run the Script

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

### 6. Choose Your Mode

The script will auto-detect your volumes and show a menu:
- **Option 1 — Full Setup Assistant**: Choose this if you erased/reinstalled and want the full macOS setup experience
- **Option 2 — Quick Bypass**: Choose this if you didn't erase, or if Option 1 showed a Remote Management error

### 7. Reboot

Close the terminal and reboot your Mac.

## Original Script vs. Clean Setup

| | Original (bypass-mdm) | Clean Setup — Full | Clean Setup — Quick |
|---|---|---|---|
| Creates temp user | Yes | No | No |
| Requires erase | No | Recommended | No |
| Setup experience | None (skipped) | Full Setup Assistant | Account creation only |
| Apple ID / Touch ID | Manual after login | During setup | Manual after login |
| Post-install cleanup | Delete temp user | None | None |

## Troubleshooting

### Option 1 shows "Remote Management" error
This means the MDM enrollment data was cached from a previous setup attempt. Either erase/reinstall and try again, or just use **Option 2 (Quick Bypass)** which skips the MDM pane entirely.

### Account creation screen doesn't appear (Option 2)
If macOS boots to a login screen, there may be a leftover user account. Boot into Recovery and run the script again — it will clean up leftover accounts automatically.

### Volume detection fails
The script looks for volumes with a `/System` directory (system volume) and volumes ending in "Data" (data volume). Ensure you're running from Recovery Mode with macOS installed.

### MDM prompts appear after login
Check that the hosts file still has the MDM blocks: `cat /etc/hosts`. macOS updates can reset the hosts file. Re-add blocks with:
```bash
sudo sh -c 'echo "0.0.0.0 deviceenrollment.apple.com" >> /etc/hosts'
sudo sh -c 'echo "0.0.0.0 mdmenrollment.apple.com" >> /etc/hosts'
sudo sh -c 'echo "0.0.0.0 iprofiles.apple.com" >> /etc/hosts'
```

## Bonus: Lock Down Mac (Prevent Reset)

Adds friction to the factory reset process — the user keeps full admin access but can't accidentally erase the Mac. Run **after** setup is complete:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/lock-down-mac.sh -o lock-down-mac.sh && chmod +x ./lock-down-mac.sh && sudo ./lock-down-mac.sh
```

What it does:
- **Installs a restriction profile** that disables "Erase All Content and Settings" in System Settings
- **Firmware/Recovery password** (Intel) or relies on Apple Silicon's built-in auth requirement
- **User stays admin** — full access to install apps, change settings, everything except factory reset

To unlock when a reset is actually needed:
```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/unlock-mac.sh -o unlock-mac.sh && chmod +x unlock-mac.sh && sudo ./unlock-mac.sh
```

## Disclaimer

> This script prevents MDM profiles from being configured locally. The device serial number may still appear in the organization's MDM inventory. This tool is provided for educational purposes. Use responsibly and at your own risk. Ensure you have proper authorization before using this on any device.

## Credits

- Original concept: [Assaf Dori](https://github.com/assafdori/bypass-mdm)
- Clean setup adaptation: [joneshipit](https://github.com/joneshipit)
