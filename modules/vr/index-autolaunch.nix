# Auto-launch SteamVR when Valve Index HMD is plugged in via USB.
# Auto-stop when the HMD is disconnected.
#
# Trigger on USB device 28de:2300 (Valve Index HMD display).
# The hub (28de:2613) appears when the breakout box powers on without an HMD,
# so triggering on the HMD-specific product ID prevents false triggers.
{ config, lib, pkgs, ... }:
let
  cfg = config.myOS.vr;

  steamvr-launch = pkgs.writeShellScript "steamvr-launch" ''
    set -euo pipefail

    # Find the active graphical session user
    USER=""
    for session in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend \
        --no-pager | ${pkgs.gawk}/bin/awk '{print $1}'); do
      TYPE=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Type --value)
      if [ "$TYPE" = "x11" ] || [ "$TYPE" = "wayland" ]; then
        USER=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Name --value)
        break
      fi
    done

    if [ -z "$USER" ]; then
      echo "No graphical session found"
      exit 1
    fi

    UID_VAL=$(${pkgs.coreutils}/bin/id -u "$USER")

    # Wait for Steam to be running (up to 60s)
    for i in $(${pkgs.coreutils}/bin/seq 1 30); do
      if ${pkgs.procps}/bin/pgrep -u "$USER" steam > /dev/null 2>&1; then
        ${pkgs.util-linux}/bin/runuser -u "$USER" -- \
          env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_VAL/bus" \
              XDG_RUNTIME_DIR="/run/user/$UID_VAL" \
          ${pkgs.xdg-utils}/bin/xdg-open "steam://run/250820"
        echo "SteamVR launch requested for $USER"
        exit 0
      fi
      echo "Waiting for Steam... attempt $i/30"
      ${pkgs.coreutils}/bin/sleep 2
    done
    echo "Steam not detected after 60s"
    exit 1
  '';

  steamvr-stop = pkgs.writeShellScript "steamvr-stop" ''
    set -euo pipefail
    for session in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend \
        --no-pager | ${pkgs.gawk}/bin/awk '{print $1}'); do
      TYPE=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Type --value)
      if [ "$TYPE" = "x11" ] || [ "$TYPE" = "wayland" ]; then
        USER=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Name --value)
        ${pkgs.procps}/bin/pkill -u "$USER" -f "vrmonitor" || true
        ${pkgs.procps}/bin/pkill -u "$USER" -f "vrserver" || true
        ${pkgs.procps}/bin/pkill -u "$USER" -f "vrcompositor" || true
        break
      fi
    done
  '';

  # udev rules package — must use a 60- prefix filename so TAG+="systemd"
  # is processed before systemd's 73-seat-late.rules.
  # Do NOT use services.udev.extraRules (writes to 99-local.rules where
  # TAG+="uaccess" and TAG+="systemd" can be silently ignored).
  index-udev-pkg = pkgs.writeTextFile {
    name = "valve-index-autolaunch-udev";
    destination = "/etc/udev/rules.d/60-valve-index-autolaunch.rules";
    text = ''
      # Valve Index HMD connected — start SteamVR
      ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", \
        ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2300", \
        TAG+="systemd", ENV{SYSTEMD_WANTS}="steamvr-autolaunch.service"

      # Valve Index HMD disconnected — stop SteamVR
      # Note: ATTRS{} is unavailable on remove (sysfs node is already gone).
      # Use ENV{PRODUCT} which encodes vendor/product as "28de/2300/*".
      ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="28de/2300/*", \
        RUN+="${pkgs.systemd}/bin/systemctl --no-block stop steamvr-autolaunch.service"
    '';
  };

in
lib.mkIf (cfg.enable && cfg.autolaunch.enable) {
  services.udev.packages = [ index-udev-pkg ];

  systemd.services.steamvr-autolaunch = {
    description = "Auto-launch SteamVR when Valve Index HMD detected";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${steamvr-launch}";
      ExecStop = "${steamvr-stop}";
      TimeoutStartSec = 90;
    };
    # No wantedBy — only triggered by udev TAG+="systemd"
  };
}
