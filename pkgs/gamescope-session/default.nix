# Custom gamescope session management — replaces Jovian-NixOS session.
#
# Provides:
#   gamescope-session        — main session wrapper (what SDDM runs)
#   steamos-session-select   — session switcher (what Steam calls)
#   return-to-gaming-mode    — KDE desktop entry to switch back
#   gamescope-wayland.desktop — SDDM session file
#
# Session lifecycle:
#   SDDM auto-login → gamescope-session wrapper
#   ├─ gamescope + Steam Big Picture (default)
#   │   └─ "Switch to Desktop" → steamos-session-select → kills gamescope
#   ├─ wrapper detects desktop request → starts KDE Plasma
#   │   └─ KDE logout → wrapper loops back to gamescope
#   └─ crash/unexpected exit → brief pause, restart gamescope
{ lib
, writeShellScriptBin
, writeTextFile
, symlinkJoin
, procps
, coreutils
, kdePackages
, systemd
}:

let
  # Main session wrapper — this is what SDDM launches as the gamescope-wayland session.
  # It runs gamescope+Steam in a loop, switching to KDE Plasma when requested.
  gamescopeSession = writeShellScriptBin "gamescope-session" ''
    set -o pipefail

    export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0

    # Session state directory
    STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${coreutils}/bin/id -u)}"
    SESSION_FILE="$STATE_DIR/steamos-session-select"

    # Source custom environment overrides (set via NixOS module)
    if [ -f /etc/gamescope-session/environment ]; then
      . /etc/gamescope-session/environment
    fi

    while true; do
      ${coreutils}/bin/rm -f "$SESSION_FILE"

      # Launch gamescope with Steam Big Picture.
      # gamescope must be the security-wrapped version at /run/wrappers/bin/gamescope
      # for cap_sys_nice capability (required for Steam inside gamescope).
      #
      # Flags:
      #   --steam          Steam integration (overlay, focus management)
      #   -e               Expose Steam overlay for external overlay windows
      #   -- steam args    Steam launch arguments
      #   -steamos3        Enable SteamOS 3.x UI features
      #   -steampal        Enable Steam Deck UI palette/layout
      #   -steamdeck       Enable Steam Deck mode (required for "Switch to Desktop")
      #   -gamepadui       New gamepad-focused UI
      /run/wrappers/bin/gamescope \
        --steam \
        -e \
        ''${GAMESCOPE_EXTRA_ARGS:-} \
        -- \
        steam \
          -steamos3 \
          -steampal \
          -steamdeck \
          -gamepadui \
          ''${STEAM_EXTRA_ARGS:-} || true

      # Gamescope has exited — check if desktop mode was requested
      if [ -f "$SESSION_FILE" ]; then
        SELECTED="$(${coreutils}/bin/cat "$SESSION_FILE")"
        case "$SELECTED" in
          plasma|desktop)
            # Launch KDE Plasma Wayland as the desktop session.
            # KWin takes over as the Wayland compositor.
            # When the user logs out of KDE, this returns and the loop restarts gamescope.
            ${kdePackages.plasma-workspace}/bin/startplasma-wayland 2>&1 || true
            continue
            ;;
        esac
      fi

      # Gamescope exited without a desktop request — restart after brief pause
      # to prevent tight restart loops on crash.
      ${coreutils}/bin/sleep 2
    done
  '';

  # Session selector — Steam calls this when "Switch to Desktop" is pressed.
  # It writes the desired session and kills gamescope to trigger the switch.
  sessionSelect = writeShellScriptBin "steamos-session-select" ''
    STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${coreutils}/bin/id -u)}"

    # Map "desktop" to "plasma" for our session wrapper
    SESSION="$1"
    if [ "$SESSION" = "desktop" ]; then
      SESSION="plasma"
    fi

    ${coreutils}/bin/echo "$SESSION" > "$STATE_DIR/steamos-session-select"

    # If switching to desktop, terminate gamescope to trigger the session switch.
    # SIGTERM allows gamescope to clean up (release DRM lease, etc).
    if [ "$SESSION" = "plasma" ]; then
      ${procps}/bin/pkill -TERM -x gamescope 2>/dev/null || true
    fi
  '';

  # Desktop entry for returning to gaming mode from KDE
  returnToGamingMode = writeShellScriptBin "return-to-gaming-mode" ''
    STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${coreutils}/bin/id -u)}"
    ${coreutils}/bin/echo "gamescope" > "$STATE_DIR/steamos-session-select"

    # Log out of KDE Plasma — this causes startplasma-wayland to exit,
    # returning control to our session wrapper which restarts gamescope.
    ${systemd}/bin/loginctl terminate-session "''${XDG_SESSION_ID:-}" 2>/dev/null \
      || ${kdePackages.plasma-workspace}/bin/qdbus org.kde.Shutdown /Shutdown logout 2>/dev/null \
      || true
  '';

  # Wayland session .desktop file — registered with SDDM
  desktopFile = writeTextFile {
    name = "gamescope-session-desktop";
    destination = "/share/wayland-sessions/gamescope-wayland.desktop";
    text = ''
      [Desktop Entry]
      Name=Gaming Mode
      Comment=Gamescope + Steam Big Picture
      Exec=gamescope-session
      Type=Application
      DesktopNames=gamescope
    '';
  };

  # Desktop entry for KDE's application menu
  returnDesktopEntry = writeTextFile {
    name = "return-to-gaming-mode-desktop";
    destination = "/share/applications/return-to-gaming-mode.desktop";
    text = ''
      [Desktop Entry]
      Name=Return to Gaming Mode
      Comment=Exit KDE and switch back to Steam Big Picture
      Exec=return-to-gaming-mode
      Type=Application
      Icon=steam
      Categories=Game;
    '';
  };

in
symlinkJoin {
  name = "gamescope-session";
  paths = [
    gamescopeSession
    sessionSelect
    returnToGamingMode
    desktopFile
    returnDesktopEntry
  ];

  # Tell NixOS display manager infrastructure what sessions we provide
  passthru.providedSessions = [ "gamescope-wayland" ];
}
