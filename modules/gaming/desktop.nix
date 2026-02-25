# KDE Plasma 6 — the desktop session for "Switch to Desktop" in Steam Big Picture.
#
# When the user presses "Switch to Desktop" in gamescope, the session wrapper
# starts KDE Plasma Wayland. Logging out of KDE returns to gamescope.
# A "Return to Gaming Mode" desktop entry is provided by the gamescope-session package.
{ pkgs, ... }: {
  services.desktopManager.plasma6.enable = true;

  # Slim down the default KDE package set
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    oxygen
    elisa
    khelpcenter
    kwrited
  ];

  # SDDM is configured in steam-session.nix (auto-login to gamescope session).
  # KDE Plasma is started by our session wrapper, not by SDDM directly.
}
