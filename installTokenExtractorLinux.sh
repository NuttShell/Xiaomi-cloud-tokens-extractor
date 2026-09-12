#!/usr/bin/env bash
#
# Install / update / remove script for the Xiaomi Cloud Tokens Extractor
# Linux binary (token_extractor_linux_<arch>, published on GitHub Releases).
#
# Unlike a service installer, this tool is a one-shot CLI you run on demand --
# so there's no systemd unit, no dedicated system user, no port/auth config.
# All this script does is: detect the architecture, fetch the right binary
# from GitHub Releases, drop it in /opt, and symlink it into PATH. Session
# cache and reports are handled entirely by the binary itself, per-user,
# under ~/.xiaomi-token-extractor/ -- this script never touches that.
#
# Usage:
#   sudo ./installTokenExtractorLinux.sh                    # interactive menu
#   sudo ./installTokenExtractorLinux.sh --install           # install latest
#   sudo ./installTokenExtractorLinux.sh --install 1.0.5     # install a specific version
#   sudo ./installTokenExtractorLinux.sh --update --silent   # update, fully unattended
#   sudo ./installTokenExtractorLinux.sh --check             # check for updates only
#   sudo ./installTokenExtractorLinux.sh --remove             # uninstall
#
set -euo pipefail

#############################################
#           CONSTANTS
#############################################
readonly REPO_URL="https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor"
readonly INSTALLER_RAW_URL="https://raw.githubusercontent.com/NuttShell/Xiaomi-cloud-tokens-extractor/master/installTokenExtractorLinux.sh"
readonly INSTALL_DIR="/opt/xiaomi-token-extractor"
readonly SYMLINK_PATH="/usr/local/bin/token-extractor"
# Matches the glibc baseline of the python:3.12-bullseye image the Linux
# binary is built inside (see release.yml) -- anything older can't load it.
readonly MIN_GLIBC_VERSION="2.31"

scriptname=$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")

SILENT_MODE=0
parsedCommand=""
specificVersion=""
architecture=""

#############################################
#           COLOR OUTPUT
#############################################
declare -A colors=([black]=0 [red]=1 [green]=2 [yellow]=3 [blue]=4 [magenta]=5 [cyan]=6 [white]=7)
supports_color_output=0
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  if [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
    supports_color_output=1
  fi
fi

colorize() {
  if [[ $supports_color_output -eq 1 ]]; then
    printf "%s%s%s" "$(tput setaf "${colors[$1]:-7}")" "$2" "$(tput op)"
  else
    printf "%s" "$2"
  fi
}

#############################################
#           UTILITIES
#############################################

isRoot() {
  [[ $EUID -eq 0 ]]
}

trimInput() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Prompts are read from /dev/tty (not stdin) so this still works when the
# script is run as `curl ... | sudo bash` -- stdin is the script body then.
promptYesNo() {
  local prompt="$1"
  local default="${2:-n}"

  if [[ $SILENT_MODE -eq 1 ]]; then
    [[ "$default" == "y" ]]
    return
  fi

  local answer
  printf ' %s (y/n) ' "$prompt" >&2
  IFS= read -r answer </dev/tty
  [[ "$answer" =~ ^[Yy] ]]
}

promptInput() {
  local prompt="$1"
  local answer
  printf ' %s ' "$prompt" >&2
  IFS= read -r answer </dev/tty
  trimInput "$answer"
}

# Simple numbered menu, matching token_extractor.py's own server-selection
# prompt style: number the options, 0 always means exit.
promptChoice() {
  local title="$1"
  shift
  local options=("$@")

  echo "" >&2
  echo "$title" >&2
  local i
  for i in "${!options[@]}"; do
    printf '%-3s- %s\n' "$((i + 1))" "${options[$i]}" >&2
  done
  printf '%-3s- Exit\n' "0" >&2
  echo "" >&2

  local choice
  while true; do
    printf 'Enter number: ' >&2
    IFS= read -r choice </dev/tty
    if [[ "$choice" == "0" ]]; then
      echo "0"
      return
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "$choice"
      return
    fi
    echo " Invalid input, try again" >&2
  done
}

#############################################
#           ARCH / GLIBC / CURL CHECKS
#############################################

# Only amd64 builds are published today (see release.yml). Extending this
# once aarch64/armhf builds exist is just adding cases here -- the rest of
# the script (getBinaryName, download URLs) already parameterizes on
# $architecture and needs no other changes.
checkArch() {
  case "$(uname -m)" in
    x86_64) architecture="amd64" ;;
    *)
      echo " $(colorize red "Unsupported architecture: $(uname -m).")" >&2
      echo " Only amd64 (x86_64) builds are published right now." >&2
      exit 1
      ;;
  esac
}

checkCurl() {
  if ! command -v curl >/dev/null 2>&1; then
    echo " $(colorize red "ERROR: curl is required but not installed.")" >&2
    echo " Install it with your distro's package manager (e.g. 'apt install curl'" >&2
    echo " or 'dnf install curl') and re-run this script." >&2
    exit 1
  fi
}

getGlibcVersion() {
  local v
  if command -v ldd >/dev/null 2>&1; then
    v=$(ldd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  fi
  if command -v getconf >/dev/null 2>&1; then
    v=$(getconf GNU_LIBC_VERSION 2>/dev/null | grep -oE '[0-9]+\.[0-9]+')
    if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  fi
  if command -v dpkg >/dev/null 2>&1; then
    v=$(dpkg -l libc6 2>/dev/null | awk '/^ii/ {print $3}' | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  fi
  if command -v rpm >/dev/null 2>&1; then
    v=$(rpm -q glibc 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  fi
  return 1
}

# True if $1 >= $2 (both plain "X.Y" version strings).
compareVersions() {
  local sorted_first
  sorted_first=$(printf '%s\n' "$1" "$2" | sort -V | head -n1)
  [[ "$sorted_first" == "$2" ]]
}

checkGlibcCompatibility() {
  local current
  if ! current=$(getGlibcVersion); then
    echo " $(colorize yellow "Warning: could not detect glibc version -- continuing anyway.")"
    return 0
  fi
  if ! compareVersions "$current" "$MIN_GLIBC_VERSION"; then
    echo " $(colorize red "ERROR: this build needs glibc >= $MIN_GLIBC_VERSION, this system has $current.")"
    echo " Your distro is likely too old for this binary (e.g. Debian 10 or older,"
    echo " Ubuntu 18.04 or older)."
    exit 1
  fi
  if [[ $SILENT_MODE -eq 0 ]]; then
    echo " - glibc $current OK (needs >= $MIN_GLIBC_VERSION)"
  fi
}

#############################################
#           VERSION MANAGEMENT
#
# Release tags on this repo ARE the plain version string (e.g. "1.0.6"),
# same as `token_extractor --version` prints -- no prefix/transform needed,
# unlike some other projects' "vX.Y.Z" or custom-prefixed tags.
#############################################

getBinaryName() {
  echo "token_extractor_linux_${architecture}"
}

installedBinaryPath() {
  echo "${INSTALL_DIR}/$(getBinaryName)"
}

getLatestReleaseTag() {
  curl -fsS -o /dev/null -w '%{redirect_url}' --connect-timeout 10 --max-time 30 \
    "${REPO_URL}/releases/latest" | sed -E 's#.*/tag/##'
}

releaseExists() {
  local tag="$1" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    "${REPO_URL}/releases/tag/$tag") || code=""
  [[ "$code" == "200" ]]
}

getTargetVersion() {
  if [[ -n "$specificVersion" ]]; then
    if ! releaseExists "$specificVersion"; then
      echo " $(colorize red "ERROR: version $specificVersion not found in releases.")" >&2
      echo " Check available versions at: $REPO_URL/releases" >&2
      exit 1
    fi
    echo "$specificVersion"
    return
  fi

  local tag
  tag=$(getLatestReleaseTag) || tag=""
  if [[ -z "$tag" ]]; then
    echo " $(colorize red "ERROR: could not fetch the latest release from GitHub.")" >&2
    exit 1
  fi
  echo "$tag"
}

buildDownloadUrl() {
  local target_version="$1" binary_name="$2"
  if [[ -z "$specificVersion" ]]; then
    echo "${REPO_URL}/releases/latest/download/${binary_name}"
  else
    echo "${REPO_URL}/releases/download/${target_version}/${binary_name}"
  fi
}

downloadBinary() {
  local url="$1" destination="$2" version_info="$3"
  local curl_args=(-fL --connect-timeout 10 --max-time 300)

  if [[ $SILENT_MODE -eq 0 ]]; then
    echo " - Downloading token-extractor $version_info..."
    curl_args+=(--progress-bar)
  else
    curl_args+=(-s -S)
  fi

  curl "${curl_args[@]}" -o "$destination" "$url"
  chmod 755 "$destination"
}

#############################################
#           INSTALL STATUS
#############################################

checkInstalled() {
  local bin
  bin=$(installedBinaryPath)
  [[ -f "$bin" ]] && [[ -s "$bin" ]]
}

getInstalledVersion() {
  "$(installedBinaryPath)" --version 2>/dev/null
}

# Returns 0 (already at target_version) or 1 (needs installing/updating).
checkInstalledVersion() {
  local target_version="$1"
  local installed_version
  installed_version=$(getInstalledVersion) || installed_version=""

  if [[ "$target_version" == "$installed_version" ]]; then
    [[ $SILENT_MODE -eq 0 ]] && echo " - You already have version $target_version installed."
    return 0
  fi

  [[ $SILENT_MODE -eq 0 ]] && echo " - Installed: \"${installed_version:-none}\", target: \"$target_version\"."
  return 1
}

#############################################
#           INSTALL / UPDATE / CHECK / REMOVE
#############################################

# Copies this installer script into $INSTALL_DIR, so it's on the system
# afterwards for future --update/--check/--remove runs without having to
# re-download it from GitHub. Two paths:
#   1. Copy the real file on disk, if there is one (the common case: a
#      downloaded/local installTokenExtractorLinux.sh was run directly).
#   2. Otherwise (e.g. `curl ... | sudo bash` or `sudo bash <(curl ...)`,
#      where the script only ever exists as a pipe -- BASH_SOURCE[0] then
#      points at something like /dev/fd/63, not a regular file, and it can
#      only be read once anyway) fetch a fresh copy straight from GitHub.
# Best-effort either way: a failure here shouldn't block the actual binary
# install, so nothing here is fatal.
copySelfToInstallDir() {
  local self_path=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    self_path=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
  fi

  if [[ -n "$self_path" && -f "$self_path" ]]; then
    install -m 755 "$self_path" "${INSTALL_DIR}/installTokenExtractorLinux.sh"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 10 --max-time 30 \
        -o "${INSTALL_DIR}/installTokenExtractorLinux.sh" "$INSTALLER_RAW_URL" 2>/dev/null; then
      chmod 755 "${INSTALL_DIR}/installTokenExtractorLinux.sh"
    else
      rm -f "${INSTALL_DIR}/installTokenExtractorLinux.sh"
    fi
  fi
}

doInstall() {
  checkCurl

  local target_version
  target_version=$(getTargetVersion)
  [[ $SILENT_MODE -eq 0 ]] && echo " - Target version: $target_version"

  checkGlibcCompatibility

  local need_download=1
  if checkInstalled; then
    if checkInstalledVersion "$target_version"; then
      need_download=0
    elif [[ $SILENT_MODE -eq 0 ]]; then
      if ! promptYesNo "Install/update to $target_version?" "y"; then
        echo " Cancelled."
        return 0
      fi
    fi
  fi

  mkdir -p "$INSTALL_DIR"
  copySelfToInstallDir

  local binName binPath
  binName=$(getBinaryName)
  binPath="${INSTALL_DIR}/${binName}"

  if [[ $need_download -eq 1 ]]; then
    local urlBin
    urlBin=$(buildDownloadUrl "$target_version" "$binName")
    downloadBinary "$urlBin" "$binPath" "$target_version"
  fi

  # (Re)link every time, in case a previous symlink got removed manually --
  # cheap, idempotent, and means `--install` also fixes a broken PATH entry.
  ln -sf "$binPath" "$SYMLINK_PATH"

  if [[ $SILENT_MODE -eq 0 ]]; then
    echo ""
    echo " $(colorize green "token-extractor $target_version is installed at $INSTALL_DIR")"
    echo " Run it with: token-extractor --help"
    echo " Session cache and reports are saved per-user under ~/.xiaomi-token-extractor/"
    echo " This install script is also kept at $INSTALL_DIR/installTokenExtractorLinux.sh"
    echo " for future updates/removal."
    echo ""
  else
    echo "token-extractor $target_version installed to $INSTALL_DIR"
  fi
}

doCheck() {
  if ! checkInstalled; then
    echo " Not installed. Run with --install to install it."
    exit 1
  fi

  local target_version installed_version
  target_version=$(getTargetVersion)
  installed_version=$(getInstalledVersion) || installed_version=""

  echo " - Installed: ${installed_version:-unknown}"
  echo " - Latest:    $target_version"

  if [[ -n "$installed_version" && "$installed_version" == "$target_version" ]]; then
    echo " $(colorize green "Up to date.")"
  else
    echo " $(colorize yellow "Update available -- run: sudo $scriptname --update")"
  fi
}

doRemove() {
  if ! checkInstalled && [[ ! -L "$SYMLINK_PATH" ]]; then
    echo " token-extractor is not installed."
    return 0
  fi

  if [[ $SILENT_MODE -eq 0 ]]; then
    echo ""
    echo " Install dir: $INSTALL_DIR"
    echo " This removes the binary, the installer copy, and the $SYMLINK_PATH symlink."
    echo " Session cache/reports in each user's ~/.xiaomi-token-extractor/ are left"
    echo " alone (delete that folder yourself per-user if you also want those gone)."
    echo ""
    if ! promptYesNo "Are you sure you want to remove token-extractor?" "n"; then
      echo " $(colorize yellow "Cancelled.")"
      return 0
    fi
  fi

  rm -rf "$INSTALL_DIR"
  rm -f "$SYMLINK_PATH"
 echo " $(colorize green " token-extractor removed.")"
}

#############################################
#           HELP & ARG PARSING
#############################################

helpUsage() {
  cat <<EOF
$scriptname - install/update/remove token-extractor (Xiaomi Cloud Tokens Extractor)

Usage: $scriptname [COMMAND] [OPTIONS]

Commands:
  -i, --install [VERSION]   Install latest, or a specific version (e.g. 1.0.5)
  -u, --update              Update to the latest version (installs it if missing)
  -c, --check               Check for updates -- reports only, changes nothing
  -r, --remove              Uninstall ($INSTALL_DIR and $SYMLINK_PATH)
  -h, --help                Show this help message

Options:
  --silent                  Non-interactive: no prompts, sensible defaults
                             (install/update proceed automatically; remove
                             still needs --remove explicitly, and skips its
                             confirmation prompt too)

Examples:
  sudo $scriptname                       # interactive menu
  sudo $scriptname --install             # install latest
  sudo $scriptname --install 1.0.5       # install a specific version
  sudo $scriptname --update --silent     # update to latest, fully unattended
  sudo $scriptname --check               # just check whether an update exists
  sudo $scriptname --remove              # uninstall

After installing: token-extractor --help
Session cache and reports live per-user in ~/.xiaomi-token-extractor/, not in
$INSTALL_DIR -- so different users on a shared machine don't share tokens.
EOF
}

parseArguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--install)
        parsedCommand="install"
        shift
        if [[ $# -gt 0 && "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          specificVersion="$1"
          shift
        fi
        ;;
      -u|--update)
        parsedCommand="update"
        shift
        ;;
      -c|--check)
        parsedCommand="check"
        shift
        ;;
      -r|--remove)
        parsedCommand="remove"
        shift
        ;;
      --silent)
        SILENT_MODE=1
        shift
        ;;
      -h|--help)
        helpUsage
        exit 0
        ;;
      *)
        echo " Unknown option: $1" >&2
        helpUsage
        exit 1
        ;;
    esac
  done
}

#############################################
#           MAIN
#############################################

main() {
  parseArguments "$@"

  if ! isRoot; then
    echo " This script must be run as root (or with sudo). Example: sudo $scriptname" >&2
    exit 1
  fi

  checkArch

  case "$parsedCommand" in
    install)
      doInstall
      exit 0
      ;;
    update)
      specificVersion=""
      doInstall
      exit 0
      ;;
    check)
      doCheck
      exit 0
      ;;
    remove)
      doRemove
      exit 0
      ;;
  esac

  # No command given -- interactive menu.
  if [[ $SILENT_MODE -eq 1 ]]; then
    echo " No command given. Use --install/--update/--check/--remove, or --help." >&2
    exit 1
  fi

  echo ""
  echo " $(colorize green "=============================================================")"
  echo " $(colorize green " Xiaomi Cloud Token extractor install/update/remove script")"
  echo " $(colorize green "=============================================================")"

  local choice
  choice=$(promptChoice "  What would you like to do?" \
      "  Install / update to latest" \
      "  Install a specific version" \
      "  Check for updates" \
      "  Uninstall")

  case "$choice" in
    1)
      specificVersion=""
      doInstall
      ;;
    2)
      while true; do
        specificVersion=$(promptInput "Version to install (e.g. 1.0.5):")
        [[ "$specificVersion" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
        echo " That doesn't look like a version number, try again (or Ctrl+C to give up)."
      done
      doInstall
      ;;
    3) doCheck ;;
    4) doRemove ;;
    0|*) echo "  Bye." ;;
  esac
}

main "$@"
