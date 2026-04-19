#!/bin/bash
# [omarchy] Inject CachyOS optimized repos into /etc/pacman.conf based on host CPU.
#
# The upstream stable/edge pacman templates do not include CachyOS repos at all.
# The fork previously hardcoded [cachyos-*-znver4] sections, which broke install
# on any CPU that did not support x86_64_v4 (pacman rejects all v4 packages with
# "package architecture is not valid"). This helper detects CPU capability at
# install time and injects the matching [cachyos-*] block before [core].
#
# Idempotent: safe to run multiple times. Removes any existing [cachyos*] block
# before injecting a fresh one.

set -euo pipefail

pacman_conf="${1:-/etc/pacman.conf}"

if [[ ! -f $pacman_conf ]]; then
  echo "cachyos-repos: $pacman_conf does not exist; skipping" >&2
  exit 0
fi

ld_help=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null || true)
has_v4=$(echo "$ld_help" | grep -q "x86-64-v4 (supported" && echo 1 || echo 0)
has_v3=$(echo "$ld_help" | grep -q "x86-64-v3 (supported" && echo 1 || echo 0)
is_amd=$(grep -q "AuthenticAMD" /proc/cpuinfo && echo 1 || echo 0)

if [[ $has_v4 == 1 && $is_amd == 1 && -f /etc/pacman.d/cachyos-v4-mirrorlist ]]; then
  suffix="znver4"
  mirrorlist="/etc/pacman.d/cachyos-v4-mirrorlist"
elif [[ $has_v4 == 1 && -f /etc/pacman.d/cachyos-v4-mirrorlist ]]; then
  suffix="v4"
  mirrorlist="/etc/pacman.d/cachyos-v4-mirrorlist"
elif [[ $has_v3 == 1 && -f /etc/pacman.d/cachyos-v3-mirrorlist ]]; then
  suffix="v3"
  mirrorlist="/etc/pacman.d/cachyos-v3-mirrorlist"
else
  suffix=""
fi

block="# CachyOS optimized repos (detected: ${suffix:-generic})"$'\n'
if [[ -n $suffix ]]; then
  for section in "cachyos-${suffix}" "cachyos-core-${suffix}" "cachyos-extra-${suffix}"; do
    block+="[${section}]"$'\n'"Include = ${mirrorlist}"$'\n\n'
  done
fi
if [[ -f /etc/pacman.d/cachyos-mirrorlist ]]; then
  block+="[cachyos]"$'\n'"Include = /etc/pacman.d/cachyos-mirrorlist"$'\n\n'
fi

tmp=$(mktemp)
awk -v block="$block" '
  # Strip any existing [cachyos*] sections (and their preceding detection comment)
  /^# CachyOS optimized repos/ { skip = 1; next }
  /^\[cachyos/ { skip = 1; next }
  skip && /^\[/ { skip = 0 }
  skip { next }

  # Inject fresh block before [core]
  /^\[core\]/ && !injected { printf "%s", block; injected = 1 }
  { print }
' "$pacman_conf" >"$tmp"

sudo cp "$tmp" "$pacman_conf"
rm -f "$tmp"

echo "CachyOS repo variant: ${suffix:-generic}"
