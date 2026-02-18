# Auggie (Augment Code CLI) tests
# Tests: A1-A2
# Run: nix build .#checks.x86_64-linux.tools-auggie --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };

  # Create mock augment config directory
  mockAugmentConfig = lib.mkMockConfig {
    files = {
      "session.json" = ''{"token": "test-token"}'';
      ".auggie.json" = ''{"version": "1.0"}'';
    };
  };

  # Create a mock auggie package for testing
  mockAuggie = pkgs.writeShellScriptBin "auggie" ''
    echo "auggie mock v1.0.0"
  '';
in
pkgs.testers.nixosTest {
  name = "agentbox-tools-auggie";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ self.nixosModules.default ];

    # Provide gothaPkgs with mock auggie package via _module.args
    _module.args.gothaPkgs = {
      auggie = mockAuggie;
    };

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for this test
    agentbox.project.source.required = false;

    # Enable auggie with config sync
    agentbox.auggie.enable = true;
    agentbox.auggie.syncConfigFromHost = true;

    # Use virtualisation.sharedDirectories to simulate 9p mount
    virtualisation.sharedDirectories = {
      host-augment = {
        source = "${mockAugmentConfig}";
        target = "/mnt/host-augment";
      };
    };
  };

  testScript = ''
    # A1: Auggie installed - auggie binary exists when enabled
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("which auggie")
    machine.succeed("auggie | grep -q 'auggie mock'")
    print("A1: Auggie installed - PASSED")

    # A2: Auggie config synced - ~/.augment is copied from host when syncConfigFromHost=true
    machine.wait_for_unit("copy-host-configs.service")
    machine.succeed("test -d /home/dev/.augment")
    machine.succeed("test -f /home/dev/.augment/session.json")
    machine.succeed("test -f /home/dev/.augment/.auggie.json")
    machine.succeed("stat -c '%U' /home/dev/.augment | grep -q dev")
    machine.succeed("stat -c '%a' /home/dev/.augment | grep -q 700")
    print("A2: Auggie config synced - PASSED")

    # Verify AUGMENT_DISABLE_AUTO_UPDATE is set (NixOS uses /etc/set-environment)
    machine.succeed("grep -q AUGMENT_DISABLE_AUTO_UPDATE /etc/set-environment")
    print("A3: Auto-update disabled - PASSED")

    print("All auggie tests passed!")
  '';
}

