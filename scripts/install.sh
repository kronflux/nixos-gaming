#!/usr/bin/env bash
set -euo pipefail

# ── NixOS Gaming/VR OS — Installation Script ──────────────────────
#
# Handles everything: partitioning, formatting, hardware detection,
# GPU selection, flake setup, NixOS install, and user password.
#
# Usage:
#   Boot from a NixOS minimal installer USB, then:
#     sudo -i
#     bash <path-to>/install.sh
#
#   Or if running the script from a cloned repo on the installer:
#     sudo -i
#     bash /path/to/nixos-gaming/scripts/install.sh

REPO_URL="https://github.com/kronflux/nixos-gaming.git"
FLAKE_REF="/mnt/etc/nixos#gamingOS"
NIXOS_DIR="/mnt/etc/nixos"

# ── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}>>>${NC} $*"; }
warn()  { echo -e "${YELLOW}WARNING:${NC} $*"; }
err()   { echo -e "${RED}ERROR:${NC} $*"; }
ok()    { echo -e "${GREEN}OK:${NC} $*"; }
header() { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Root check ────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "This script must be run as root."
  echo "  Usage: sudo -i"
  echo "  Then:  bash install.sh"
  exit 1
fi

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          NixOS Gaming & VR OS — Installer               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Enable swap — installer has limited RAM ───────────────────────
header "Memory setup"
if swapon --show | grep -q .; then
  ok "Swap already active."
else
  info "No swap detected. Enabling 4GB zram swap..."
  modprobe zram 2>/dev/null || true
  if [[ -e /dev/zram0 ]]; then
    echo "zstd" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    echo "4G" > /sys/block/zram0/disksize
    mkswap /dev/zram0 >/dev/null
    swapon /dev/zram0
    ok "zram swap enabled (4GB)."
  else
    warn "Could not enable zram. Trying swap file fallback..."
    fallocate -l 4G /tmp/nixos-install-swap 2>/dev/null || dd if=/dev/zero of=/tmp/nixos-install-swap bs=1M count=4096 status=progress
    chmod 600 /tmp/nixos-install-swap
    mkswap /tmp/nixos-install-swap >/dev/null
    swapon /tmp/nixos-install-swap
    ok "Swap file enabled (4GB)."
  fi
fi

# ── Git safe.directory — set early to avoid ownership errors ──────
git config --global --add safe.directory "$NIXOS_DIR" 2>/dev/null || true

# ── Device selection ──────────────────────────────────────────────
header "Disk selection"
echo ""
echo "Available block devices:"
echo ""
lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT
echo ""

read -rp "Device to install to (e.g. sda, nvme0n1): " selected_device
disk="/dev/${selected_device}"

if [[ ! -b "$disk" ]]; then
  err "'$disk' is not a valid block device."
  exit 1
fi

echo ""
echo -e "${RED}${BOLD}WARNING: ALL DATA ON $disk WILL BE DESTROYED.${NC}"
read -rp "Type 'yes' to confirm: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# ── Partition prefix (nvme0n1p1 vs sda1) ──────────────────────────
if [[ "$selected_device" =~ [0-9]$ ]]; then
  part_prefix="${disk}p"
else
  part_prefix="${disk}"
fi

# ── Partitioning ──────────────────────────────────────────────────
header "Partitioning $disk"
sgdisk --zap-all "$disk"
parted -s "$disk" mklabel gpt
parted -s "$disk" mkpart ESP fat32 1MiB 1024MiB
parted -s "$disk" set 1 esp on
parted -s "$disk" mkpart primary ext4 1024MiB 100%
partprobe "$disk"
sleep 2
ok "Partitioned: 1GB EFI + rest ext4."

# ── Formatting ────────────────────────────────────────────────────
header "Formatting"
mkfs.fat -F32 -n BOOT "${part_prefix}1"
mkfs.ext4 -F -L nixos "${part_prefix}2"
ok "Formatted: BOOT (FAT32), nixos (ext4)."

# ── Mounting ──────────────────────────────────────────────────────
header "Mounting"
mount "${part_prefix}2" /mnt
mkdir -p /mnt/boot
mount "${part_prefix}1" /mnt/boot
ok "Mounted at /mnt."

# ── Configuration source ─────────────────────────────────────────
header "NixOS configuration"
mkdir -p /mnt/etc

# Determine source: local copy or git clone
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || script_dir=""
use_local=false

if [[ -n "$script_dir" && -f "$script_dir/flake.nix" ]]; then
  echo ""
  echo "Found local configuration at: $script_dir"
  echo "  1) Use local copy"
  echo "  2) Clone from GitHub ($REPO_URL)"
  read -rp "Choice [1/2]: " source_choice
  [[ "$source_choice" == "2" ]] || use_local=true
fi

if $use_local; then
  info "Copying local configuration..."
  cp -a "$script_dir/." "$NIXOS_DIR"
  # Ensure it's a git repo (flakes require it)
  if [[ ! -d "$NIXOS_DIR/.git" ]]; then
    cd "$NIXOS_DIR"
    git init -q
    git add -A
    git commit -q -m "Initial import"
    cd - >/dev/null
  fi
else
  info "Cloning from $REPO_URL..."
  git clone "$REPO_URL" "$NIXOS_DIR"
fi

ok "Configuration placed at $NIXOS_DIR."

# ── Hardware detection ────────────────────────────────────────────
header "Hardware detection"
info "Running nixos-generate-config..."

# Standard mode writes a complete hardware-configuration.nix WITH fileSystems.
# Do NOT use --show-hardware-config — it omits fileSystems in some environments.
nixos-generate-config --root /mnt

# Copy the generated file into our flake structure
cp /mnt/etc/nixos/hardware-configuration.nix "$NIXOS_DIR/hosts/gaming/hardware-configuration.nix"

# Remove the auto-generated configuration.nix that we don't use
rm -f /mnt/etc/nixos/configuration.nix 2>/dev/null || true

# Validate fileSystems detection
if grep -q 'fileSystems\."/"' "$NIXOS_DIR/hosts/gaming/hardware-configuration.nix"; then
  ok "Root filesystem detected."
else
  err "No root filesystem detected in hardware-configuration.nix!"
  echo "  This usually means your disk was not mounted at /mnt when"
  echo "  nixos-generate-config ran. Current mounts:"
  mount | grep /mnt || echo "  (nothing mounted at /mnt)"
  echo ""
  read -rp "Continue anyway? (will likely fail) [y/N]: " cont
  [[ "$cont" == "y" ]] || exit 1
fi

# Stage in git so the flake can see it
cd "$NIXOS_DIR"
git add hosts/gaming/hardware-configuration.nix
cd - >/dev/null

# ── GPU selection ─────────────────────────────────────────────────
header "GPU driver"
echo ""
echo "  1) NVIDIA (proprietary driver)"
echo "  2) AMD    (open-source amdgpu + RADV)"
echo ""
read -rp "Select GPU [1/2]: " gpu_choice

case "$gpu_choice" in
  2|amd|AMD)
    sed -i 's/myOS.gpu = "nvidia"/myOS.gpu = "amd"/' "$NIXOS_DIR/hosts/gaming/default.nix"
    ok "GPU set to AMD."
    ;;
  *)
    ok "GPU set to NVIDIA (default)."
    ;;
esac

# ── VR configuration ──────────────────────────────────────────────
header "VR support"
echo ""
echo "  1) Enable  — Valve Index VR with auto-launch on HMD plug"
echo "  2) Disable — No VR support (pure gaming PC)"
echo ""
read -rp "Enable VR? [1/2]: " vr_choice

case "$vr_choice" in
  2|no|NO|n|N)
    sed -i 's/myOS.vr.enable = true/myOS.vr.enable = false/' "$NIXOS_DIR/hosts/gaming/default.nix"
    ok "VR disabled."
    ;;
  *)
    ok "VR enabled (default)."
    ;;
esac

# ── Timezone ──────────────────────────────────────────────────────
header "Timezone"
current_tz=$(grep 'time.timeZone' "$NIXOS_DIR/hosts/gaming/default.nix" | sed 's/.*"\(.*\)".*/\1/')
echo ""
echo "  Current: $current_tz"
read -rp "  Enter timezone (or press Enter to keep): " new_tz

if [[ -n "$new_tz" ]]; then
  sed -i "s|time.timeZone = \"$current_tz\"|time.timeZone = \"$new_tz\"|" "$NIXOS_DIR/hosts/gaming/default.nix"
  ok "Timezone set to $new_tz."
else
  ok "Keeping $current_tz."
fi

# ── Stage any config changes ──────────────────────────────────────
cd "$NIXOS_DIR"
git add -A
cd - >/dev/null

# ── Install ───────────────────────────────────────────────────────
header "Installing NixOS"
info "This will download and build packages. May take a while on first install."
echo ""

nixos-install --flake "$FLAKE_REF" --no-root-password

# ── User password ─────────────────────────────────────────────────
header "User password"
echo ""
echo "Set the password for the 'gamer' user:"
echo ""
nixos-enter --root /mnt -c 'passwd gamer' || {
  warn "Could not set password interactively."
  echo "  Set it manually after reboot: passwd gamer"
}

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Installation complete!                      ║"
echo "║                                                          ║"
echo "║  Reboot into your new system:                            ║"
echo "║    reboot                                                ║"
echo "║                                                          ║"
echo "║  The system will boot directly into Steam Big Picture.   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
