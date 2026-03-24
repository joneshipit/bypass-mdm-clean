# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without keeping a temporary user account**. Unlike other MDM bypass scripts where you're stuck with a throwaway admin account, this gives you the **full macOS Setup Assistant experience** — Apple ID, Touch ID, Siri, iCloud — just without the MDM enrollment step.

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## Two Paths

| | Quick Setup (2 steps) | Clean Setup (3 steps) |
|---|---|---|
| **Flow** | Recovery → macOS → done | Recovery → macOS → Recovery → done |
| **Complexity** | Simpler | More involved |
| **How it cleans up** | Cleanup daemon deletes users on reboot | You delete users from Recovery yourself |
| **System volume mods** | No (data volume + launchctl only) | Yes (disables SIP, renames daemon plists) |
| **Reset protection** | Always installed | Optional |
| **Best for** | Most users | If Quick doesn't work |

## Quick Setup (2 Steps)

### 1. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until the Apple logo appears. |

### 2. Open Terminal & Run Step 1

From the menu bar: **Utilities → Terminal**

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

Select **1) Quick Setup**. Close Terminal and reboot.

### 3. Log In & Run Step 2

Log in as **`tmpsetup`** / password **`1234`**. Skip all setup prompts.

Open **Terminal** and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-quick.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh
```

### 4. Wait

The Mac will **reboot twice automatically**:
1. First reboot: cleanup daemon deletes all users + removes `.AppleSetupDone`
2. Second reboot: Setup Assistant appears

Create your account with Apple ID, Touch ID, Siri — the works. MDM enrollment will be skipped.

---

## Clean Setup (3 Steps)

Use this if Quick Setup doesn't work, or if you want maximum thoroughness (disables SIP to modify the system volume directly).

### 1. Boot into Recovery Mode

Same as above.

### 2. Open Terminal & Run Step 1

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

Select **2) Clean Setup**. Close Terminal and reboot.

### 3. Log In & Run Step 2

Log in as **`tmpsetup`** / password **`1234`**. Skip all setup prompts.

Open **Terminal** and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh
```

### 4. Boot into Recovery Mode again

**Shut down** (don't just reboot). Boot into Recovery Mode using the same method as before.

### 5. Run Step 3

Open Terminal and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step3-cleanup.sh -o step3.sh && chmod +x step3.sh && ./step3.sh
```

If it says "system volume is read-only," reboot into Recovery and run it again — SIP disable needs a reboot to take effect.

Close Terminal and reboot.

### 6. Setup Assistant

The Mac boots into a clean Setup Assistant. Create your account with Apple ID, Touch ID, Siri — the works. MDM enrollment will be skipped.

### 7. Re-enable SIP (after setup)

Boot into Recovery one more time and run:
```bash
csrutil enable
csrutil authenticated-root enable
```

---

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

### Quick Setup: users weren't deleted
If the cleanup daemon didn't run, you can clean up manually from Recovery (run Step 3).

## Uninstall

To remove all bypass components:
```bash
sudo rm /usr/local/bin/mdm-hosts-guard.sh
sudo rm /Library/LaunchDaemons/com.joneshipit.mdm-hosts-guard.plist
sudo rm /usr/local/bin/block-erase.sh
sudo rm /Library/LaunchDaemons/com.joneshipit.block-erase.plist
sudo rm "/Library/Managed Preferences/com.apple.SetupAssistant.plist"
sudo rm /Library/Preferences/com.apple.SetupAssistant.plist
```
Then edit `/etc/hosts` and remove the `0.0.0.0` lines.

## See Also

- **[prevent-reset](https://github.com/joneshipit/prevent-reset)** — silently block "Erase All Content and Settings" to prevent accidental factory resets

## Disclaimer

> This script prevents MDM profiles from being configured locally. The device serial number may still appear in the organization's MDM inventory. This tool is provided for educational purposes. Use responsibly and at your own risk. Ensure you have proper authorization before using this on any device.

## Credits

- Original concept: [Assaf Dori](https://github.com/assafdori/bypass-mdm)
- Clean setup adaptation: [joneshipit](https://github.com/joneshipit)
