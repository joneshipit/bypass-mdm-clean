# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without creating a temporary user account**. Unlike other MDM bypass scripts that create a throwaway admin account you have to delete later, this script lets macOS Setup Assistant run normally — so you set up your Mac exactly the way Apple intended, just without the MDM enrollment step.

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## How It Works

The script runs from Recovery Mode and does four things:

1. **Blocks MDM domains** — adds `0.0.0.0` entries to `/etc/hosts` for Apple's enrollment servers
2. **Nukes all MDM data** — removes every `.cloudConfig*` file, including the cached activation record that causes Setup Assistant to show the MDM enrollment pane even when servers are blocked
3. **Creates bypass markers** — writes `.cloudConfigProfileInstalled` and `.cloudConfigRecordNotFound` so macOS thinks MDM is already handled
4. **Ensures Setup Assistant runs** — removes `.AppleSetupDone` so you get the normal first-boot experience

The key difference from the original: instead of creating a temporary user and marking setup as done, this script ensures Setup Assistant runs on next boot. You create your own account through the normal macOS setup flow — Apple ID, Touch ID, Siri, everything.

## Features

- **No temporary user** — go straight through Setup Assistant like a new Mac
- **Automatic volume detection** — no need to know your volume names
- **Idempotent** — safe to run multiple times (won't duplicate hosts entries)
- **Error handling** — color-coded output with validation at each step

## Prerequisites

- **Erase the hard drive** and **reinstall macOS** before running the script. This is critical — a previous Setup Assistant run caches MDM enrollment data in places the script can't fully clean. A fresh install ensures there's no cached state to interfere.
- The script must be run from **Recovery Mode**, **after** macOS is installed but **before** the first boot into Setup Assistant.

## Step-by-Step Instructions

### 1. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until you see "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until you see the Apple logo. |

### 2. Erase & Reinstall macOS

Open **Disk Utility** from Recovery Mode, erase the internal drive (APFS format), then close Disk Utility and select **Reinstall macOS**. Wait for the install to complete.

### 3. Boot into Recovery Mode Again

After macOS finishes installing, it will try to boot into Setup Assistant. **Do not go through setup.** Instead, force shut down (hold Power) and boot back into Recovery Mode.

### 4. Connect to WiFi

Connect to a WiFi network from Recovery Mode. This is needed to download the script.

### 5. Open Terminal

From the menu bar: **Utilities → Terminal**

### 6. Run the Script

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

### 7. Select Option 1

The script will auto-detect your volumes and present a menu. Select **1) Bypass MDM (Clean Setup)**.

### 8. Reboot

Close the terminal and reboot your Mac. Setup Assistant will start normally — create your account, sign in with your Apple ID, set up Touch ID, and everything else. The MDM enrollment step will be skipped.

## Original Script vs. Clean Setup

| | Original (bypass-mdm) | Clean Setup (this repo) |
|---|---|---|
| Creates temp user | Yes — you must delete it later | No |
| Setup Assistant | Skipped entirely | Runs normally |
| Account creation | Manual (System Settings) | Through Setup Assistant |
| Apple ID setup | Manual | Through Setup Assistant |
| Post-install cleanup | Delete temp user, fix permissions | None needed |

## Troubleshooting

### Setup Assistant still shows MDM enrollment
This usually means macOS cached the MDM enrollment data from a previous setup attempt. The fix:
1. Boot into Recovery Mode
2. **Erase the drive** in Disk Utility
3. **Reinstall macOS**
4. Boot into Recovery **again** (before first setup)
5. Run this script
6. Then reboot into Setup Assistant

The script must run on a fresh macOS install that has never been through Setup Assistant. Once Setup Assistant runs and contacts Apple's servers, it caches MDM data that persists even after the script cleans the known locations.

### Volume detection fails
The script looks for volumes with a `/System` directory (system volume) and volumes ending in "Data" (data volume). If your volumes have non-standard names, the script will report what it finds. Ensure you're running from Recovery Mode with macOS installed on the disk.

### Permission errors
Make sure you're running the script from the Recovery Mode terminal, which has root access. Do not run this from a normal macOS boot.

## Disclaimer

> This script prevents MDM profiles from being configured locally. The device serial number may still appear in the organization's MDM inventory. This tool is provided for educational purposes. Use responsibly and at your own risk. Ensure you have proper authorization before using this on any device.

## Credits

- Original concept: [Assaf Dori](https://github.com/assafdori/bypass-mdm)
- Clean setup adaptation: [joneshipit](https://github.com/joneshipit)
