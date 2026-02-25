# CachyOS kernel, bootloader, plymouth, quiet boot, SteamOS sysctl tuning
{ pkgs, nix-cachyos-kernel, ... }: {
  nixpkgs.overlays = [
    # Use pinned overlay for guaranteed binary cache hits from
    # attic.xuyh0120.win/lantian — avoids compiling from source
    nix-cachyos-kernel.overlays.pinned
  ];

  # GCC non-LTO variant — safest choice for NVIDIA DKMS compatibility.
  # Do NOT use -lto variants with NVIDIA (Clang+ThinLTO breaks DKMS modules).
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;

  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = 10;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };

  boot.initrd.systemd.enable = true;

  # Quiet boot with plymouth
  boot.plymouth.enable = true;
  boot.consoleLogLevel = 0;
  boot.kernelParams = [ "quiet" "udev.log_level=3" "audit=0" ];

  # SteamOS-aligned sysctl tuning (ported from Jovian-NixOS steamos/sysctl.nix)
  boot.kernel.sysctl = {
    # Gaming scheduler tuning (from steamos-customizations-jupiter)
    "kernel.sched_cfs_bandwidth_slice_u" = 3000;
    "kernel.sched_latency_ns" = 3000000;
    "kernel.sched_min_granularity_ns" = 300000;
    "kernel.sched_wakeup_granularity_ns" = 500000;
    "kernel.sched_migration_cost_ns" = 50000;
    "kernel.sched_nr_migrate" = 128;

    # Disable split-lock mitigation (performance impact on some games)
    "kernel.split_lock_mitigate" = 0;

    # Required by many modern games (Proton/Wine)
    "vm.max_map_count" = 2147483642;

    # Fix Ubisoft Connect and similar services
    "net.ipv4.tcp_mtu_probing" = true;

    # Faster TCP port reuse for games killed and restarted quickly
    "net.ipv4.tcp_fin_timeout" = 5;

    # Remove 95% CPU cap on real-time tasks.
    # VR compositors and audio threads require unrestricted RT scheduling.
    # Acceptable on a dedicated gaming machine with no multi-user workloads.
    "kernel.sched_rt_runtime_us" = -1;
  };

  # Faster shutdown
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";
}
