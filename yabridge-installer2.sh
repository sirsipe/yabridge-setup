#!/bin/sh

set -eu

# Include ID and VERSION_CODENAME
. /etc/os-release

# noble is the last ubuntu repo containing wine-staging-9.21
UBUNTU_FALLBACK_REPO=noble

# trixie is the last debian repo containing wine-staging-9.21
DEBIAN_FALLBACK_REPO=trixie

case "$ID" in
    ubuntu|pop|linuxmint|elementary)      
        DISTRO_ID=ubuntu
        case "$VERSION_CODENAME" in
            ## Ubuntu and pop
            questing|plucky)             
                echo
                echo "Using '${UBUNTU_FALLBACK_REPO}' repositories since WineHQ doesn't contain wine-staging-9.21 for '${ID} ${VERSION_CODENAME}'.";
                echo "This might not be....kosher."
                echo
                OS_CODENAME=${UBUNTU_FALLBACK_REPO}
                ;;
            noble|jammy|focal)
                OS_CODENAME=${VERSION_CODENAME}
                ;;

            ## Mint
            wilma)
                # Mint 22 is based on ubuntu noble
                OS_CODENAME=noble
                ;;
            vanessa|vera|victoria|virginia)
                # Mint 21 is based on ubuntu jammy
                OS_CODENAME=jammy
                ;;
            ulyana|ulyssa|uma|una)
                # Mint 20 is based on ubuntu focal
                OS_CODENAME=focal
                ;;

            #elementary
            circe)
                OS_CODENAME=noble
                ;;
            horus)
                OS_CODENAME=jammy
                ;;
        esac
        ;;
    debian)
        DISTRO_ID=debian
        case "$VERSION_CODENAME" in
            forky)
                echo
                echo "Using '${DEBIAN_FALLBACK_REPO}' repositories since WineHQ doesn't contain wine-staging-9.21 for '${ID} ${VERSION_CODENAME}'.";
                echo "This might not be....kosher."
                echo
                OS_CODENAME=${DEBIAN_FALLBACK_REPO}
                ;;
            trixie)
                OS_CODENAME=trixie
                ;;
            bookworm)
                OS_CODENAME=bookworm
                ;;
     esac
        ;;
esac


# Required environment variables
: "${DISTRO_ID:?Unable to resolve DISTRO_ID. Set it manually as environment variable and try again.}"
: "${OS_CODENAME:?Unable to resolve OS_CODENAME. Set it manually as environment variable and try again.}"

### Create temporary folder that gets destroyed after.
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

WINE_BRANCH="${WINE_BRANCH:-staging}"
WINE_VERSION="${WINE_VERSION:-9.21}"
WINE_INSTALL_LOCATION=$HOME/.local/share/wine-${WINE_BRANCH}-${WINE_VERSION}
WINE_BIN=${WINE_INSTALL_LOCATION}/opt/wine-staging/bin/wine

DEFAULT_WINEPREFIX="${DEFAULT_WINEPREFIX:-$HOME/.yb-wine}"

# Resolve current directory 
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
THIS_SCRIPT=${SCRIPT_DIR}/$(basename -- "$0")

# Helper function to remove warning vomit from apt-get
run_filtered() {
    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        printf "%s\n" "$output" | grep -viE '^(W:|WARNING:|Ign:)' >&2
        return "$status"
    fi
}


## Check for "system-wine"
set +e
SYSTEM_WINE=$(command -v wine)
set -e

if [ -z "$SYSTEM_WINE" ]; then
    echo
    echo "System wine is not found but it's required to be installed."
    echo "Do you want me to execute following statements?"
    echo
    echo "  sudo dpkg --add-architecture i386"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install wine wine32:i386"
    echo 
    printf "Execute (password might be prompted)? [y/N]: " >&2
    IFS= read answer

    case "$answer" in
        [yY])
            echo "This might take a while..."

            if ! sudo dpkg --add-architecture i386; then
                echo "ERROR: Failed to add i386 architecture." >&2
                exit 1
            fi

            # Let's ignore all errors here as update very often has
            # some errors in live distro -versions.
            set -e
            sudo apt-get update 2>&1 /dev/null
            set +e
            
            if ! sudo apt-get install wine wine32:i386; then
                echo "ERROR: Failed to install wine / wine32:i386." >&2
                exit 1
            fi
            
            exec "$THIS_SCRIPT" "$@"
         ;; 
        *)    echo "User aborted."; exit 1;;
    esac
else
    echo
    echo "Your system wine is: $("$SYSTEM_WINE" --version)"
fi

# yabridge version and install location
YABRIDGE_VER="${YABRIDGE_VER:-5.1.1}"
YABRIDGE_INSTALL_LOCATION="${YABRIDGE_INSTALL_LOCATION:-$HOME/.local/share}"

# yb-env and wine-version-selector paths
YB_LAUNCHER_TARGET=$HOME/.local/share/yb-launcher
YB_ENV=yb-env
WV_SELECTOR=wine-version-selector
XDG_APP_PATH=$HOME/.local/share/applications/


# Get common functions
. "${SCRIPT_DIR}/functions.sh"


### Check if wine is already installed to given location
if directory_exists "${WINE_INSTALL_LOCATION}"; then
  echo
  echo "Looks like wine-${WINE_BRANCH}-${WINE_VERSION} is already installed (at '${WINE_INSTALL_LOCATION}')."
  echo "If you continue, it will removed and reinstalled."
  printf "Do you want to continue? [y/N]: " >&2
  IFS= read answer

  case "$answer" in
    [yY]) ;; # Just continue
    *)    echo "User aborted."; exit 1;;
  esac
fi


### Check if yabridge is already installed
if directory_exists "${YABRIDGE_INSTALL_LOCATION}/yabridge"; then
  echo
  echo "Looks like yabridge is already installed (at '${YABRIDGE_INSTALL_LOCATION}/yabridge')."
  echo "If you continue, it will removed and reinstalled."
  printf "Do you want to continue? [y/N]: " >&2
  IFS= read answer


  case "$answer" in
    [yY]) ;; # Just continue
    *)    echo "User aborted."; exit 1;;
  esac
fi

### Check if yb-launcher is already installed
if directory_exists "${YB_LAUNCHER_TARGET}"; then
  echo
  echo "Looks like yb-launcher is already installed (at '${YB_LAUNCHER_TARGET}')."
  echo "If you continue, it will removed and reinstalled."
  printf "Do you want to continue? [y/N]: " >&2
  IFS= read answer

  case "$answer" in
    [yY]) ;; # Just continue
    *)    echo "User aborted."; exit 1;;
  esac
fi

echo
echo "Retrieving 'wine-${WINE_BRANCH}-${WINE_VERSION}' into ${WINE_INSTALL_LOCATION}"
echo "using DISTRO_ID '${DISTRO_ID}' and OS_CODENAME '${OS_CODENAME}'."

TEMP_REPO="${TMPDIR}/wine-temp-repo.list"
PKG_DIR="${TMPDIR}/wine-temp-packages"
mkdir -p "${PKG_DIR}"
APT_STATE_DIR="${TMPDIR}/wine-apt-state"
mkdir -p "${APT_STATE_DIR}"
touch "${APT_STATE_DIR}/status"


# Create temp-repo.list
sed -e "s|@@DISTRO_ID@@|${DISTRO_ID}|g" \
    -e "s|@@OS_CODENAME@@|${OS_CODENAME}|g" \
    "${SCRIPT_DIR}/templates/wine-repo.list.template" > "${TEMP_REPO}"




# Update package cache with the tempory repo
echo
echo "Updating temporary package cache..."
run_filtered apt-get -o Dir::State="${APT_STATE_DIR}" \
    -o Dir::State::status="${APT_STATE_DIR}/status" \
    -o Dir::Cache="${APT_STATE_DIR}" \
    -o Dir::Etc::sourcelist="${TEMP_REPO}" \
    -o Dir::Etc::sourceparts=- \
    -o APT::Get::List-Cleanup=0 \
    -o Acquire::Retries=0 \
    -o Acquire::http::Timeout=5 \
    -o Acquire::http::ConnectTimeout=3 \
    update
echo "...OK!"

# Download packages to temporary ${PKG_DIR}
echo
echo "Downloading packages..."
(
    cd "${PKG_DIR}"
    apt-get \
        -o Dir::State="${APT_STATE_DIR}" \
        -o Dir::State::status="${APT_STATE_DIR}/status" \
        -o Dir::Cache="${APT_STATE_DIR}" \
        -o Dir::Etc::sourcelist="${TEMP_REPO}" \
        -o Dir::Etc::sourceparts=- \
        -o APT::Get::List-Cleanup=0 \
        download \
        "wine-${WINE_BRANCH}:amd64=${WINE_VERSION}~${OS_CODENAME}-1" \
        "wine-${WINE_BRANCH}-amd64=${WINE_VERSION}~${OS_CODENAME}-1" \
        "wine-${WINE_BRANCH}-i386=${WINE_VERSION}~${OS_CODENAME}-1" 
)
echo "...OK!"

set +e
deb_count=$(find "${PKG_DIR}" -maxdepth 1 -name '*.deb' | wc -l || true)
set -e

if [ "$deb_count" -eq 0 ]; then
  echo "No .deb files found. Check DISTRO_ID, OS_CODENAME and WINE_VERSION." >&2
  exit 1
fi

### Prepare the install target
echo
echo "Installing packages..."
rm -rf "${WINE_INSTALL_LOCATION}"
mkdir -p "${WINE_INSTALL_LOCATION}"
# Install deps to target
for deb in "${PKG_DIR}"/*.deb; do
  [ -f "$deb" ] || continue
  dpkg-deb -x "$deb" "${WINE_INSTALL_LOCATION}"
done
echo "...OK!"

## Install yabridge
echo
echo "Downloading and installing yabridge-${YABRIDGE_VER}..."
rm -rf "${YABRIDGE_INSTALL_LOCATION}/yabridge"
wget -P "${PKG_DIR}" -q https://github.com/robbert-vdh/yabridge/releases/download/$YABRIDGE_VER/yabridge-${YABRIDGE_VER}.tar.gz
tar -C "${YABRIDGE_INSTALL_LOCATION}" -xavf "${PKG_DIR}/yabridge-${YABRIDGE_VER}.tar.gz" > /dev/null 
echo "...OK!"

## Install yb-env
echo
echo "Installing '${YB_LAUNCHER_TARGET}/${YB_ENV}' with default wine prefix '${DEFAULT_WINEPREFIX}'..."
mkdir -p "${YB_LAUNCHER_TARGET}"
sed -e "s|@@DEFAULT_WINEPREFIX@@|${DEFAULT_WINEPREFIX}|g" \
    -e "s|@@WINE_INSTALL_LOCATION@@|${WINE_INSTALL_LOCATION}|g" \
    -e "s|@@WINE_BRANCH@@|${WINE_BRANCH}|g" \
    "${SCRIPT_DIR}/templates/yb-env2.template" > "${YB_LAUNCHER_TARGET}/${YB_ENV}"
chmod +x "${YB_LAUNCHER_TARGET}/${YB_ENV}"
echo "...OK!"


## Init the wine prefix
echo
echo "Initializing '${DEFAULT_WINEPREFIX}'..."
rm -rf "${DEFAULT_WINEPREFIX}"
WINEARCH="win64" "${YB_LAUNCHER_TARGET}/${YB_ENV}" wineboot --init 2>&1 /dev/null


## Install wine-version-selector
echo
echo "Installing '${YB_LAUNCHER_TARGET}/${WV_SELECTOR}'..."
mkdir -p "${YB_LAUNCHER_TARGET}"
sed -e "s|@@SYSTEM_WINE@@|${SYSTEM_WINE}|g" \
    -e "s|@@TARGET@@|${YB_LAUNCHER_TARGET}|g" \
    -e "s|@@YB_ENV@@|${YB_ENV}|g" \
    -e "s|@@YABRIDGE_INSTALL_LOCATION@@|${YABRIDGE_INSTALL_LOCATION}|g" \
    "${SCRIPT_DIR}/templates/wine-version-selector.template" > "${YB_LAUNCHER_TARGET}/${WV_SELECTOR}"
chmod +x "${YB_LAUNCHER_TARGET}/${WV_SELECTOR}"
echo "...OK!"

echo
echo "Installing '${XDG_APP_PATH}/${WV_SELECTOR}.desktop'..."
mkdir -p "${XDG_APP_PATH}"
sed -e "s|@@EXECUTABLE@@|${YB_LAUNCHER_TARGET}/${WV_SELECTOR}|g" \
    "${SCRIPT_DIR}/templates/wine-version-selector.desktop.template" > "${XDG_APP_PATH}/${WV_SELECTOR}.desktop"
echo "...OK!"

echo
echo "Registering '${WV_SELECTOR}.desktop' as default exe/msi application..."
xdg-mime default "${WV_SELECTOR}.desktop" application/x-ms-dos-executable
xdg-mime default "${WV_SELECTOR}.desktop" application/x-msi
echo "...OK!"


### This function replaces given executable with a script
### that calls in in context of YB_ENV.
### The original executable name is appended with ".raw".
wrap_with_YB_ENV() {
  orig="$1"
  path_resolved=$(realpath "$orig")
  
  if [ -f "${path_resolved}.raw" ]; then
    echo "ERROR: '${path_resolved}.raw' already exists!"
    exit 1
  fi

  mv "${path_resolved}" "${path_resolved}.raw"
  cat > "${path_resolved}" <<EOF
#!/bin/sh

exec "${YB_LAUNCHER_TARGET}/${YB_ENV}" "${path_resolved}.raw" "\$@"
EOF
  
  chmod +x "$path_resolved"
  echo "Wrapped '${path_resolved}' with '${YB_LAUNCHER_TARGET}/${YB_ENV}'." 
}


### Pre-create plugin folders and register them
pre_add_plugin_folder() {
    dir=$1
    echo "- \"$dir\""
    mkdir -p "$dir"
    "$YB_LAUNCHER_TARGET/$YB_ENV" "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridgectl" add "$dir"
}


### yabridge's host executables should always use the secondary wine.
echo
wrap_with_YB_ENV "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridge-host-32.exe"
wrap_with_YB_ENV "${YABRIDGE_INSTALL_LOCATION}/yabridge/yabridge-host.exe"


echo
echo "Pre-adding common VST paths..."
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/VST3"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/CLAP"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files (x86)/Common Files/CLAP"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/VST Plugins"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Steinberg/VSTPlugins"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/VST2"
pre_add_plugin_folder "${DEFAULT_WINEPREFIX}/drive_c/Program Files/Common Files/Steinberg/VST2"
echo "...OK!"

echo
echo "Adding '$YB_ENV' to .bashrc..."
BASHRC="$HOME/.bashrc"
PATH_LINE="export PATH=\"${YB_LAUNCHER_TARGET}:\$PATH\""
if [ -f "$BASHRC" ] && grep -Fq "$PATH_LINE" "$BASHRC"; then
    echo "...was already there!"
else
    {
        echo ""
        echo "# Added by yabridge-installer"
        echo "$PATH_LINE"
    } >> "$BASHRC"
    export PATH="$YB_LAUNCHER_TARGET:$PATH"
    echo "...OK!"
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
echo "NOTE! If a plugin's UI is unresponsive, but the plugin seems to otherwise work,"
echo "you likely need to apply 'dxvk' patch with winetricks:"
echo 
echo "  # Install winetricks"
echo "  sudo apt update"  
echo "  sudo apt install winetricks"
echo 
echo "  # Apply 'winetricks dxvk' to yabridge environment"
echo "  yb-env winetricks dxvk"
echo
echo