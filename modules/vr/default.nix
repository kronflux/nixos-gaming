# VR option declarations and shared config — Valve Index support
{ config, lib, pkgs, ... }:
let
  cfg = config.myOS.vr;
in
{
  options.myOS.vr = {
    enable = lib.mkEnableOption "VR support (Valve Index)";

    runtime = lib.mkOption {
      type = lib.types.enum [ "steamvr" "monado" ];
      default = "steamvr";
      description = ''
        Primary OpenXR runtime.
        "steamvr" — Valve's proprietary runtime. Works on NVIDIA but lacks async
                     reprojection on NixOS due to bubblewrap capability stripping.
        "monado"  — Open-source runtime. Has async reprojection on NixOS via
                     CAP_SYS_NICE security wrapper, but may have NVIDIA DRM lease
                     latency issues.
      '';
    };

    autolaunch.enable = lib.mkEnableOption
      "Auto-launch SteamVR when Valve Index HMD is connected via USB";

    bubblewrapPatch = lib.mkEnableOption ''
      Patch bubblewrap to allow CAP_SYS_NICE inside Steam sandbox.
      WARNING: This circumvents an intended security mechanism.
      Enables SteamVR async reprojection on NixOS.
    '';

    openvrCompat = lib.mkOption {
      type = lib.types.enum [ "opencomposite" "xrizer" ];
      default = "opencomposite";
      description = ''
        OpenVR to OpenXR compatibility layer (Monado only).
        "opencomposite" — More mature, wider game compatibility.
        "xrizer"        — Newer, actively developed alternative.
      '';
    };

    lighthouseControl = lib.mkEnableOption
      "Power base stations on/off with Monado start/stop (requires lighthouse-steamvr)";

    audio = {
      enable = lib.mkEnableOption "Automatic Valve Index audio switching on VR start/stop";

      card = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "ALSA card name from `pactl list cards`. Example: alsa_card.usb-Valve_Corporation_Valve_VR_Radio___HMD_Mic-01";
      };
      profile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Card profile to activate. Example: output:iec958-stereo+input:mono-fallback";
      };
      source = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "PulseAudio source device name from `pactl list short sources`.";
      };
      sink = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "PulseAudio sink device name from `pactl list short sinks`.";
      };
      defaultSource = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Default source to restore when VR stops.";
      };
      defaultSink = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Default sink to restore when VR stops.";
      };
    };
  };

  imports = [
    ./steamvr.nix
    ./monado.nix
    ./index-autolaunch.nix
    ./index-audio.nix
  ];

  config = lib.mkIf cfg.enable {
    # VR compositors (Monado and SteamVR's vrcompositor) lock memory pages.
    # Without unlimited memlock, this fails with EPERM.
    security.pam.loginLimits = [
      { domain = "*"; type = "soft"; item = "memlock"; value = "unlimited"; }
      { domain = "*"; type = "hard"; item = "memlock"; value = "unlimited"; }
    ];

    # VR desktop shortcuts for KDE desktop mode (Monado only — SteamVR is
    # launched through Steam, so systemctl start/stop would be meaningless)
    environment.systemPackages = lib.mkIf (cfg.runtime == "monado") [
      (pkgs.makeDesktopItem {
        name = "start-vr";
        desktopName = "Start VR";
        exec = "${pkgs.systemd}/bin/systemctl start --user monado";
        icon = "applications-system";
        type = "Application";
      })
      (pkgs.makeDesktopItem {
        name = "stop-vr";
        desktopName = "Stop VR";
        exec = "${pkgs.systemd}/bin/systemctl stop --user monado";
        icon = "applications-system";
        type = "Application";
      })
    ];
  };
}
