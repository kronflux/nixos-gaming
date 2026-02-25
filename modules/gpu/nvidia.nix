# NVIDIA GPU driver configuration
{ config, lib, pkgs, ... }:
let
  cfg = config.myOS;
in
lib.mkIf (cfg.gpu == "nvidia") {
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Required for 32-bit Steam/Proton games
    extraPackages = with pkgs; [
      libva-vdpau-driver
      nvidia-vaapi-driver
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true; # Required for gamescope and Wayland
    # Start with proprietary modules for VR stability.
    # open = true is supported on Turing+ but has reported VA-API and
    # VR issues. Toggle to true after confirming system stability.
    open = lib.mkDefault false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # nvidia-drm.modeset=1 is set automatically by modesetting.enable = true

  # Fix SteamVR Error 405: libdrm.so not found inside pressure-vessel sandbox
  programs.steam.extraPackages = [ pkgs.libdrm ];

  environment.sessionVariables = {
    # Hint for electron/chromium apps on NVIDIA Wayland
    LIBVA_DRIVER_NAME = "nvidia";
  };
}
