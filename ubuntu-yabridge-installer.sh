#!/usr/bin/env bash

##
#
# Run as NORMAL USER. Do not run as sudo.
#
# Since yabridge requires very specific wine version to run (wine-staging-9.21),
# and it's not reasonable to hold "system wine" back just for that purpose,
# this script is designed to setup secondary wine version that is separated
# from the system wine. This script also installs yabridge and creates wine
#
# The secondary wine installation is not fully contanerized, but depends on multiple
# libraries that are easiest to obtain by installing latest version of wine. 
# This is fragile setup as it assumes latest version of wine has all the same dependencies.
#
# What this script does:
#
# - Enables i386 architecture repos
# - Installs wine with all recommended packages
# - Adds official WineHQ Repository's PGP signature to keyring
#
# - Retrieves specific version (wine-staging-9.21) from WineHQ repos
#   and unpacks it to /opt/wine-staging-9.21/ so e.g. its binaries are in
#   /opt/wine-staging-9.21/wine-staging/opt/bin/.
#
# - Downloads yabridge and extracts it to $HOME/.local/share/ (as is recommended). 
#
# - Creates new command: /usr/local/bin/wine-yb
#       Points to the secondary 64bit wine with default WINEPREFIX of $HOME/.wine-yb.
#
# - Creates new command: /usr/local/bin/yabridgectl
#       Calls $HOME/.local/share/yabridge/yabridgectl with WINELOADER 
#       set to secondary wine, and WINEPREFIX set to $HOME/.wine-yb.
#
# - Creates new command: /usr/local/bin/wine-version-selector
#       A script that prompts user whether to use system wine or "yabridge wine". 
#       This script is set as default .exe and .msi mimetype handler. If yabridge 
#       version is chosen, then after the program exits, also "yabridgectl sync" 
#       is called.
#
# - Pre-adds known VST2, CLAP and VST3 folders to yabridge from $HOME/.wine-yb WINEPREFIX.
#
#
# Author: Simo Erkinheimo, 28.7.2025
##

# Exit immediately if any command fails.
set -e

### USER DEFINES -->
## -- Versions and install locations --
WINE_BRANCH=staging
WINE_VERSION=9.21
WINE_INSTALL_LOCATION=/opt/wine-${WINE_BRANCH}-${WINE_VERSION}
WINEPREFIX=$HOME/.wine-yb
YABRIDGE_VER=5.1.1
YABRIDGE_INSTALL_LOCATION=$HOME/.local/share
## -- Commands --
WINE_YB=wine-yb
YBCTL=yabridgectl
WV_SELECTOR=wine-version-selector
TARGET=/usr/local/bin
### <-- DEFINES

### Install Wine to the system
echo "Installing Wine + i386 architecture..."
sudo dpkg --add-architecture i386
sudo apt update
sudo apt-get install -y wine --install-recommends
echo "...wine installed!"

### Detect distribution codename. Needed to resolve correct repos.
OS_CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '"')
echo "Distribution codename is '${OS_CODENAME}'"

### Create temporary folder that gets destroyed after.
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

### Get and install WineHQ's gpg key. This has to be added to systemwide keyring to work.
### The sources list is temporary and given specifically for apt with APT_OPTS
### to avoid polluting the system with 3rd party repos.
wget -qO- https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor | sudo tee /etc/apt/keyrings/winehq.gpg > /dev/null
cat > "$TMPDIR/winehq.sources" <<EOF
Types: deb
Architectures: amd64 i386
URIs: https://dl.winehq.org/wine-builds/ubuntu/
Suites: ${OS_CODENAME}
Components: main
Signed-By: /etc/apt/keyrings/winehq.gpg
EOF

### Download the needed .dep packages from WineHQ repos
APT_OPTS=(
  -o Dir::Etc::SourceList="$TMPDIR/winehq.sources"
  -o Dir::Etc::SourceParts="-"  # disable source parts
  -o APT::Get::List-Cleanup="0"
)

sudo apt-get "${APT_OPTS[@]}" update

PACKAGES=(
  wine-${WINE_BRANCH}:amd64=${WINE_VERSION}~${OS_CODENAME}-1
  wine-${WINE_BRANCH}-amd64=${WINE_VERSION}~${OS_CODENAME}-1
  wine-${WINE_BRANCH}-i386=${WINE_VERSION}~${OS_CODENAME}-1
)

echo "Downloading wine-${WINE_BRANCH}-${WINE_VERSION}..."
DOWNLOAD_DIR="$TMPDIR/downloads"
mkdir -p "$DOWNLOAD_DIR"
pushd "$DOWNLOAD_DIR" > /dev/null

for pkg in "${PACKAGES[@]}"; do
    apt-get "${APT_OPTS[@]}" download "$pkg"
done

### Prepare the install target
sudo rm -rf "${WINE_INSTALL_LOCATION}"
sudo mkdir -p "${WINE_INSTALL_LOCATION}"

echo "Installing wine-${WINE_BRANCH}-${WINE_VERSION}..."
### Extract the dep packages to target install location
for deb in *.deb; do
    sudo dpkg-deb -x "$deb" "${WINE_INSTALL_LOCATION}"
done

echo "Downloading and installing yabridge-${YABRIDGE_VER}..."
rm -rf "${YABRIDGE_INSTALL_LOCATION}/yabridge"
### Download yabridge and extract to target folder.
wget -q https://github.com/robbert-vdh/yabridge/releases/download/$YABRIDGE_VER/yabridge-${YABRIDGE_VER}.tar.gz
tar -C "$YABRIDGE_INSTALL_LOCATION" -xavf yabridge-${YABRIDGE_VER}.tar.gz

popd > /dev/null  # exit DOWNLOAD_DIR

### This function replaces given executable with a script
### that defines WINLOADER pointing to the secondary wine
### installation before executing the original executable.
### The original executable name is appended with ".raw".
function wrap_with_wineloader() {
  local orig="$1"
  local path_resolved
  path_resolved=$(realpath "$orig")
  mv "$path_resolved" "$path_resolved.raw"
  cat > "$path_resolved" <<EOF
#!/bin/bash
WINELOADER=${WINE_INSTALL_LOCATION}/opt/wine-${WINE_BRANCH}/bin/wine
exec "${path_resolved}.raw" "\$@"
EOF
  
  chmod +x "$1"
}

### yabridge's host executables should always use the secondary wine.
wrap_with_wineloader "$YABRIDGE_INSTALL_LOCATION/yabridge/yabridge-host-32.exe"
wrap_with_wineloader "$YABRIDGE_INSTALL_LOCATION/yabridge/yabridge-host.exe"


### Creates a bash script with given name and given body,
### and installs it to $TARGET with sudo.
function create_command() {
  local script_name="$1"
  local script_body="$2"
  
  echo "Creating command ${script_name}..."
  # Write to temporary file
  local tmp_file="./${script_name}"
  echo "#!/bin/bash" > "$tmp_file"
  cat >> "$tmp_file" <<EOF
$script_body
EOF

  chmod +x "$tmp_file"
  sudo mv "$tmp_file" "$TARGET/$script_name"

  echo "...created and installed to ${TARGET}."

}

SCRIPTS_DIR="$TMPDIR/scripts"
mkdir -p "$SCRIPTS_DIR"
pushd "$SCRIPTS_DIR" > /dev/null

cmd_body='
export WINEPREFIX="$WINEPREFIX"
export WINEARCH="win64"
WINE_HOME="${WINE_INSTALL_LOCATION}/opt/wine-${WINE_BRANCH}"
export PATH="\$WINE_HOME/bin:$PATH"
export LD_LIBRARY_PATH="\$WINE_HOME/lib64:$LD_LIBRARY_PATH"
export WINESERVER="\$WINE_HOME/bin/wineserver"
export WINELOADER="\$WINE_HOME/bin/wine"
export WINE="\$WINELOADER"

exec "\$WINE" "\$@"'
create_command "$WINE_YB" "$cmd_body"

cmd_body='
export WINE="${WINE_INSTALL_LOCATION}/opt/wine-${WINE_BRANCH}/bin/wine"
export WINEPREFIX="$WINEPREFIX"
export WINELOADER="${WINE_INSTALL_LOCATION}/opt/wine-${WINE_BRANCH}/bin/wine"
exec "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridgectl" "\$@"'
create_command "$YBCTL" "$cmd_body"

cmd_body='
EXE="$1"
CHOICE=$(zenity --list --radiolist \
  --title="Select Wine version" \
  --text="What are you running?" \
  --column "" --column "Application Type (wine version)" --column "wine" \
  TRUE "Windows Application (System Wine)" "system-wine" \
  FALSE "Audio Plugin Installer (Yabridge Wine)" "yabridge-wine" \
  --hide-column=3 \
  --print-column=3)

case "$CHOICE" in
  system-wine)
    exec /usr/bin/wine "$EXE"
    ;;
  yabridge-wine)
    /usr/local/bin/wine-yb "$EXE"
    if [ $? -eq 0 ]; then
      /usr/local/bin/yabridgectl sync
      exit 0
    else
      exit 1
    fi
    ;;
  *)
    echo "Cancelled"
    exit 1
    ;;
esac'
create_command "$WV_SELECTOR" "$cmd_body"

### Create a .desktop file for the selector
DESKTOP_FILE=~/.local/share/applications/$WV_SELECTOR.desktop
echo "Creating ${DESKTOP_FILE}..."
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Wine Version Selector
Exec=${TARGET}/${WV_SELECTOR} %f
Type=Application
MimeType=application/x-ms-dos-executable;application/x-msi;
NoDisplay=false
EOF

echo "...done!"

popd > /dev/null #exit SCRIPTS_DIR

### Pre-create plugin folders and register them
function pre_add_plugin_folder() {
    echo "Adding \"$1\" to yabridge paths..."
    mkdir -p "$1"
    WINELOADER="${WINE_INSTALL_LOCATION}/opt/wine-${WINE_BRANCH}/bin/wine" "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridgectl" add "$1"
    echo "...done!"
}

pre_add_plugin_folder "$WINEPREFIX/drive_c/Program Files/Common Files/VST3"
pre_add_plugin_folder "$WINEPREFIX/drive_c/Program Files/Common Files/CLAP"
pre_add_plugin_folder "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/CLAP"
pre_add_plugin_folder "$WINEPREFIX/drive_c/Program Files/VST Plugins"
pre_add_plugin_folder "$WINEPREFIX/drive_c/Program Files/Steinberg/VSTPlugins"
pre_add_plugin_folder "$WINEPREFIX/drive_c/Program Files/Common Files/VST2"
pre_add_plugin_folder "$WINEPREFIX/drive_c/Program Files/Common Files/Steinberg/VST2"

### Register it as default handler
echo "Registering ${DESKTOP_FILE} as default exe/msi application..."
xdg-mime default wine-version-selector.desktop application/x-ms-dos-executable
xdg-mime default wine-version-selector.desktop application/x-msi
echo "...done!"

echo
echo "All Good!" 
echo "Simply double click any Windows plugin installer you've downloaded and choose 'Audio Plugin Installer (Yabridge Wine)' to install it."
echo "Once installed, simply use your favourite DAW, but remember to re-scan plugins with it!"
