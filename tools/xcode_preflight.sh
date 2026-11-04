#!/bin/bash
# Sourced by the archive and export scripts. No installation or Apple mutation.
set -euo pipefail
frit_xcode_preflight() {
  local frit_developer_path frit_free_gb frit_memory_percent
  frit_developer_path="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
  if [[ ! -d "$frit_developer_path/Platforms/MacOSX.platform" ]]; then
    echo "Full Xcode is required. Selected developer path is $frit_developer_path." >&2
    echo "Install Xcode first. Use DEVELOPER_DIR to select it for this command. This script does not install it or change xcode-select." >&2
    return 69
  fi
  frit_free_gb=$(/bin/df -g /System/Volumes/Data | /usr/bin/awk 'NR==2 {print $4}')
  if [[ ! "$frit_free_gb" =~ ^[0-9]+$ || "$frit_free_gb" -lt 20 ]]; then
    echo "Build stopped. Free disk is ${frit_free_gb:-unknown} GB. At least 20 GB is required." >&2
    return 75
  fi
  frit_memory_percent=$(/usr/bin/memory_pressure | /usr/bin/awk '/System-wide memory free percentage/ {gsub(/%/, "", $NF); print $NF}')
  if [[ ! "$frit_memory_percent" =~ ^[0-9]+$ || "$frit_memory_percent" -lt 25 ]]; then
    echo "Build stopped. Free memory is ${frit_memory_percent:-unknown} percent. At least 25 percent is required." >&2
    return 75
  fi
  [[ -x "$HOME/bin/buildslot" ]] || { echo "Missing required buildslot command." >&2; return 69; }
  command -v timeout >/dev/null || { echo "Missing required timeout command." >&2; return 69; }
  /usr/bin/xcrun xcodebuild -version
}
