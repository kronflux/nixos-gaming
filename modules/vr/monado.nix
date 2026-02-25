# Monado OpenXR runtime configuration
{ config, lib, pkgs, ... }:
let
  cfg = config.myOS.vr;

  # Select OpenVR compatibility layer based on user option
  openvrCompatPkg = if cfg.openvrCompat == "xrizer"
    then pkgs.xrizer
    else pkgs.opencomposite;

  openvrCompatPath = if cfg.openvrCompat == "xrizer"
    then "${openvrCompatPkg}/lib/xrizer"
    else "${openvrCompatPkg}/lib/opencomposite";

  # openvrpaths.vrpath — tells OpenVR games to use OpenComposite/xrizer
  # instead of SteamVR. Without this, every OpenVR game defaults to SteamVR
  # even when Monado is the active OpenXR runtime.
  openvrPathsFile = pkgs.writeText "monado-openvrpaths" (builtins.toJSON {
    version = 1;
    jsonid = "vrpathreg";
    external_drivers = null;
    config  = [ "/home/gamer/.local/share/Steam/config" ];
    log     = [ "/home/gamer/.local/share/Steam/logs" ];
    runtime = [ openvrCompatPath ];
  });

  # Lighthouse power control script (guarded by temp file for manual override)
  lighthouseStartScript = pkgs.writeShellScript "monado-lighthouse-on" ''
    if [ ! -f "/tmp/disable-lighthouse-control" ]; then
      ${pkgs.lighthouse-steamvr}/bin/lighthouse-steamvr --state on || true
    fi
  '';

  lighthouseStopScript = pkgs.writeShellScript "monado-lighthouse-off" ''
    if [ ! -f "/tmp/disable-lighthouse-control" ]; then
      ${pkgs.lighthouse-steamvr}/bin/lighthouse-steamvr --state off || true
    fi
  '';
in
lib.mkIf (cfg.enable && cfg.runtime == "monado") {
  services.monado = {
    enable = true;
    defaultRuntime = true;       # Register as system-wide default OpenXR runtime
    forceDefaultRuntime = true;  # Prevent SteamVR from overriding Monado as active runtime
    highPriority = true;         # CAP_SYS_NICE for async reprojection
  };

  systemd.user.services.monado = {
    environment = {
      # Use SteamVR's lighthouse tracking driver for dramatically better
      # tracking than the open-source libsurvive alternative.
      # SteamVR must be installed (but not running) for this to work.
      # Initial room setup must be done through SteamVR first.
      STEAMVR_LH_ENABLE = "1";

      # Compute compositor mode
      XRT_COMPOSITOR_COMPUTE = "1";

      # Supersampling of the Monado runtime compositor.
      # 140 is conservative (works on mid-range GPUs). Set to 180 for high-end.
      XRT_COMPOSITOR_SCALE_PERCENTAGE = "140";

      # Performance boost: unlimit compositor refresh from power-of-two HMD refresh
      U_PACING_APP_USE_MIN_FRAME_PERIOD = "1";

      # Valve Index display modes:
      # 0: 2880x1600@90Hz  1: 2880x1600@144Hz
      # 2: 2880x1600@120Hz 3: 2880x1600@80Hz
      XRT_COMPOSITOR_DESIRED_MODE = "0";

      # Disable WMR hand tracking (not relevant for Index)
      WMR_HANDTRACKING = "0";

      # Debug GUI — uncomment to enable Monado mirror/peek window for diagnostics
      # XRT_DEBUG_GUI = "1";
      # XRT_CURATED_GUI = "1";
    };

    serviceConfig = {
      # Set up openvrpaths.vrpath so OpenVR games route through OpenComposite/xrizer
      # to Monado instead of falling back to SteamVR.
      ExecStartPre = lib.mkBefore [
        "-${pkgs.writeShellScript "monado-pre" ''
          mkdir -p "$XDG_CONFIG_HOME/openvr"
          ln -sf ${openvrPathsFile} "$XDG_CONFIG_HOME/openvr/openvrpaths.vrpath"
        ''}"
      ] ++ lib.optionals cfg.lighthouseControl [
        "-${lighthouseStartScript}"
      ];

      # Clean up runtime configs on stop to avoid stale state
      ExecStopPost = [
        "-${pkgs.writeShellScript "monado-post" ''
          rm -rf "$XDG_CONFIG_HOME"/{openxr,openvr}
        ''}"
      ] ++ lib.optionals cfg.lighthouseControl [
        "-${lighthouseStopScript}"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    monado
    openvrCompatPkg
    monado-vulkan-layers
  ] ++ lib.optionals cfg.lighthouseControl [
    lighthouse-steamvr
  ];

  # Steam hardware udev rules
  hardware.steam-hardware.enable = true;
}
