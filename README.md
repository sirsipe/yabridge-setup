# !!! WORK IN PROGRESS - DO NOT USE YET !!!

# Yabridge installer (for Ubuntu Studio)
This is a script build on Ubuntu Studio 24.04, but it could work on other debian based systems too. The attempt is to simplify the magical install procedure of Windows VSTs/CLAPs up to the point that after running this script, user never needs to use terminal to install more such plugins.

RUN AS USER, NOT AS SUDO
Password will be prompted when needed.

1. Download [ubuntu-yabridge-installer.sh](ubuntu-yabridge-installer.sh)
2. Add executable rights for it with `chmod +x ubuntu-yabridge-installer.sh`
3. Run `./ubuntu-yabridge-installer.sh`

## Why
Since yabridge requires very specific wine version to run (wine-staging-9.21 as of 28.7.2025), and it's not reasonable to hold "system wine" back just for that purpose, this script is designed to setup secondary wine version that is separated from the system wine. This way system can always be kept up-to-date. This script also installs yabridge and creates isolated windows environment "WINEPREFIX" that is used with specifically tailored custom commands (wine-yb, wine-version-selector, yabridgectl).

The secondary wine installation is NOT fully contanerized, but depends on multiple libraries that are easiest to obtain by installing latest version of wine to the system. This is why this script will also install wine to the system, and it has to install also i386 libraries for it. **This is fragile setup** as it assumes latest version of wine has all the same dependencies.

## What this script does:
- Enables i386 architecture repos
- Installs wine with all recommended packages
- Adds official WineHQ Repository's PGP signature to keyring

- Retrieves specific version (wine-staging-9.21) from WineHQ repos and unpacks it to /opt/wine-staging-9.21/ so e.g. its binaries are in /opt/wine-staging-9.21/wine-staging/opt/bin/.

- Downloads yabridge and extracts it to $HOME/.local/share/ (as is recommended). 

- Creates new command: /usr/local/bin/wine-yb. This command points to the secondary 64bit wine with default WINEPREFIX of $HOME/.wine-yb.

- Creates new command: /usr/local/bin/yabridgectl. This command calls $HOME/.local/share/yabridge/yabridgectl with WINELOADER set to the secondary wine, and WINEPREFIX set to $HOME/.wine-yb.

- Creates new command: /usr/local/bin/wine-version-selector. This is a script that prompts user whether to use system wine or "yabridge wine". This script is set as default .exe and .msi mimetype handler. If yabridge version is chosen, then after the program exits, also "yabridgectl sync" is called. 

- Pre-adds known VST2, CLAP and VST3 folders to yabridge from $HOME/.wine-yb WINEPREFIX.
