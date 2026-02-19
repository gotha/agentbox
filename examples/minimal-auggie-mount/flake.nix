{
  description = "Minimal agentbox VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    agentbox.url = "github:gotha/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs allSystems;
    in
    {
      # Create VM configurations for each supported host system
      nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
        name = "vm-${hostSystem}";
        value = agentbox.lib.mkDevVm {
          inherit hostSystem;
          extraConfig = {
            agentbox.project = {
              source.type = "mount";
              marker = "package.json";
            };

            agentbox.auggie = {
              enable = true;
              syncConfigFromHost = true;
            };
          };
        };
      }) allSystems);

      apps = forAllSystems (hostSystem:
        let
          pkgs = nixpkgs.legacyPackages.${hostSystem};
          vmConfig = self.nixosConfigurations."vm-${hostSystem}";
          vmDrv = vmConfig.config.system.build.vm;
          vmName = vmConfig.config.agentbox.vm.hostname;
          projectCfg = vmConfig.config.agentbox.project;
          vmRunner = agentbox.lib.mkVmRunner {
            inherit pkgs vmDrv vmName;
            hostShares = [];
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

