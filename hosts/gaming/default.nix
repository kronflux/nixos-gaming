# Host-level configuration — imports all modules and sets user-facing options.
#
# Build with: sudo nixos-rebuild switch --flake .#gamingOS
#
# Customize the options below to match your hardware:
#   myOS.gpu           — "nvidia" or "amd"
#   myOS.vr.enable     — true to enable Valve Index VR support
#   myOS.vr.runtime    — "steamvr" or "monado"
#   myOS.vr.autolaunch — auto-start/stop SteamVR on HMD plug/unplug
{ config, lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix

    # Core system
    ../../modules/core/boot.nix
    ../../modules/core/nix.nix
    ../../modules/core/users.nix

    # GPU drivers
    ../../modules/gpu

    # Gaming session (gamescope + Steam Big Picture)
    ../../modules/gaming/steam-session.nix
    ../../modules/gaming/desktop.nix

    # Audio
    ../../modules/audio.nix

    # Controllers and Bluetooth
    ../../modules/controllers.nix

    # VR
    ../../modules/vr
  ];

  # ── Hardware selection ─────────────────────────────────────────────
  myOS.gpu = "nvidia";  # "nvidia" or "amd"

  # ── VR configuration ───────────────────────────────────────────────
  myOS.vr = {
    enable = true;
    runtime = "steamvr";            # "steamvr" or "monado"
    autolaunch.enable = true;       # Auto-launch SteamVR on HMD plug-in
    bubblewrapPatch = false;        # Set true for SteamVR async reprojection
                                    # (security trade-off — read the docs)
  };

  # ── System identity ────────────────────────────────────────────────
  networking.hostName = "gamingOS";
  time.timeZone = "America/Edmonton";

  # ── EarlyOOM — prevent system hang under memory pressure ───────
  # Kills processes early instead of letting the kernel OOM-kill randomly.
  # Critical for VR where an unresponsive system can cause nausea.
  services.earlyoom = {
    enable = true;
    # Kill when free memory drops below 400MB or swap below 300MB
    # (SteamOS defaults from Jovian-NixOS)
    extraArgs = [ "-M" "409600,307200" "-S" "409600,307200" ];
  };

  # ── Udisks2 — auto-mount game drives ─────────────────────────────
  # Allows plugging in external game drives and having them auto-mount.
  # Works with KDE's device notifier.
  services.udisks2.enable = true;

  # Swap — zram is lightweight and avoids needing a swap partition
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # Polkit for privilege escalation prompts in KDE
  security.polkit.enable = true;

  # SSH — disable if not needed
  services.openssh.enable = false;

  # Firewall — on by default, Steam remote play ports opened separately
  networking.firewall.enable = true;

  system.stateVersion = "25.05";
}
