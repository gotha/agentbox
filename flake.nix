{
  description = "gotha/agentbox - NixOS VM for coding agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
  let
    # Support Linux and Darwin (macOS) hosts
    allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs allSystems;

    # Import library functions
    lib = import ./lib { inherit nixpkgs; };

  in {
    # Export NixOS modules for consumption by other flakes
    nixosModules = {
      default = import ./modules;
      hardware = import ./modules/hardware.nix;
      networking = import ./modules/networking.nix;
      users = import ./modules/users.nix;
      packages = import ./modules/packages.nix;
      development = import ./modules/development.nix;
      environment = import ./modules/environment.nix;
      services = import ./modules/services;
    };

    # Export library functions
    inherit lib;

    # NixOS VM configurations for each host system
    nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
      name = "vm-${hostSystem}";
      value = lib.mkDevVm {
        inherit hostSystem;
      };
    }) allSystems);

    # Packages to build the VM image
    packages = forAllSystems (hostSystem:
      let
        vmConfig = self.nixosConfigurations."vm-${hostSystem}";
      in {
        default = vmConfig.config.system.build.vm;
        vm = vmConfig.config.system.build.vm;
      }
    );

    # Apps to run the VM directly
    apps = forAllSystems (hostSystem:
      let
        pkgs = nixpkgs.legacyPackages.${hostSystem};
        vmConfig = self.nixosConfigurations."vm-${hostSystem}";
        vmDrv = vmConfig.config.system.build.vm;

        vmName = vmConfig.config.agentbox.vm.hostname;

        # Use the library helper to generate wrapper scripts
        vmRunner = import ./lib/mk-vm-runner.nix {
          inherit pkgs vmDrv vmName;
          projectMarker = vmConfig.config.agentbox.project.marker;
        };
      in {
        default = { type = "app"; program = "${vmRunner.headless}/bin/run-${vmName}"; };
        vm = { type = "app"; program = "${vmRunner.headless}/bin/run-${vmName}"; };
        vm-gui = { type = "app"; program = "${vmRunner.gui}/bin/run-${vmName}-gui"; };
      }
    );
  };
}
