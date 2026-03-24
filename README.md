# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without keeping a temporary user account**. Unlike other MDM bypass scripts where you're stuck with a throwaway admin account, this gives you the **full macOS Setup Assistant experience** — Apple ID, Touch ID, Siri, iCloud — just without the MDM enrollment step.

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## How It Works

A three-step process:

1. **Step 1 (Recovery):** Create a temp user + block MDM + set bypass markers
2. **Step 2 (macOS):** Permanently block MDM domains in `/etc/hosts`, install guard daemon
3. **Step 3 (Recovery):** Delete all user accounts, trigger Setup Assistant

Why three steps? You can't modify `/etc/hosts` from Recovery (SSV blocks it), and you can't delete a user while logged into it. So Step 2 handles hosts from within the OS, and Step 3 handles user cleanup from Recovery.

## Step-by-Step Instructions

### 1. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until the Apple logo appears. |

### 2. Open Terminal

From the menu bar: **Utilities → Terminal**

### 3. Run Step 1

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

Select **1) Bypass MDM (Step 1)**. Close Terminal and reboot.

### 4. Log In & Run Step 2

Log in as **`tmpsetup`** / password **`1234`**. Skip all setup prompts.

Open **Terminal** and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh
```

### 5. Boot into Recovery Mode again

Shut down (don't just reboot — you need to enter Recovery). Boot into Recovery Mode using the same method as step 1.

### 6. Run Step 3

Open Terminal and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step3-cleanup.sh -o step3.sh && chmod +x step3.sh && ./step3.sh
```

Close Terminal and reboot.

### 7. Setup Assistant

The Mac boots into a clean Setup Assistant. Create your account with Apple ID, Touch ID, Siri — the works. MDM enrollment will be skipped.

## Troubleshooting

### MDM still appears in Setup Assistant
The hosts file changes should persist since they're written from within the OS. If MDM still shows:
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
