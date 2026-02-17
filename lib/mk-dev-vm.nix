# Helper function to create a NixOS VM configuration
{ nixpkgs }:
{ hostSystem
, modules ? []
, extraConfig ? {}
, modulesPath ? null
}:
let
  # Map host system to guest VM system
  hostToGuest = {
    "aarch64-darwin" = "aarch64-linux";
    "x86_64-darwin" = "x86_64-linux";
    "aarch64-linux" = "aarch64-linux";
    "x86_64-linux" = "x86_64-linux";
  };

  guestSystem = hostToGuest.${hostSystem};
  hostPkgs = nixpkgs.legacyPackages.${hostSystem};

  # Get the modules path from nixpkgs if not provided
  nixpkgsModulesPath = if modulesPath != null
    then modulesPath
    else "${nixpkgs}/nixos/modules";
in
nixpkgs.lib.nixosSystem {
  system = guestSystem;
  modules = [
    # QEMU VM support
    ({ modulesPath, ... }: {
      imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
      virtualisation.host.pkgs = hostPkgs;
    })

    # The main devenv module
    ../modules

    # User-provided extra configuration
    extraConfig
  ] ++ modules;

  specialArgs = {
    inherit hostPkgs hostSystem;
  };
}

