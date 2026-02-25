# User account, groups, shell
{ pkgs, ... }: {
  users.users.gamer = {
    isNormalUser = true;
    description = "Gaming user";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "input"
      "gamemode"    # Feral GameMode performance daemon
      "bluetooth"   # Direct Bluetooth adapter access
      "render"      # GPU render node access (Vulkan compute, VR)
    ];
    # Set a password after first boot with: passwd gamer
    initialPassword = "changeme";
    shell = pkgs.bash;
  };

  # Allow wheel group to use sudo
  security.sudo.wheelNeedsPassword = false;
}
