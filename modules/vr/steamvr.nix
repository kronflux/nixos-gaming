# SteamVR runtime configuration
{ config, lib, pkgs, ... }:
let
  cfg = config.myOS.vr;

  # Patched bubblewrap that preserves CAP_SYS_NICE in non-setuid mode.
  # This allows SteamVR's vrcompositor-launcher to acquire the capability
  # for async reprojection inside NixOS's bubblewrap-based Steam sandbox.
  patchedBwrap = pkgs.bubblewrap.overrideAttrs (o: {
    patches = (o.patches or []) ++ [ ../../patches/bwrap-cap-nice.patch ];
  });
in
lib.mkIf (cfg.enable && cfg.runtime == "steamvr") {
  # Steam hardware udev rules (controller, Vive, Index permissions)
  hardware.steam-hardware.enable = true;

  # Optionally patch bubblewrap for async reprojection
  programs.steam.package = lib.mkIf cfg.bubblewrapPatch (
    pkgs.steam.override {
      buildFHSEnv = args: (pkgs.buildFHSEnv.override {
        bubblewrap = patchedBwrap;
      }) (args // {
        extraBwrapArgs = (args.extraBwrapArgs or []) ++ [ "--cap-add" "ALL" ];
      });
    }
  );

  # SteamVR environment variables
  environment.sessionVariables = {
    # Force XCB platform for SteamVR under Wayland (prevents Qt Wayland issues)
    QT_QPA_PLATFORM = "xcb";
  };
}
