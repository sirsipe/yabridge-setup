#!/bin/sh

###
# Run as NORMAL USER. Do not run as sudo.
#
# See https://github.com/sirsipe/yabridge-setup/blob/main/README.md
#
###

# Exit immediately if any command fails.
set -e

### DEFINES -->
## -- Versions and install locations --
WINE_BRANCH=staging
WINE_VERSION=9.21
WINE_INSTALL_LOCATION=/opt/wine-${WINE_BRANCH}-${WINE_VERSION}
DEFAULT_WINEPREFIX=$HOME/.wine-yb
YABRIDGE_VER=5.1.1
YABRIDGE_INSTALL_LOCATION=$HOME/.local/share
## -- Commands --
YB_ENV=yb-env
WV_SELECTOR=wine-version-selector
TARGET=/usr/local/bin
### <-- DEFINES

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
### Includes
. "${SCRIPT_DIR}/functions.sh"
. /etc/os-release

WINHQ_ADDED="n"

### -- ADDITIONAL FUNCTIONS -->

### Function to enable i386 architecture if not enabled yet.
ensure_i386_architecture_is_set() {
  if ! is_i386_architecture_enabled; then  

    echo "Enabling i386 architecture..."
    run_quiet sudo dpkg --add-architecture i386
    run_quiet sudo apt-get update
    echo "...OK!" 

    if ! is_i386_architecture_enabled; then
      echo "ERROR: It still looks like i386 architecture is not enabled. That's unexpected."
      exit 1
    fi  
  fi  
}

### Function to install WineHQ repos
install_winehq_repos() {

  if is_winehq_already_in_apt_sources; then
    echo "ERROR: Calling install_winehq_repos when WineHQ is already in repos!"
    exit 1
  fi

  if [ -z "${DISTRO_ID}" ] || [ -z "${OS_CODENAME}" ]; then
    echo "ERROR: DISTRO_ID and OS_CODENAME variables must be set before calling install_winehq_repos!"
    exit 1
  fi

  ensure_i386_architecture_is_set

  echo "Installing WineHQ gpg key..."
  wget -qO- https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor | sudo tee /etc/apt/keyrings/winehq.gpg > /dev/null
  echo "..OK!"
  
  echo "Adding sources and updating package cache..."
  sed -e "s|@@DISTRO_ID@@|${DISTRO_ID}|g" \
    -e "s|@@OS_CODENAME@@|${OS_CODENAME}|g" \
    "${SCRIPT_DIR}/templates/winehq.sources.template" | sudo tee "/etc/apt/sources.list.d/winehq.sources" > /dev/null
  run_quiet sudo apt-get update
  echo "...OK!" 
  
  WINHQ_ADDED="y"

  if ! is_winehq_already_in_apt_sources; then
    echo "ERROR: WineHQ repo still doesn't seem available."
    exit 1
  fi
}

### this function installs system wine from already existing repos
### or adds WineHQ repos and calls itself recursively if package is not available. 
### OS_CODENAME and DISTRO_ID should be set before calling this
install_system_wine() {
  ### Install wine (and winetricks) if they are available in current repos.
  if ! is_command_installed "wine" && is_apt_package_available "wine"; then 

    echo "System Wine is not installed, but it's available. Let's install that."  

    ensure_i386_architecture_is_set

    if ! is_command_installed "winetricks" && is_apt_package_available "winetricks"; then 

      echo "Looks like 'winetricks' is available too, so let's install both."
      echo "Installing 'wine' and 'winetricks'..."
      run_indented sudo apt-get install -y wine winetricks  

    else  

      echo "Installing 'wine'..."
      run_indented sudo apt-get install -y wine 

    fi
    echo "...OK!" 

  elif ! is_command_installed "wine" && ! is_apt_package_available "wine" && is_winehq_already_in_apt_sources; then 

    echo "ERROR: WineHQ repo is already set but 'wine' is not installed nor available."
    exit 1  

  elif is_command_installed "wine" && ! is_command_installed "winetricks" && ! is_apt_package_available "winetricks"; then  

    if ! is_i386_architecture_enabled; then
      echo "Wine has been installed but without i386 architecture. Not sure what to do."
      echo "Maybe remove wine manually and try this script again?"
      exit 1
    fi

    echo "System Wine is already installed, but 'winetricks' is not. Installing winetricks..."
    run_indented sudo apt-get install -y winetricks
    echo "...OK!" 

  elif is_command_installed "wine" && is_command_installed "winetricks"; then
    
    if ! is_i386_architecture_enabled; then
      echo "Wine has been installed but without i386 architecture. Not sure what to do."
      echo "Maybe remove wine manually and try this script again?"
      exit 1
    fi

    echo "System Wine and 'winetricks' are already installed. Good!"  

  elif ! is_winehq_already_in_apt_sources && [ -n "${DISTRO_ID}" ] && [ -n "${OS_CODENAME}" ]; then 

    echo "Looks like wine is not available in your current repos. Let's add WineHQ repos."
    install_winehq_repos

    ## Call recursively again.
    install_system_wine

  else

    echo "ERROR: Unknown case. Exiting."
    exit 1

  fi  
} 

### This function replaces given executable with a script
### that calls in in context of YB_ENV.
### The original executable name is appended with ".raw".
wrap_with_YB_ENV() {
  local orig="$1"
  local path_resolved
  path_resolved=$(realpath "$orig")
  
  if [ -f "${path_resolved}.raw" ]; then
    echo "ERROR: '${path_resolved}.raw' already exists!"
    exit 1
  fi

  mv "${path_resolved}" "${path_resolved}.raw"
  cat > "${path_resolved}" <<EOF
#!/bin/sh

exec "${TARGET}/${YB_ENV}" "${path_resolved}.raw" "\$@"
EOF
  
  chmod +x "$1"
  echo "Wrapped '${path_resolved}' with '${TARGET}/${YB_ENV}'." 
}


### Pre-create plugin folders and register them
pre_add_plugin_folder() {
    echo "Adding \"$1\" to yabridge paths..."
    mkdir -p "$1"
    $TARGET/$YB_ENV "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridgectl" add "$1"
    echo "...done!"
}


### <-- ADDITIONAL FUNCTIONS --

### THE SCRIPT ---->

### Get from /etc/os-release
OS_CODENAME=$VERSION_CODENAME
DISTRO_ID=$ID
echo "Your distribution's id is '${DISTRO_ID}' and codename is '${OS_CODENAME}'."

### Ensure we are in x86_64 system.
if ! is_system_64bit; then
  echo "ERROR: Expected x86_64 system."
  exit 1
fi

### Check if yabridge is already installed
if directory_exists "${YABRIDGE_INSTALL_LOCATION}/yabridge"; then
  echo
  echo "Looks like yabridge is already installed (at '${YABRIDGE_INSTALL_LOCATION}/yabridge')."
  echo "If you continue, it will removed and reinstalled."
  read -p "Do you want to continue? [y/N]: " answer

  case "$answer" in
    [yY]) ;; # Just continue
    *)    echo "User aborted."; exit 1;;
  esac

elif is_command_installed "yabridgectl"; then

  echo "Yabridge seems to be installed already, but it's not"
  echo "at the expected path ('${YABRIDGE_INSTALL_LOCATION}/yabridge')."
  echo "Not sure what to do. Exiting."
  exit 1

fi

echo
### If WineHQ repos are not yet added, check that we can find them for current distribution.
### If we can't, then we must exit immediately.
if is_winehq_already_in_apt_sources; then

  echo "WineHQ repos are already added to your system."
  OS_CODENAME=$(get_winehq_suite)
  echo "Detected WineHQ codename: ${OS_CODENAME}"

else
  echo "WineHQ repos not yet added. Attempting to resolve..."
  
  if check_WineHQ_repo_exists "${DISTRO_ID}" "${OS_CODENAME}"; then
    echo "WineHQ Repository FOUND!"
  else
    echo "ERROR: Couldn't find WineHQ repository for your Linux distribution."
    echo "Check available repos from https://gitlab.winehq.org/wine/wine/-/wikis/Debian-Ubuntu"
    echo "and compare them to your distribution id and codename."
    echo "You might have better luck, if you override OS_CODENAME and DISTRO_ID variables from the script."
    exit 1
  fi
fi

echo
### Refresh packages
echo "Refreshing package cache (sudo apt-get update). Password might be prompted."
run_quiet sudo apt-get update
echo "Package cache updated."

echo
### Install wine using current repos or WineHQ repos if not available.
install_system_wine
SYSTEM_WINE=$(get_system_wine_path)
echo "Your system wine is: $(${SYSTEM_WINE} --version)"

### Now check if we previously didn't install WineHQ repos. We need them now.
if ! is_winehq_already_in_apt_sources; then
  echo
  install_winehq_repos
  
fi


### Create temporary folder that gets destroyed after.
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT
echo
echo "Downloading wine-${WINE_BRANCH}-${WINE_VERSION}..."
cd "$TMPDIR" || exit 1

run_indented apt-get download wine-${WINE_BRANCH}:amd64=${WINE_VERSION}~${OS_CODENAME}-1
run_indented apt-get download wine-${WINE_BRANCH}-amd64=${WINE_VERSION}~${OS_CODENAME}-1
run_indented apt-get download wine-${WINE_BRANCH}-i386=${WINE_VERSION}~${OS_CODENAME}-1

if [ "${WINHQ_ADDED}" = "y" ]; then
  echo
  echo "Removing WineHQ repos as they are not needed..."
  sudo rm -f /etc/apt/sources.list.d/winehq.sources
  if ! grep -r --quiet 'dl.winehq.org' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    sudo rm -f /etc/apt/keyrings/winehq.gpg
  fi
  run_quiet sudo apt-get update
  echo "...OK!" 
fi

### Prepare the install target
sudo rm -rf "${WINE_INSTALL_LOCATION}"
sudo mkdir -p "${WINE_INSTALL_LOCATION}"

echo
echo "Installing wine-${WINE_BRANCH}-${WINE_VERSION}..."
### Extract the dep packages to target install location
for deb in *.deb; do
    sudo dpkg-deb -x "$deb" "${WINE_INSTALL_LOCATION}"
done
echo "...OK!"

echo
echo "Downloading and installing yabridge-${YABRIDGE_VER}..."
rm -rf "${YABRIDGE_INSTALL_LOCATION}/yabridge"
### Download yabridge and extract to target folder.
wget -q https://github.com/robbert-vdh/yabridge/releases/download/$YABRIDGE_VER/yabridge-${YABRIDGE_VER}.tar.gz
tar -C "${YABRIDGE_INSTALL_LOCATION}" -xavf yabridge-${YABRIDGE_VER}.tar.gz > /dev/null
echo "...OK!"

cd - > /dev/null || exit 1  # exit TMPDIR


### yabridge's host executables should always use the secondary wine.
echo
wrap_with_YB_ENV "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridge-host-32.exe"
wrap_with_YB_ENV "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridge-host.exe"


echo
echo "Installing '${TARGET}/${YB_ENV}'"
sed -e "s|@@DEFAULT_WINEPREFIX@@|${DEFAULT_WINEPREFIX}|g" \
    -e "s|@@WINE_INSTALL_LOCATION@@|${WINE_INSTALL_LOCATION}|g" \
    -e "s|@@WINE_BRANCH@@|${WINE_BRANCH}|g" \
    "${SCRIPT_DIR}/templates/yb-env.template" | sudo tee "${TARGET}/${YB_ENV}" > /dev/null
sudo chmod +x "${TARGET}/${YB_ENV}"

echo "Installing '${TARGET}/${WV_SELECTOR}'"
sed -e "s|@@SYSTEM_WINE@@|${SYSTEM_WINE}|g" \
    -e "s|@@TARGET@@|${TARGET}|g" \
    -e "s|@@YB_ENV@@|${YB_ENV}|g" \
    -e "s|@@YABRIDGE_INSTALL_LOCATION@@|${YABRIDGE_INSTALL_LOCATION}|g" \
    "${SCRIPT_DIR}/templates/wine-version-selector.template" | sudo tee "${TARGET}/${WV_SELECTOR}" > /dev/null
sudo chmod +x "${TARGET}/${WV_SELECTOR}"

echo "Creating '$HOME/.local/share/applications/${WV_SELECTOR}.desktop'"
mkdir -p "$HOME/.local/share/applications"
sed -e "s|@@EXECUTABLE@@|${TARGET}/${WV_SELECTOR}|g" \
    "${SCRIPT_DIR}/templates/wine-version-selector.desktop.template" > "$HOME/.local/share/applications/${WV_SELECTOR}.desktop"

echo
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/VST3"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/CLAP"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files (x86)/Common Files/CLAP"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/VST Plugins"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Steinberg/VSTPlugins"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/VST2"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/Steinberg/VST2"

### Register it as default handler
echo
echo "Registering '${WV_SELECTOR}' as default exe/msi application..."
xdg-mime default "${WV_SELECTOR}.desktop" application/x-ms-dos-executable
xdg-mime default "${WV_SELECTOR}.desktop" application/x-msi
echo "...OK!"

if ! is_command_installed "winetricks" && is_apt_package_available "winetricks"; then
  echo
  echo "Installing 'winetricks'..."
  run_indented sudo apt-get install -y winetricks
  echo "...OK!"
fi

if is_command_installed "winetricks" && has_vulkan; then
  echo
  echo "Applying 'winetricks dxvk' to '${DEFAULT_WINEPREFIX}'..."
  run_indented $TARGET/$YB_ENV winetricks dxvk
  echo "...OK!"
elif has_vulkan; then
  echo
  echo "Seems that 'winetricks' is not available, so I'm unable to add"
  echo "'dxvk patch' that fixes the UI issues of many plugins." 
fi

echo
echo
echo "All Good!" 
echo
echo "Simply double click any Windows plugin installer (exe/msi) you've downloaded"
echo "and choose 'Audio Plugin Installer (Yabridge Wine)' to install it."
echo 
echo "Once installed, simply use your favourite DAW,"
echo "but remember to re-scan plugins with it!"
echo
echo