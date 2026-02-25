# NixOS Gaming & VR OS

A fully declarative NixOS configuration that boots directly into Steam Big Picture via gamescope, supports Valve Index VR with automatic launch/shutdown on HMD plug events, and provides a lightweight KDE Plasma desktop accessible from Steam's "Switch to Desktop" button.

The entire system is defined in a single flake with two external inputs: nixpkgs and the CachyOS kernel. There are no other runtime dependencies. Every piece of state -- kernel, drivers, session manager, udev rules, systemd services -- is reproducible from `sudo nixos-rebuild switch --flake .#gamingOS`.

## Features

- **Boot to Steam Big Picture** -- Gamescope compositor launches Steam in full-screen Big Picture mode on boot, no display manager interaction required.
- **"Switch to Desktop"** -- The Steam Big Picture button works. It switches to a KDE Plasma 6 Wayland session. Logging out of KDE returns to Gaming Mode.
- **"Return to Gaming Mode"** -- A desktop shortcut in KDE logs out and returns to the gamescope session automatically.
- **Valve Index VR** -- SteamVR and Monado runtimes are both supported and toggleable. HMD auto-launch detects the Index via USB and starts SteamVR. Disconnecting the HMD stops it. Monado users get OpenVR compatibility (OpenComposite or xrizer), automatic `openvrpaths.vrpath` management, optional lighthouse base station power control, and KDE desktop shortcuts for VR start/stop.
- **VR audio switching** -- Optional automatic audio routing to/from the Index headset when VR starts and stops.
- **NVIDIA and AMD GPU support** -- A single config flag (`myOS.gpu`) switches between complete NVIDIA and AMD driver stacks.
- **CachyOS kernel** -- Binary-cached CachyOS kernel with gaming-optimized scheduler tuning and SteamOS sysctl settings. Unlimited RT scheduling for VR compositors.
- **Controller support** -- Xbox One/Series (xpadneo), Xbox 360, DualShock 4, DualSense, and 8BitDo controllers supported out of the box with optimized Bluetooth pairing.
- **Living room ready** -- EarlyOOM prevents hangs under memory pressure, udisks2 auto-mounts game drives, Steam LAN transfer ports are opened for fast local game sharing.

## How It Works

### Session Lifecycle

The system uses SDDM as the display manager with auto-login enabled. On boot, SDDM logs in as the `gamer` user and launches the `gamescope-wayland` session, which is a custom wrapper script.

```
Boot
 |
 v
SDDM auto-login
 |
 v
gamescope-session (wrapper loop)
 |
 +---> gamescope + Steam Big Picture
 |      |
 |      +-- "Switch to Desktop" pressed
 |      |    |
 |      |    v
 |      |   steamos-session-select writes "plasma", kills gamescope
 |      |
 |      +-- Game crash / Steam exit
 |           |
 |           v
 |          Wrapper restarts gamescope after 2s pause
 |
 +---> KDE Plasma Wayland (when desktop was requested)
        |
        +-- User logs out (or "Return to Gaming Mode" shortcut)
             |
             v
            Wrapper loops back to gamescope
```

The wrapper never exits under normal operation. If it does crash, SDDM's auto-relogin restarts it.

### VR Auto-Launch

When `myOS.vr.autolaunch.enable = true`, a udev rule watches for the Valve Index HMD (USB `28de:2300`). On plug, a systemd oneshot service waits for Steam to be running, then opens `steam://run/250820` (the SteamVR app ID). On unplug, the service stops and kills VR processes.

The rule specifically targets the HMD display device (`2300`), not the breakout box hub (`2613`), to avoid false triggers when only the breakout box is powered on.

### GPU Switching

`myOS.gpu = "nvidia"` or `"amd"` controls which driver stack is activated via `lib.mkIf`. Both paths are always defined; only the matching one produces configuration output.

| | NVIDIA | AMD |
|---|---|---|
| Driver | `nvidia` (proprietary) | `amdgpu` (open) |
| Vulkan | NVIDIA ICD | RADV (Valve's driver) |
| VR default | SteamVR | Monado |
| Kernel notes | GCC non-LTO (DKMS safe) | `cap_sys_nice` kernel patch + SteamOS GPU params |

AMD additionally receives SteamOS-aligned kernel parameters for GPU lockup recovery, TTM memory allocation, and scheduling stall prevention (`amdgpu.lockup_timeout`, `ttm.pages_min`, `amdgpu.sched_hw_submission`, `amdgpu.dcdebugmask`).

### Controller Support

Xbox One/Series wireless controllers connect via Bluetooth using the `xpadneo` driver. Xbox 360 wired controllers use the built-in `xpad` driver. DualShock 4, DualSense, and 8BitDo controllers are supported through udev rules that grant user-level access.

Bluetooth is configured with SteamOS-aligned settings: multi-profile support (controller + headphones simultaneously), fast reconnection, and disabled ERTM (fixes pairing issues with most Bluetooth gamepads). The Blueman service provides a GUI for pairing from KDE desktop mode.

### VR Runtimes

Both SteamVR and Monado are implemented as toggleable modules behind `myOS.vr.runtime`.

**SteamVR** is the default for NVIDIA. It works without extra configuration but lacks async reprojection on NixOS because Steam's bubblewrap sandbox strips `CAP_SYS_NICE`. An opt-in bubblewrap patch (`myOS.vr.bubblewrapPatch`) restores this capability at the cost of weakening the sandbox.

**Monado** is the default for AMD. It receives `CAP_SYS_NICE` through a NixOS security wrapper (outside the sandbox), so async reprojection works natively. It uses SteamVR's lighthouse tracking driver (`STEAMVR_LH_ENABLE=1`) for best tracking quality.

When Monado is the active runtime, the module:

- Sets `forceDefaultRuntime = true` to prevent SteamVR from overriding the active OpenXR runtime.
- Creates `openvrpaths.vrpath` via `ExecStartPre` to route OpenVR games through OpenComposite (or xrizer, configurable via `myOS.vr.openvrCompat`) to Monado. Without this, OpenVR games silently fall back to SteamVR.
- Cleans up `openvrpaths.vrpath` via `ExecStopPost` to avoid stale runtime state.
- Exposes the Monado IPC socket to Steam's pressure-vessel sandbox via `PRESSURE_VESSEL_FILESYSTEMS_RW`.
- Optionally controls lighthouse base stations (`myOS.vr.lighthouseControl`) — powers them on when VR starts and off when it stops.
- Provides "Start VR" and "Stop VR" desktop shortcuts for KDE desktop mode.
- Includes `monado-vulkan-layers` for Vulkan integration.

## Directory Structure

```
nixos-vr-gaming/
|-- flake.nix                          # Inputs: nixpkgs + nix-cachyos-kernel
|-- hosts/gaming/
|   |-- default.nix                    # Host config: imports modules, sets options
|   +-- hardware-configuration.nix     # Machine-specific (generate per machine)
|-- modules/
|   |-- core/
|   |   |-- boot.nix                   # CachyOS kernel, bootloader, sysctl tuning
|   |   |-- nix.nix                    # Flake settings, binary caches
|   |   +-- users.nix                  # User account, groups, sudo
|   |-- gpu/
|   |   |-- default.nix                # myOS.gpu option declaration
|   |   |-- nvidia.nix                 # NVIDIA driver, modesetting, VA-API
|   |   +-- amd.nix                    # AMD driver, RADV, kernel patch
|   |-- gaming/
|   |   |-- steam-session.nix          # SDDM config, Steam, gamescope, udev, polkit
|   |   +-- desktop.nix                # KDE Plasma 6
|   |-- vr/
|   |   |-- default.nix                # myOS.vr option declarations + memlock + desktop shortcuts
|   |   |-- steamvr.nix                # SteamVR runtime + bubblewrap patch
|   |   |-- monado.nix                 # Monado OpenXR + OpenComposite/xrizer + lighthouse
|   |   |-- index-autolaunch.nix       # udev + systemd HMD auto-launch
|   |   +-- index-audio.nix            # Automatic audio switching for Valve Index
|   |-- controllers.nix                # Xbox/PS/8BitDo controllers, Bluetooth
|   +-- audio.nix                      # PipeWire + JACK + WirePlumber + rtkit
|-- pkgs/gamescope-session/
|   +-- default.nix                    # Session wrapper, steamos-session-select
|-- patches/
|   +-- bwrap-cap-nice.patch           # Bubblewrap patch for SteamVR async reprojection
+-- scripts/
    +-- install.sh                     # Interactive disk partitioning + nixos-install
```

## Requirements

- x86_64 PC with NVIDIA or AMD GPU
- UEFI boot (systemd-boot)
- NixOS installer USB (for fresh installs)

## Installation

### Fresh Install

1. Boot from a [NixOS minimal installer ISO](https://nixos.org/download/).

2. Connect to the internet (Ethernet or `nmtui` for Wi-Fi).

3. Switch to a root shell and run the install script:
   ```
   sudo -i
   nix-shell -p git
   git clone https://github.com/kronflux/nixos-gaming.git /tmp/nixos-gaming
   bash /tmp/nixos-gaming/scripts/install.sh
   ```

4. Reboot. The system will boot directly into Steam Big Picture.

The install script handles everything interactively: disk partitioning, swap setup, hardware detection, GPU selection, VR enable/disable, timezone, NixOS installation, and user password. It also works if you run it from a local copy of the repository.

### Manual Install

If you prefer to do things manually, or the script doesn't work for your setup:

```bash
sudo -i

# Partition and mount (adjust device name)
sgdisk --zap-all /dev/sda
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart ESP fat32 1MiB 1024MiB
parted -s /dev/sda set 1 esp on
parted -s /dev/sda mkpart primary ext4 1024MiB 100%
mkfs.fat -F32 -n BOOT /dev/sda1
mkfs.ext4 -L nixos /dev/sda2
mount /dev/sda2 /mnt && mkdir -p /mnt/boot && mount /dev/sda1 /mnt/boot

# Clone and generate hardware config
git clone https://github.com/kronflux/nixos-gaming.git /mnt/etc/nixos
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/gaming/hardware-configuration.nix

# Stage in git (flakes only see tracked files)
cd /mnt/etc/nixos && git add hosts/gaming/hardware-configuration.nix && cd -

# Edit hosts/gaming/default.nix to set myOS.gpu, timezone, etc.
nano /mnt/etc/nixos/hosts/gaming/default.nix

# Install
nixos-install --flake /mnt/etc/nixos#gamingOS --no-root-password
nixos-enter --root /mnt -c 'passwd gamer'
reboot
```

**Important:** Do not use `nixos-generate-config --show-hardware-config` — it omits `fileSystems` entries in some environments (Hyper-V, certain UEFI setups) and will cause the build to fail with "fileSystems does not specify your root file system."

### Existing NixOS System

```bash
git clone https://github.com/kronflux/nixos-gaming.git /etc/nixos

# Copy your existing hardware config into the flake
cp /etc/nixos/hardware-configuration.nix /etc/nixos/hosts/gaming/hardware-configuration.nix
# Or generate fresh: nixos-generate-config && cp /etc/nixos/hardware-configuration.nix /etc/nixos/hosts/gaming/hardware-configuration.nix

# Stage it (flakes only see git-tracked files)
cd /etc/nixos && git add hosts/gaming/hardware-configuration.nix

# Edit hosts/gaming/default.nix to set GPU, timezone, etc.
# Then build:
sudo nixos-rebuild switch --flake .#gamingOS
```

## Configuration

All user-facing options are set in `hosts/gaming/default.nix`:

```nix
{
  # GPU driver selection
  myOS.gpu = "nvidia";  # "nvidia" or "amd"

  # VR configuration
  myOS.vr = {
    enable = true;               # Enable Valve Index VR support
    runtime = "steamvr";         # "steamvr" or "monado"
    autolaunch.enable = true;    # Auto-start SteamVR on HMD plug
    bubblewrapPatch = false;     # Patch bwrap for SteamVR async reprojection

    # Monado-specific options (ignored when runtime = "steamvr")
    openvrCompat = "opencomposite";  # "opencomposite" or "xrizer"
    lighthouseControl = false;       # Power base stations on/off with VR

    # Valve Index audio switching (optional, requires device names from pactl)
    # audio = {
    #   enable = true;
    #   card = "alsa_card.usb-Valve_Corporation_Valve_VR_Radio___HMD_Mic-01";
    #   profile = "output:iec958-stereo+input:mono-fallback";
    #   source = "alsa_input.usb-Valve_Corporation_Valve_VR_Radio___HMD_Mic-01.mono-fallback";
    #   sink = "alsa_output.usb-Valve_Corporation_Valve_VR_Radio___HMD_Mic-01.iec958-stereo";
    #   defaultSource = "your-normal-mic-source";
    #   defaultSink = "your-normal-speakers-sink";
    # };
  };

  # System
  networking.hostName = "gamingOS";
  time.timeZone = "America/New_York";
}
```

### VR Audio Switching

The optional `myOS.vr.audio` module automatically routes audio to the Index headset when VR starts and restores your normal audio devices when VR stops. To configure it:

1. Plug in your Valve Index and run:
   ```
   pactl list cards        # Find the card name
   pactl list short sinks   # Find the sink name
   pactl list short sources # Find the source name
   ```
2. Set the device names in `hosts/gaming/default.nix` (see example above).
3. The service binds to `monado.service` so it activates automatically with VR.

### Lighthouse Base Station Control

When `myOS.vr.lighthouseControl = true`, base stations are powered on when Monado starts and powered off when it stops, using `lighthouse-steamvr` over Bluetooth. This saves power and extends base station lifespan.

To temporarily disable lighthouse control without changing the config (e.g., when base stations are already on from another machine), create `/tmp/disable-lighthouse-control`:
```
touch /tmp/disable-lighthouse-control
```

### OpenVR Compatibility Layer

`myOS.vr.openvrCompat` controls how OpenVR games are translated to OpenXR when using Monado:

- **`opencomposite`** (default) -- More mature, wider game compatibility.
- **`xrizer`** -- Newer, actively developed alternative. May work better for some titles.

The selected layer is registered via `openvrpaths.vrpath` which is automatically managed by the Monado service.

### Gamescope Session Environment

Extra arguments for gamescope and Steam can be configured in `/etc/gamescope-session/environment` (managed by the NixOS module in `steam-session.nix`):

```bash
GAMESCOPE_EXTRA_ARGS="--mangoapp --adaptive-sync"
STEAM_EXTRA_ARGS=""
```

### NVIDIA Open vs Proprietary Modules

The NVIDIA module defaults to proprietary drivers (`hardware.nvidia.open = false`) for VR stability. Turing and newer GPUs technically support open modules, but community reports indicate VA-API and VR regressions. To test open modules:

```nix
hardware.nvidia.open = true;
```

## Updating

```
sudo nix flake update --flake /etc/nixos
sudo nixos-rebuild switch --flake /etc/nixos#gamingOS
```

To roll back to a previous generation if an update breaks something:

```
sudo nixos-rebuild switch --flake /etc/nixos#gamingOS --rollback
```

Or select a previous generation from the systemd-boot menu at boot time.

## Recovering a Broken System

Boot from a NixOS installer USB, mount your root and boot partitions, and rebuild:

```
mount /dev/disk/by-label/nixos /mnt
mount /dev/disk/by-label/BOOT /mnt/boot
nixos-install --flake /mnt/etc/nixos#gamingOS --no-root-password
```

The flake lock file pins every dependency. As long as the configuration is on disk, the system can be fully reconstructed.

## Known Issues and Notes

- **"fileSystems does not specify your root file system" during install.** Do not use `nixos-generate-config --show-hardware-config` — it omits `fileSystems` entries in some environments (Hyper-V, certain UEFI setups). Use `nixos-generate-config --root /mnt` (standard mode) and then `cp /mnt/etc/nixos/hardware-configuration.nix` into `hosts/gaming/`. Verify the file contains `fileSystems."/"` before building.
- **"configuration file doesn't exist" during install.** Nix flakes only see git-tracked files. After generating `hardware-configuration.nix`, you **must** run `git add hosts/gaming/hardware-configuration.nix` before `nixos-install`. The install script handles this automatically.
- **"repository path is not owned by current user" during install.** Git's safe.directory protection (CVE-2022-24765) triggers when switching between users (e.g., `sudo` vs root shell). Fix with: `git config --global --add safe.directory /mnt/etc/nixos`. Run the entire installation from a single root shell (`sudo -i`) to avoid this.
- **Out of memory during install.** The NixOS minimal installer has limited RAM. Enable zram swap before building: `modprobe zram && echo 4G > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon /dev/zram0`. The install script does this automatically.
- **"Git tree is dirty" warning.** This is harmless. It means there are uncommitted changes (like the generated hardware config). The flake still evaluates correctly as long as the files are `git add`ed.
- **First boot takes a while.** Steam performs initial setup on first launch. The screen may appear black for several minutes. Do not power-cycle -- reboot after the process completes.
- **`steamos-session-select` depends on gamescope detection.** If Steam's "Switch to Desktop" button does not appear, verify that gamescope is running with `--steam` and that Steam was launched with `-steamdeck`.
- **SteamVR Error 405 on NVIDIA.** The `libdrm` package is added to `programs.steam.extraPackages` to fix `libdrm.so` not found inside the pressure-vessel sandbox.
- **Monado has no hotplug support.** All controllers and trackers must be powered on before starting Monado.
- **`openvrpaths.vrpath` is managed automatically.** The Monado service creates a symlink to a Nix store path on start and cleans it up on stop. SteamVR can no longer overwrite it during Monado sessions.
- **udev rules require re-plug after rebuild.** Existing plugged-in devices do not re-trigger udev rules after `nixos-rebuild switch`. Unplug and replug the Index, or run `sudo udevadm control --reload && sudo udevadm trigger`.
- **CachyOS LTO variants break NVIDIA.** The `-lto` kernel variants use Clang ThinLTO which can fail to compile NVIDIA DKMS modules. The default `linuxPackages-cachyos-latest` (GCC, non-LTO) is used for this reason.
- **Xbox controller firmware updates require Windows.** The 8BitDo Ultimate Software V2 and Xbox Accessories app do not work under Wine/Proton. Use a Windows VM or PC for firmware updates.
- **Xbox One controllers over Bluetooth need xpadneo.** The built-in `xpad` driver only supports wired Xbox controllers. Wireless Bluetooth connections require the `xpadneo` driver (enabled by default).

### Bleeding-Edge VR Packages (nixpkgs-xr)

The `flake.nix` includes a commented-out `nixpkgs-xr` input. Uncommenting it provides bleeding-edge versions of Monado, OpenComposite, and other VR packages from the `nix-community/nixpkgs-xr` overlay, instead of the versions in nixpkgs. This is useful if nixpkgs lags behind on VR-critical fixes but may introduce instability. Only enable this after the base system is confirmed working.

## Design Decisions

**Why SDDM and not a direct TTY launch?** SDDM provides session management infrastructure (session .desktop files, auto-login, auto-relogin) that would need to be reimplemented with `getty` autologin. SDDM also handles PAM, seat management, and XDG session registration correctly.

**Why a wrapper loop instead of SDDM session switching?** SDDM session switching requires an intermediary daemon (like steamos-manager) to change the active session via D-Bus. A wrapper loop that alternates between gamescope and KDE within a single SDDM session is simpler, has fewer moving parts, and achieves the same user experience.

## License

MIT
