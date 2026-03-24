# Bypass MDM - Clean Setup

Bypass MDM enrollment on macOS **without keeping a temporary user account**. Gives you the **full macOS Setup Assistant experience** — Apple ID, Touch ID, Siri, iCloud — just without the MDM enrollment step.

**Tested and working on macOS Tahoe (26) and Ventura (13).**

Based on [bypass-mdm](https://github.com/assafdori/bypass-mdm) by Assaf Dori.

## Two Paths

| | Quick Setup (2 steps) | Clean Setup (3 steps) |
|---|---|---|
| **Flow** | Recovery → macOS → reboot → done | Recovery → macOS → Recovery → done |
| **Result** | Keeps user account, triggers setup on login | Deletes all users, full fresh Setup Assistant |
| **System volume mods** | No (data volume + launchctl only) | Yes (disables SIP, renames daemon plists) |
| **Reset protection** | Always installed | Optional |
| **Best for** | Quick and easy | Maximum thoroughness |

---

## Quick Setup (2 Steps)

### 1. Boot into Recovery Mode

| Mac Type | How to Enter Recovery |
|----------|----------------------|
| **Apple Silicon** (M1/M2/M3/M4) | Shut down completely. Press and **hold the Power button** until "Loading startup options." Select **Options** → **Continue**. |
| **Intel** | Shut down completely. Press Power, then immediately **hold ⌘ + R** until the Apple logo appears. |

Open Terminal from the menu bar: **Utilities → Terminal**

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

Select **1) Quick Setup**. Close Terminal and reboot.

### 2. Log In & Run Step 2

Log in as **`user`** / password **`1234`**. Skip all setup prompts (click "Set Up Later" / "Not Now").

Open **Terminal** and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-quick.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh
```

Reboot. Log in as **user** / **1234** — setup will appear (Apple ID, iCloud, Touch ID, Siri). Done.

---

## Clean Setup (3 Steps)

The most thorough approach. Disables SIP to modify the system volume, deletes all users, and triggers a completely fresh Setup Assistant.

### 1. Boot into Recovery Mode & Run Step 1

Same Recovery Mode entry as above. Open Terminal and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/bypass-mdm-clean.sh -o bypass-mdm.sh && chmod +x ./bypass-mdm.sh && ./bypass-mdm.sh
```

Select **2) Clean Setup**. Close Terminal and reboot.

### 2. Log In & Run Step 2

Log in as **`user`** / password **`1234`**. Skip all setup prompts.

Open **Terminal** and run:

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step2-clean-setup.sh -o step2.sh && chmod +x step2.sh && sudo ./step2.sh
```

**Important (Apple Silicon only):** Before shutting down, create an admin account for SIP authentication:

```bash
sudo sysadminctl -addUser admin -password 1234 -admin
```

This is needed because `dscl`-created accounts don't get Secure Tokens, and `csrutil` requires one.

**Shut down** the Mac (don't just reboot).

### 3. Boot into Recovery Mode & Disable SIP

Boot into Recovery Mode again. Open Terminal.

**First, disable SIP** (Apple Silicon will prompt for credentials — use **admin** / **1234**):

```bash
csrutil disable
csrutil authenticated-root disable
```

**Then run Step 3:**

```bash
curl -L https://raw.githubusercontent.com/joneshipit/bypass-mdm-clean/main/step3-cleanup.sh -o step3.sh && chmod +x step3.sh && ./step3.sh
```

Close Terminal and reboot.

### 4. Setup Assistant

The Mac boots into a **completely clean Setup Assistant** — just like a brand new Mac. Create your account with Apple ID, Touch ID, Siri, iCloud. MDM enrollment will be skipped.

### 5. Re-enable SIP (recommended)

After setup is complete, boot into Recovery one more time:

```bash
csrutil enable
csrutil authenticated-root enable
```

---

## Troubleshooting

### "No authenticated users" when running csrutil

Accounts created via `dscl` from Recovery don't have Secure Tokens. You need to create an account with `sysadminctl` from within macOS first:

```bash
sudo sysadminctl -addUser admin -password 1234 -admin
```

Then boot into Recovery and authenticate with **admin** / **1234**.

### MDM still appears in Setup Assistant

1. Boot into the Mac (it may let you past the error with "Continue")
2. Open Terminal and verify: `cat /etc/hosts` — MDM domains should be listed
3. If not, run: `sudo /usr/local/bin/mdm-hosts-guard.sh` to reapply

### Can't log in as user

Make sure you're using exactly `user` (lowercase) with password `1234`. If the account doesn't appear, boot into Recovery and run Step 1 again.

### MDM prompts appear after setup

The hosts guard daemon should prevent this. Verify it's running:

```bash
sudo launchctl list | grep mdm-hosts-guard
```

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

Then edit `/etc/hosts` and remove the `0.0.0.0` lines:

```bash
sudo nano /etc/hosts
```

## See Also

- **[prevent-reset](https://github.com/joneshipit/prevent-reset)** — silently block "Erase All Content and Settings" to prevent accidental factory resets

## Disclaimer

> This script prevents MDM profiles from being configured locally. The device serial number may still appear in the organization's MDM inventory. This tool is provided for educational purposes. Use responsibly and at your own risk. Ensure you have proper authorization before using this on any device.

## Credits

- Original concept: [Assaf Dori](https://github.com/assafdori/bypass-mdm)
- Clean setup adaptation: [joneshipit](https://github.com/joneshipit)
