{
  description = "gotha/agentbox - NixOS VM for coding agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    gotha-nixpkgs.url = "github:gotha/nixpkgs";
  };

  outputs = { self, nixpkgs, gotha-nixpkgs }:
  let
    # Support Linux and Darwin (macOS) hosts
    allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs allSystems;

    # Import library functions
    lib = import ./lib { inherit nixpkgs gotha-nixpkgs; };

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
      docker = import ./modules/docker.nix;
      auggie = import ./modules/auggie.nix;
      cursor = import ./modules/cursor.nix;
      services = import ./modules/services;
    };

    # Export library functions
    inherit lib;

    extraConfig = {
      #agentbox.docker.enable = true;
      #agentbox.docker.syncConfigFromHost = true;

      #agentbox.auggie.enable = true;
      #agentbox.auggie.syncConfigFromHost = true;

      #agentbox.project = {
      #  source.type = "copy";
      #  marker = "go.mod";
      #};
    };

    # NixOS VM configurations for each host system
    nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
      name = "vm-${hostSystem}";
      value = lib.mkDevVm {
        inherit hostSystem;
        extraConfig = self.extraConfig;
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

    # NixOS VM tests (only on Linux)
    checks.x86_64-linux = import ./tests {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      inherit self;
    };

    checks.aarch64-linux = import ./tests {
      pkgs = nixpkgs.legacyPackages.aarch64-linux;
      inherit self;
    };

    # Apps to run the VM directly
    apps = forAllSystems (hostSystem:
      let
        pkgs = nixpkgs.legacyPackages.${hostSystem};
        vmConfig = self.nixosConfigurations."vm-${hostSystem}";
        vmDrv = vmConfig.config.system.build.vm;

        vmName = vmConfig.config.agentbox.vm.hostname;

        # Extract host shares from VM config for the runner script
        # Only need tag and hostPath for the 9p virtfs setup
        hostShares = map (share: {
          inherit (share) tag hostPath;
        }) vmConfig.config.agentbox.hostShares;

        # Extract project configuration
        projectCfg = vmConfig.config.agentbox.project;

        # Use the library helper to generate wrapper scripts
        vmRunner = import ./lib/mk-vm-runner.nix {
          inherit pkgs vmDrv vmName hostShares;
          projectMarker = projectCfg.marker;
          projectSourceType = projectCfg.source.type;
          projectSourcePath = projectCfg.source.path;
          projectDestPath = projectCfg.destPath;
        };
      in {
        default = { type = "app"; program = "${vmRunner.headless}/bin/run-${vmName}"; };
        vm = { type = "app"; program = "${vmRunner.headless}/bin/run-${vmName}"; };
        vm-gui = { type = "app"; program = "${vmRunner.gui}/bin/run-${vmName}-gui"; };
      }
    );
  };
}
