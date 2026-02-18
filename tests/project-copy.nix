# Project source: copy tests
# Tests: C1-C6
# Run: nix build .#checks.x86_64-linux.project-copy --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };
  mockProject = lib.mkMockProject {
    marker = "flake.nix";
    extraFiles = {
      "node_modules/package/index.js" = "module.exports = {}";
    };
  };
in
pkgs.testers.nixosTest {
  name = "agentbox-project-copy";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Configure copy source type
    agentbox.project.source.type = "copy";
    agentbox.project.source.required = true;
    agentbox.project.source.refresh = "always";
    agentbox.project.source.copy.excludePatterns = [ "node_modules" ];
    agentbox.project.destPath = "/home/dev/project";
    agentbox.project.marker = "flake.nix";
    agentbox.project.validateMarker = true;

    # Use virtualisation.sharedDirectories to simulate the 9p mount for copy source
    # Note: The service expects the share to be named "host-project-src"
    virtualisation.sharedDirectories.host-project-src = {
      source = "${mockProject}";
      target = "/mnt/host-project-src";
    };
  };

  testScript = ''
    # C1: Copy basic - Project is copied to destPath
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("copy-host-project.service")
    machine.succeed("test -d /home/dev/project")
    machine.succeed("test -f /home/dev/project/flake.nix")
    machine.succeed("test -f /home/dev/project/README.md")
    machine.succeed("test -f /home/dev/project/src/index.js")
    print("C1: Copy basic - PASSED")

    # C2: Copy ownership - Copied files are owned by the user
    machine.succeed("stat -c '%U' /home/dev/project | grep -q dev")
    machine.succeed("stat -c '%U' /home/dev/project/flake.nix | grep -q dev")
    print("C2: Copy ownership - PASSED")

    # C3: Copy excludes - Excluded patterns are not copied
    machine.succeed("test ! -d /home/dev/project/node_modules")
    print("C3: Copy excludes - PASSED")

    # C4: Copy writable - User can create/modify files in copied directory
    machine.succeed("sudo -u dev touch /home/dev/project/test-file.txt")
    machine.succeed("sudo -u dev rm /home/dev/project/test-file.txt")
    print("C4: Copy writable - PASSED")

    print("All project-copy tests passed!")
  '';
}

