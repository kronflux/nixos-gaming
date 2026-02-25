# Gamescope session — boots directly into Steam Big Picture.
#
# Replaces Jovian-NixOS with our own session management:
# - Custom gamescope session wrapper handles the gamescope ↔ KDE lifecycle
# - steamos-session-select script handles "Switch to Desktop" from Steam
# - SDDM auto-login configured directly
# - Security wrappers, polkit, and udev rules ported from Jovian/SteamOS
{ config, lib, pkgs, ... }:
let
  # Our custom session package
  gamescopeSession = pkgs.callPackage ../../pkgs/gamescope-session { };
in
{
  # Allow unfree Steam packages
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "steam-unwrapped"
      "steam-run"
    ];

  # ── SDDM auto-login into gamescope session ─────────────────────────
  # Our session package provides gamescope-wayland.desktop for SDDM.
  # SDDM auto-logs in as the gaming user and starts our session wrapper.
  # Auto-relogin ensures the session restarts if it crashes.
  services.displayManager = {
    autoLogin = {
      enable = true;
      user = "gamer";
    };
    sddm = {
      enable = true;
      autoLogin.relogin = true;
    };
    defaultSession = "gamescope-wayland";
    sessionPackages = [ gamescopeSession ];
  };

  # ── Steam ──────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    package = pkgs.steam.override {
      extraProfile = ''
        unset TZ
        export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
      '';
      # Expose Monado IPC socket to Steam's pressure-vessel sandbox.
      # Without this, games inside pressure-vessel cannot reach the Monado
      # compositor at $XDG_RUNTIME_DIR/monado_comp_ipc.
      # Harmless when using SteamVR (the variable is ignored).
      extraEnv = {
        PRESSURE_VESSEL_FILESYSTEMS_RW = "$XDG_RUNTIME_DIR/monado_comp_ipc";
      };
    };
    remotePlay.openFirewall = true;
    # Proton-GE for better game compatibility + umu-launcher
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  # ── Gamescope ──────────────────────────────────────────────────────
  programs.gamescope = {
    enable = true;
    # Creates /run/wrappers/bin/gamescope with cap_sys_nice capability.
    # Required for Steam to function inside gamescope.
    # Also sets security.wrappers.bwrap with setuid.
    capSysNice = true;
  };

  programs.gamemode.enable = true;

  # ── Kernel modules ─────────────────────────────────────────────────
  # ntsync: required for game compatibility (Proton/Wine synchronization)
  boot.kernelModules = [ "ntsync" ];

  # ── Graphics ───────────────────────────────────────────────────────
  hardware.graphics = {
    enable32Bit = true;
  };
  hardware.steam-hardware.enable = true;

  # Broad game device udev rules (gamepads, arcade sticks, peripherals beyond Steam's set)
  services.udev.packages = [ pkgs.game-devices-udev-rules ];

  # ── udev rules ─────────────────────────────────────────────────────
  # From SteamOS: USB devices, HID devices, Steam Controller
  services.udev.extraRules = ''
    # USB devices and topological children
    SUBSYSTEMS=="usb", TAG+="uaccess"

    # HID devices over hidraw
    KERNEL=="hidraw*", TAG+="uaccess"

    # Steam Controller udev write access
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
  '';

  # ── Polkit rules ───────────────────────────────────────────────────
  # Allow users in "users" group to configure Wi-Fi from Steam Big Picture
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        action.id.indexOf("org.freedesktop.NetworkManager") == 0 &&
        subject.isInGroup("users") &&
        subject.local &&
        subject.active
      ) {
        return polkit.Result.YES;
      }
    });
  '';

  # ── NetworkManager ─────────────────────────────────────────────────
  # Required for Wi-Fi configuration from Steam Big Picture UI
  networking.networkmanager.enable = true;

  # ── Session environment ────────────────────────────────────────────
  # Custom environment overrides sourced by the gamescope session wrapper.
  # Users can add GAMESCOPE_EXTRA_ARGS and STEAM_EXTRA_ARGS here.
  environment.etc."gamescope-session/environment".text = ''
    # Extra gamescope arguments (e.g., "--mangoapp --adaptive-sync")
    # GAMESCOPE_EXTRA_ARGS="--mangoapp"

    # Extra Steam arguments
    # STEAM_EXTRA_ARGS=""
  '';

  # ── Firewall: Steam LAN game transfer ──────────────────────────────
  # Allows fast LAN-based game downloads between Steam clients on the local network
  networking.firewall = {
    allowedTCPPorts = [ 27040 ];
    allowedUDPPortRanges = [{ from = 27031; to = 27036; }];
  };

  # ── Packages ───────────────────────────────────────────────────────
  environment.systemPackages = [
    gamescopeSession  # session wrapper, steamos-session-select, return-to-gaming-mode
    pkgs.mangohud
    pkgs.gamescope-wsi # Vulkan layer for gamescope HDR and WSI integration
    pkgs.protonup-qt   # GUI for managing Proton-GE and other custom Proton versions
    pkgs.protontricks  # Run winetricks commands inside Proton prefixes
  ];

  # ── Session variables ──────────────────────────────────────────────
  environment.sessionVariables = {
    PROTON_USE_NTSYNC = "1";
    ENABLE_GAMESCOPE_WSI = "1";
    STEAM_MULTIPLE_XWAYLANDS = "1";
  };

  # ── XDG portal ─────────────────────────────────────────────────────
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
