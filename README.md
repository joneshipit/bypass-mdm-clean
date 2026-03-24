# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without keeping a temporary user account**. Unlike other MDM bypass scripts where you're stuck with a throwaway admin account, this gives you the **full macOS Setup Assistant experience** — Apple ID, Touch ID, Siri, iCloud — just without the MDM enrollment step.

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## How It Works

A two-step process that solves the #1 problem with MDM bypasses: the hosts file and config changes made from Recovery Mode get reverted by macOS's Signed System Volume (SSV) protection. By running Step 2 from *within* macOS, the changes write through the firmlink to the data volume — and actually persist.

### Step 1: Recovery Mode
Creates a temporary user account to boot the system, blocks MDM domains, and sets bypass markers. This is similar to the original bypass-mdm approach.

### Step 2: From within macOS
Logs in as the temp user, then:
1. **Permanently blocks MDM domains** in `/etc/hosts` — written from within the OS, bypasses SSV
2. **Installs a hosts guard daemon** — reapplies blocks on every boot (survives OS updates)
3. **Nukes all MDM configuration data** and sets bypass markers
4. **Optionally installs reset protection** — silently blocks factory reset ([prevent-reset](https://github.com/joneshipit/prevent-reset))
5. **Deletes the temporary user** — no leftover accounts
6. **Removes `.AppleSetupDone`** — triggers Setup Assistant on next boot
7. **Reboots** → clean Setup Assistant without MDM

## Step-by-Step Instructions

### 1. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until the Apple logo appears. |

### 2. Connect to WiFi

Connect to a WiFi network from Recovery Mode.

### 3. Open Terminal

From the menu bar: **Utilities → Terminal**

### 4. Run Step 1

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

Select **1) Bypass MDM (Step 1)**. The script will create a temporary user account.

### 5. Reboot & Log In

Close Terminal and reboot. Log in as:
- **Username:** `tmpsetup`
- **Password:** `1234`

Skip all setup prompts (click "Set Up Later" / "Not Now" / "Skip").

### 6. Run Step 2

Once on the desktop, open **Terminal** (Applications → Utilities → Terminal) and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh
```

Enter the password `1234` when prompted for sudo.

### 7. Setup Assistant

The Mac will automatically reboot into the full macOS Setup Assistant. Create your account with Apple ID, Touch ID, Siri, and everything else. The MDM enrollment step will be skipped.

## Why Two Steps?

| Approach | Problem |
|----------|---------|
| Recovery-only (other scripts) | `/etc/hosts` changes get reverted by SSV on boot |
| Create temp user + skip setup | Stuck with a temp user account to delete manually |
| **This script (two-step)** | Hosts changes persist (written from within OS), temp user auto-deleted, full Setup Assistant |

## Troubleshooting

### MDM still appears in Setup Assistant after Step 2
The hosts file changes should persist since they're written from within the OS. If MDM still shows, try:
1. Boot into the Mac (it may let you past the error with "Continue")
2. Open Terminal and verify: `cat /etc/hosts` — MDM domains should be listed
3. If not, run: `sudo /usr/local/bin/mdm-hosts-guard.sh` to reapply

### Can't log in as tmpsetup
Make sure you're using exactly `tmpsetup` (lowercase) with password `1234`. If the account doesn't appear, boot into Recovery and run Step 1 again.

### MDM prompts appear after setup
The hosts guard daemon should prevent this. Verify it's running:
```bash
sudo launchctl list | grep mdm-hosts-guard
```

## See Also

- **[prevent-reset](https://github.com/joneshipit/prevent-reset)** — silently block "Erase All Content and Settings" to prevent accidental factory resets

## Disclaimer

> This script prevents MDM profiles from being configured locally. The device serial number may still appear in the organization's MDM inventory. This tool is provided for educational purposes. Use responsibly and at your own risk. Ensure you have proper authorization before using this on any device.

## Credits

- Original concept: [Assaf Dori](https://github.com/assafdori/bypass-mdm)
- Clean setup adaptation: [joneshipit](https://github.com/joneshipit)
