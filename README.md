# Yabridge installer (for Ubuntu Studio)

This script is built on **Ubuntu Studio 24.04**, but it should also work on other Debian-based systems.  
It simplifies installing Windows VST/CLAP plugins with yabridge so that, after setup, you can just **double-click plugin installers**—no terminal needed. It also pins a specific wine version (**wine-staging 9.21**) for compatibility with **yabridge 5.1.1**, while keeping your **system wine** free to update.

## Step 1
**Run as normal user, NOT as sudo.**  
You’ll be prompted for your password when needed.

```bash
git clone https://github.com/sirsipe/yabridge-setup
chmod +x yabridge-setup/yabridge-installer.sh
./yabridge-setup/yabridge-installer.sh
```

## Step 2
Download your favourite Windows VST/CLAP installer (`.exe`/`.msi`) and simply **double-click** it.

You’ll be prompted to choose between:

- **Windows Application (System Wine)**
- **Audio Plugin Installer (Yabridge Wine)**

![Wine-Version-Selector](res/wine-selector-screenshot.png)

Choose **Audio Plugin Installer (Yabridge Wine)** to install into yabridge’s isolated wine environment.

## Step 3
Open your DAW and **rescan plugins**.  
On first launch, some plugins may install extra components; that’s typically one-time.

---

## Requirements

- **x86_64** system only.  
- Debian/Ubuntu or other apt-based distro.  
- Working **apt** and internet connection.  
- **zenity** installed for the selection dialog (`sudo apt-get install -y zenity`).  
- WineHQ must provide `wine-staging 9.21` for your distro `ID` and `VERSION_CODENAME`.  
- Vulkan-capable GPU and driver (with `vulkaninfo` working) if you want DXVK applied.  
- Sufficient permissions to install system packages and create files under `/usr/local/bin`, `/opt`, and `$HOME/.local/share`.

---

## What the script does (summary)

- Verifies you’re on **x86_64**; exits otherwise.  
- Reads your distro info from `/etc/os-release` and checks **WineHQ** availability for your `ID` and `VERSION_CODENAME`.  
  - If WineHQ doesn’t provide packages for your distro/codename, the script **exits** with instructions.  
- Ensures **i386** architecture is enabled if needed.  
- Installs **system wine** (and **winetricks** if available) from your current repos; if wine isn’t available there, it **adds WineHQ repos** and installs.  
- Determines **system wine** path and prints its version.  
- Ensures **WineHQ repos** are present (adds them if not) so it can download the pinned side-by-side wine.  
- Downloads **wine-staging 9.21** Debian packages (amd64/i386) and extracts them to:
  ```
  /opt/wine-staging-9.21/
  ```
- Downloads **yabridge 5.1.1** and installs to:
  ```
  $HOME/.local/share/yabridge
  ```
- Creates the environment wrapper:
  ```
  /usr/local/bin/yb-env
  ```
  which runs commands inside the side wine.  
- **Wraps** `yabridge-host.exe` and `yabridge-host-32.exe` to always run through `yb-env`.  
- Pre-creates and **registers common plugin folders** with `yabridgectl add`.  
- Installs the chooser script:
  ```
  /usr/local/bin/wine-version-selector
  ```
  and sets it as the default handler for `.exe` and `.msi`.  
  When you pick **Yabridge Wine**, it also runs `yabridgectl sync`.  
- If `winetricks` is available **and** Vulkan is detected, applies `winetricks dxvk` to the yabridge prefix to fix many plugin UIs.

---

## Details

### Separate wine installation (side-by-side)
Yabridge 5.1.1 requires **wine-staging 9.21**.  
Instead of freezing your system wine at that version, this script installs that exact version **side-by-side** under:

```
/opt/wine-staging-9.21/
```

Your **system wine** can then update independently.

The script also installs **system wine** + **i386** support (and **winetricks** if available) from your repos or WineHQ.

### Yabridge install & prefix
Yabridge is installed to:

```
$HOME/.local/share/yabridge
```

Default isolated prefix:

```
$HOME/.wine-yb
```

If `winetricks` is available and **Vulkan** works on your system, the script applies:

```
winetricks dxvk
```

to `$HOME/.wine-yb` (improves GUI rendering for many plugins).

### `yb-env` wrapper
Created at:

```
/usr/local/bin/yb-env
```

Runs any command inside the side wine environment. Examples:

```bash
yb-env wine --version
# wine-9.21 (Staging)

yb-env winetricks dxvk
# Applies DXVK to $HOME/.wine-yb if winetricks is installed
```

> Note: `yb-env` respects an existing `WINEPREFIX`. If `WINEPREFIX` is **unset**, it defaults to `$HOME/.wine-yb`.

### Wrapping yabridge hosts
The script replaces:

- `yabridge-host.exe`
- `yabridge-host-32.exe`

with small launchers that call their `.raw` counterparts through `yb-env`.  
This guarantees plugins always run in the correct wine and prefix.

### Predefined plugin folders
These folders are created (if missing) and added to yabridge’s search paths:

- `C:/Program Files/Common Files/VST3`
- `C:/Program Files/Common Files/CLAP`
- `C:/Program Files (x86)/Common Files/CLAP`
- `C:/Program Files/VST Plugins`
- `C:/Program Files/Steinberg/VSTPlugins`
- `C:/Program Files/Common Files/VST2`
- `C:/Program Files/Common Files/Steinberg/VST2`

### Wine Version Selector
Installed at:

```
/usr/local/bin/wine-version-selector
```

When you open a `.exe` or `.msi`, it prompts:

- **Windows Application (System Wine)**
- **Audio Plugin Installer (Yabridge Wine)**

Picking **Yabridge Wine** runs the installer in the side environment and then:

```
yabridgectl sync
```

The script also creates:

```
$HOME/.local/share/applications/wine-version-selector.desktop
```

and registers it as the default handler for `.exe` and `.msi` via `xdg-mime`.  
The selector uses **zenity** for the GUI prompt (install `zenity` if your desktop doesn’t include it).

![Wine-Version-Selector](res/wine-selector-screenshot.png)

---

## Warnings

- **Do NOT run standalone Windows apps** that plugin installers might add to your menu/desktop.  
  They launch with **system wine** and can **break** the yabridge environment.  
- Always use the plugins **inside your DAW**, not as standalone apps.

---

## Uninstall — Remove Everything

To fully remove all changes made by the script:

1. **Remove side Wine installation**  
   ```bash
   sudo rm -rf /opt/wine-staging-9.21
   ```

2. **Remove Yabridge installation**  
   ```bash
   rm -rf "$HOME/.local/share/yabridge"
   ```

3. **Remove the default Yabridge wine prefix**  
   ```bash
   rm -rf "$HOME/.wine-yb"
   ```

4. **Remove wrapper scripts and selector**  
   ```bash
   sudo rm -f /usr/local/bin/yb-env
   sudo rm -f /usr/local/bin/wine-version-selector
   rm -f "$HOME/.local/share/applications/wine-version-selector.desktop"
   ```

5. **Optionally remove WineHQ repository and key** (if you no longer want them)  
   ```bash
   sudo rm -f /etc/apt/sources.list.d/winehq.sources
   sudo rm -f /etc/apt/keyrings/winehq.gpg
   sudo apt-get update
   ```

---

## FAQ

**Where are the main pieces installed?**
- Side wine: `/opt/wine-staging-9.21/`
- Yabridge: `$HOME/.local/share/yabridge`
- Default prefix: `$HOME/.wine-yb`
- Environment wrapper: `/usr/local/bin/yb-env`
- Chooser: `/usr/local/bin/wine-version-selector`

**How do I check which wine my plugin uses?**  
Everything launched by yabridge hosts goes through `yb-env`, so:

```bash
yb-env wine --version
```

should show `wine-9.21 (Staging)`.

---

## TODO
- Add known yabridge groupings/configurations.
- More testing.
