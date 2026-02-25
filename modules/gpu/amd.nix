# AMD GPU driver configuration
{ config, lib, pkgs, ... }:
let
  cfg = config.myOS;
in
lib.mkIf (cfg.gpu == "amd") {
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  boot.initrd.kernelModules = [ "amdgpu" ];

  # Redistributable firmware required for early KMS with amdgpu
  hardware.enableRedistributableFirmware = true;

  # Use RADV (Valve's Vulkan driver) as default — better for gaming
  environment.sessionVariables.AMD_VULKAN_ICD = "RADV";

  # SteamOS/Valve AMD GPU kernel parameters
  boot.kernelParams = [
    # GPU lockup timeout recovery (GFX:5s, Compute:10s, DMA:10s, Video:5s)
    "amdgpu.lockup_timeout=5000,10000,10000,5000"
    # 8GB minimum TTM memory for GPU operations
    "ttm.pages_min=2097152"
    # Prevent GPU scheduling stalls
    "amdgpu.sched_hw_submission=4"
    # Fix display flashing on some AMD GPUs
    "amdgpu.dcdebugmask=0x20000"
  ];

  # Kernel patch: allow async reprojection without CAP_SYS_NICE (AMD only).
  # Required for SteamVR async reprojection on AMD GPUs.
  boot.kernelPatches = [{
    name = "amdgpu-ignore-ctx-privileges";
    patch = pkgs.fetchpatch2 {
      url = "https://github.com/Frogging-Family/community-patches/raw/a6a468420c0df18d51342ac6864ecd3f99f7011e/linux61-tkg/cap_sys_nice_begone.mypatch";
      hash = "sha256-1wUIeBrUfmRSADH963Ax/kXgm9x7ea6K6hQ+bStniIY=";
    };
  }];

  # Auto-set VR runtime to Monado for AMD (full async reprojection support)
  myOS.vr.runtime = lib.mkDefault "monado";
}
