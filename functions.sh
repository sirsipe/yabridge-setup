#!/bin/sh

### Run command without any output, unless the command fails; then print output and exit.
run_quiet() {
  output=$("$@" 2>&1) || {
    echo "Command failed: \"$*\""
    echo "Output:"
    echo "$output"
    exit 1
  }
}

run_indented() {
  "$@" 2>&1 | sed 's/^/    /'
}

### Function: Check if WineHQ repo exists for given distribution ID and codename.
check_WineHQ_repo_exists() {
  dist_id="$1"
  codename="$2"
  URL="https://dl.winehq.org/wine-builds/${dist_id}/dists/${codename}/Release"
  if curl --silent --head --fail "$URL" >/dev/null; then
    return 0
  else
    return 1
  fi
}

### Function: Check winehq is already in apt sources
is_winehq_already_in_apt_sources() {
  if grep -r --quiet 'dl.winehq.org' /etc/apt/sources.list /etc/apt/sources.list.d/; then
    return 0
  else
    return 1
  fi
}

### Function: Get WineHQ suite (codename) if present. is_winehq_already_in_apt_sources must be true before calling this.
get_winehq_suite() {
  # Find the first file containing dl.winehq.org
  srcfile=$(grep -rl 'dl.winehq.org' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | head -n 1)

  if [ -z "$srcfile" ]; then
    echo "Error: get_winehq_suite should not be called unless is_winehq_already_in_apt_sources is true."
    exit 1
  fi

  if [ "${srcfile##*.}" = "sources" ]; then
    # New-style .sources file → look for 'Suites:'
    grep -m1 '^Suites:' "$srcfile" | awk '{print $2}'
  else
    # Old-style .list file → codename is usually the 3rd field
    awk '!/^#/ && /dl.winehq.org/ {print $3; exit}' "$srcfile"
  fi
}

### Function: Check wine exists in current system and sets SYSTEM_WINE variable to its absolute path.
is_command_installed() {
  cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}


### Function: Get system wine path. 'wine' command must be installed. 
get_system_wine_path() {
  wine_path=""
  if is_command_installed "wine"; then
    command -v wine
  else
    echo "Error: Asked for system wine path, but wine is not installed."
    exit 1
  fi
}


### Function: Check if given package name is available in repos
is_apt_package_available() {
  pkg_name="$1"
  if apt-cache pkgnames | grep -xq "${pkg_name}"; then
    return 0
  else
    return 1
  fi
}

### Function: Check if current system is x86_64.
is_system_64bit() {
  if [ "$(uname -m)" = "x86_64" ]; then
    return 0
  else
    return 1
  fi
}

### Function: Check if i386 architecture is enabled or not
is_i386_architecture_enabled() {
  if dpkg --print-foreign-architectures | grep -qw i386; then
    return 0
  else
    return 1
  fi
}

### Function: Check if given directory exists.
directory_exists() {
  dir_name="$1"
  if [ -d "${dir_name}" ]; then
    return 0
  else
    return 1
  fi
}

### Function: Check if vulcan is present
has_vulkan() {
  command -v vulkaninfo >/dev/null 2>&1 || return 1
  vulkaninfo >/dev/null 2>&1
}