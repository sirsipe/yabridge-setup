# Yabridge installer (V2)

**This script is for Ubuntu/Debian based distributions.**

Most of the Windows VST/CLAP plugins work great with following combination:
 - Yabridge 5.1.1 ([Yabridge at GitHub](https://github.com/robbert-vdh/yabridge))
 - wine-staging-9.21 ([WineHQ](https://gitlab.winehq.org/wine/wine/-/wikis/Debian-Ubuntu#third-party-repositories), [The issue with newer wine](https://github.com/robbert-vdh/yabridge/issues/382))
 - winetricks dxvk

Since **wine-staging-9.21** is quite old and it's unreasonable (and often not even possible) to downgrade system wine just for good plugin compatibility, this script does an isolated **wine-staging-9.21** installation and patches yabridge to use that isolated wine version. It will also create an isolated wineprefix (*$HOME/.wine-yb*) instead of using the default one (*$HOME/.wine*), which is then used by default by the patched **yabridge** version.

Unfortunately **wine-staging-9.21** is not available in repos for many of the latest OS versions. However, using *as latest repo as possible* seems to be working nicely although it's not very *kosher*.

Should work with:
 - All Ubuntu flavors; using **noble** repos for questing/plucky and above.
 - Pop!_OS; same as Ubuntu
 - Elementary OS; circle, horus; using Ubuntu **noble** repos for others.
 - Mint 21-22; same as Ubuntu
 - Debian; bookworm, trixie; using **trixie** repos for forky and above. However, **winetricks** doesn't seem to be available at least for Trixie, so the script just won't apply the dxvk -patch for it.

## Installation

### Step 1

You need **git**.

```bash
sudo apt install git
```

Other prerequisites are prompted by the installer.
**Run as normal user, NOT as sudo.**  

```bash
git clone https://github.com/sirsipe/yabridge-setup
./yabridge-setup/yabridge-installer.sh
rm -rf yabridge-setup #cleanup
```

### Step 2

Download your favourite Windows VST/CLAP installer (`.exe`/`.msi`) and simply **double-click** it.

You’ll be prompted to choose between:

- **Windows Application (System Wine)**
- **Audio Plugin Installer (Yabridge Wine)**

![Wine-Version-Selector](res/wine-selector-screenshot.png)

Choose **Audio Plugin Installer (Yabridge Wine)** to install into yabridge’s isolated wine environment.

**!!! NOTE !!! Do NOT run anything from the desktop! If you launch e.g. a standalone plugin from desktop, it might use system wine, which WILL corrupt the wine-yb -environment.**

### Step 3

Open your DAW and **rescan plugins**.  
On first launch, some plugins may install extra components; that’s typically one-time.

## Testing & Notes

Tested with:
 - ubuntustudio-24.04.3-dvd-amd64.iso
 - ubuntustudio-25.10-desktop-amd64.iso
 - ubuntu-24.04.3-desktop-amd64.iso
 - pop-os_22.04_amd64_intel_58.iso
 - linuxmint-22.2-cinnamon-64bit.iso
 - debian-live-13.2.0-amd64-kde.iso (winetricks not available) 

Test method: Used above live images in VirtualBox, with pass-through USB audio interface. After running the script, installed [NAM Universal by Wavemind](https://wavemind.net/software) and downloaded [REAPER for Linux](https://www.reaper.fm/download.php). Launched REAPER without installing, and used the passed-through USB audio interface in REAPER with ALSA; 256/48kHz. 

-> [NAM Universal](https://wavemind.net/software) works in all above cases, except without the winetricks in Debian, the GUI is not responsive. I know that also e.g. [NeuralDSP](https://neuraldsp.com/) works the same, as long as you get through its installer which has very severe GUI issues. I've also personally tested that [Melodyne](https://www.celemony.com/en/melodyne/what-is-melodyne) works with this setup (at least in Ubuntu Studio 24.04) and also [Neural Amp Modeler](https://www.neuralampmodeler.com/) (although there are plenty of Linux native options for it, too).

### Take care of your licenses!

E.g. with [NeuralDSP](https://neuraldsp.com/), it seems that license activations get consumed if you recreate the wine-yb environment; which means that the license is not just hardware-bound, but also OS bound. I'm not sure if it helps or not, but I'd recommend taking periodic backups after activation:

```bash
tar -cf wine-yb-licenses-backup.tar $HOME/.wine-yb
```

## Requirements

- **x86_64** system only.  
- Debian/Ubuntu based distro.  
- Working **apt-get** and internet connection.  
- **zenity**, **wget**, **wine** (will be installed by the script)
- **winetricks** (optional, recommended)

## Install paths

 - wine-staging-9.21 folder: `$HOME/.local/share/wine-staging-9.21/`
 - yabridge (5.1.1) folder: `$HOME/.local/share/yabridge/`
 - **wine-version-selector**: `$HOME/.local/share/yb-launcher/wine-version-selector`
 - **yb-env**: `$HOME/.local/share/yb-launcher/yb-env`
 - dedicated wineprefix: `$HOME/.wine-yb`

The path `$HOME/.local/share/yb-launcher/` is added to **$HOME/.bashrc** so the commands `yb-env` and `wine-version-selector` can be used without full path. However, restart/relogin of the terminal is required after running the install script for that to become effective.

## Details

### yb-env

Installed at:

```
$HOME/.local/share/yb-launcher/yb-env
```

**yb-env** sets specific environment variables that causes **wine-staging-9.21** at `$HOME/.local/share/wine-staging-9.21/` to take priority for anything following the command. It will also set `WINEPREFIX` to `$HOME/.wine-yb`. 

For example:

```bash
yb-env wine --version
``` 

would return *wine-9.21 (Staging)* whereas 

```bash
wine --version
```

would return your system wine version.

To apply winetrics to your yabridge environment, you can simply do

```bash
yb-env winetricks dxvk
```

The path `$HOME/.local/share/yb-launcher/` is added to `.bashrc`, making `yb-env` invokeable without full path; but you must restart terminal after using the install script.

### How it patches yabridge

The script copies
- `yabridge-host.exe` -> `yabridge-host.exe.raw` 
- `yabridge-host-32.exe` -> `yabridge-host-32.exe.raw`
and then overrides `yabridge-host.exe` and `yabridge-host-32.exe` with launchers that call `yb-env yabridge-host.exe.raw` and `yb-env yabridge-host-32.exe.raw`. 

This guarantees plugins always run in the correct wine and prefix.

### wine-version-selector

Installed at:

```
$HOME/.local/share/yb-launcher/wine-version-selector
```

When you open a `.exe` or `.msi`, it prompts:

- **Windows Application (System Wine)**
- **Audio Plugin Installer (Yabridge Wine)**

Picking **Yabridge Wine** runs the installer in `yb-env' context and then:

```
yabridgectl sync
```

The script also creates:

```
$HOME/.local/share/applications/wine-version-selector.desktop
```

and registers it as the default handler for `.exe` and `.msi` via `xdg-mime`.  
The selector uses **zenity** for the GUI prompt.

![Wine-Version-Selector](res/wine-selector-screenshot.png)

The path `$HOME/.local/share/yb-launcher/` is added to `.bashrc`, making `wine-version-selector` invokeable without full path; but you must restart terminal after using the install script.

## Predefined plugin folders
These folders are created (if missing) and added to yabridge’s search paths:

`C:/` is `$HOME/.wine-yb/drive_c/`

- `C:/Program Files/Common Files/VST3`
- `C:/Program Files/Common Files/CLAP`
- `C:/Program Files (x86)/Common Files/CLAP`
- `C:/Program Files/VST Plugins`
- `C:/Program Files/Steinberg/VSTPlugins`
- `C:/Program Files/Common Files/VST2`
- `C:/Program Files/Common Files/Steinberg/VST2`


## Version 1 vs Version 2

This is the 2nd version of the script. The first version was introduce in [this YouTube Video](https://www.youtube.com/watch?v=2-t1uocytKs).

- Version 2 tries to solve the OS_CODENAME so that it works better with Debian, Mint, PopOs, Elementary OS; including also versions that do not have wine-staging-9.21 in the Wine-HQ repos anymore.
- Version 2 does not pollute your repositories, but uses temporary apt sources.
- If you have all requirements already installed, version 2 does everything with user privileges - everything is installed to userspace.
- Version 2 allows you to keep your existing wine -prefix
- Version 2 allows you to NOT install winetricks dxvk (although it's recommended)
