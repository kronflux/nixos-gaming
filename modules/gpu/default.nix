# GPU vendor selection — controls driver and VR runtime defaults
{ lib, ... }: {
  options.myOS.gpu = lib.mkOption {
    type = lib.types.enum [ "nvidia" "amd" ];
    default = "nvidia";
    description = "GPU vendor — controls driver selection and VR runtime config.";
  };

  imports = [ ./nvidia.nix ./amd.nix ];
}
