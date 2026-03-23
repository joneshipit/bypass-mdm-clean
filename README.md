# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without creating a temporary user account**. Unlike other MDM bypass scripts that create a throwaway admin account you have to delete later, this script lets macOS Setup Assistant run normally — so you set up your Mac exactly the way Apple intended, just without the MDM enrollment step.

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## How It Works

The script runs from Recovery Mode and does three things:

1. **Blocks MDM domains** — adds `0.0.0.0` entries to `/etc/hosts` for Apple's enrollment servers
2. **Manipulates MDM config markers** — removes activation records and creates "already handled" marker files so macOS thinks MDM setup is complete
3. **Ensures Setup Assistant runs** — removes `.AppleSetupDone` so you get the normal first-boot experience

The key difference from the original: instead of creating a temporary user and marking setup as done, this script ensures Setup Assistant runs on next boot. You create your own account through the normal macOS setup flow — Apple ID, Touch ID, Siri, everything.

## Features

- **No temporary user** — go straight through Setup Assistant like a new Mac
- **Automatic volume detection** — no need to know your volume names
- **Idempotent** — safe to run multiple times (won't duplicate hosts entries)
- **Error handling** — color-coded output with validation at each step

## Prerequisites

- Strongly recommended: **erase the hard drive** before starting
- Recommended: **reinstall macOS** (using Internet Recovery or a USB installer)
- The script must be run from **Recovery Mode**

## Step-by-Step Instructions

### 1. Erase & Reinstall macOS (Recommended)

If starting fresh, erase the drive and reinstall macOS via Recovery Mode first. This gives the cleanest result.

### 2. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until you see "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until you see the Apple logo. |

### 3. Connect to WiFi

Connect to a WiFi network from Recovery Mode. This is needed to download the script.

### 4. Open Terminal

From the menu bar: **Utilities → Terminal**

### 5. Run the Script

```bash
curl -L https://raw.githubusercontent.com/jonesdev/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

### 6. Select Option 1

The script will auto-detect your volumes and present a menu. Select **1) Bypass MDM (Clean Setup)**.

### 7. Reboot

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
Reboot into Recovery Mode and run the script again. If the issue persists, make sure you're connected to WiFi when running the script (so volume detection works correctly) and that macOS is properly installed.

### Volume detection fails
The script looks for volumes with a `/System` directory (system volume) and volumes ending in "Data" (data volume). If your volumes have non-standard names, the script will report what it finds. Ensure you're running from Recovery Mode with macOS installed on the disk.

### Permission errors
Make sure you're running the script from the Recovery Mode terminal, which has root access. Do not run this from a normal macOS boot.

## Disclaimer

> This script prevents MDM profiles from being configured locally. The device serial number may still appear in the organization's MDM inventory. This tool is provided for educational purposes. Use responsibly and at your own risk. Ensure you have proper authorization before using this on any device.

## Credits

- Original concept: [Assaf Dori](https://github.com/assafdori/bypass-mdm)
- Clean setup adaptation: jonesdev
