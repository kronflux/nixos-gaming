{
  description = "NixOS Gaming/VR OS — Valve Index + Steam Big Picture";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # CachyOS kernel (active replacement for archived chaotic-nyx)
    # Do NOT override nixpkgs — causes version mismatch with patches
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    # nixpkgs-xr — bleeding-edge Monado, OpenComposite, and other VR packages.
    # Uncomment to get the latest VR stack instead of nixpkgs versions.
    # After uncommenting, add `nixpkgs-xr` to the outputs function parameters
    # and add `nixpkgs-xr.overlays.default` to nixpkgs.overlays in your host config.
    # nixpkgs-xr = {
    #   url = "github:nix-community/nixpkgs-xr";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, nix-cachyos-kernel, ... }: {
    nixosConfigurations.gamingOS = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit self nix-cachyos-kernel; };
      modules = [
        ./hosts/gaming
      ];
    };
  };
}
