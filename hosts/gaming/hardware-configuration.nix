# PLACEHOLDER — replace with output of: nixos-generate-config --show-hardware-config
#
# Run this on your target machine:
#   nixos-generate-config --show-hardware-config > hosts/gaming/hardware-configuration.nix
#
# This file is machine-specific and must not be committed with real values
# for a shared repo. Each machine needs its own hardware-configuration.nix.
{ config, lib, modulesPath, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Example — replace everything below with your actual hardware config:
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ]; # or kvm-amd
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4"; # or btrfs, etc.
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
