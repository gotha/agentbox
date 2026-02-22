# Generate apps attribute set from nixosConfigurations
# This eliminates boilerplate in consumer flakes
{ nixpkgs }:
{ nixosConfigurations }:
let
  allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
  forAllSystems = nixpkgs.lib.genAttrs allSystems;
  mkVmRunner = import ./mk-vm-runner.nix;
in
forAllSystems (hostSystem:
  let
    pkgs = nixpkgs.legacyPackages.${hostSystem};
    vmConfig = nixosConfigurations."vm-${hostSystem}";
    vmDrv = vmConfig.config.system.build.vm;
    vmName = vmConfig.config.agentbox.vm.hostname;
    hostShares = map (share: {
      inherit (share) tag hostPath;
    }) vmConfig.config.agentbox.hostShares;
    projectCfg = vmConfig.config.agentbox.project;
    vmRunner = mkVmRunner {
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
)

