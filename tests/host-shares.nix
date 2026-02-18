# Host shares sync tests
# Tests: H1-H4
# Run: nix build .#checks.x86_64-linux.host-shares --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };

  # Create mock host config directories
  mockAugmentConfig = lib.mkMockConfig {
    files = {
      "session.json" = ''{"token": "test-token"}'';
      ".auggie.json" = ''{"config": true}'';
    };
  };

  mockDockerConfig = lib.mkMockConfig {
    files = {
      "config.json" = ''{"auths": {}}'';
    };
  };
in
pkgs.testers.nixosTest {
  name = "agentbox-host-shares";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for this test
    agentbox.project.source.required = false;

    # Configure host shares
    agentbox.hostShares = [
      {
        tag = "host-augment";
        hostPath = ".augment";
        dest = ".augment";
        mode = "700";
        fileOverrides = [ "session.json:600" ".auggie.json:600" ];
      }
      {
        tag = "host-docker";
        hostPath = ".docker";
        dest = ".docker";
        mode = "700";
        fileOverrides = [ "config.json:600" ];
      }
    ];

    # Use virtualisation.sharedDirectories to simulate 9p mounts
    virtualisation.sharedDirectories = {
      host-augment = {
        source = "${mockAugmentConfig}";
        target = "/mnt/host-augment";
      };
      host-docker = {
        source = "${mockDockerConfig}";
        target = "/mnt/host-docker";
      };
    };
  };

  testScript = ''
    # H1: Share basic - Files from shared directory are copied to user home
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("copy-host-configs.service")

    # Check augment config was copied
    machine.succeed("test -d /home/dev/.augment")
    machine.succeed("test -f /home/dev/.augment/session.json")
    machine.succeed("test -f /home/dev/.augment/.auggie.json")
    print("H1a: Augment config copied - PASSED")

    # Check docker config was copied
    machine.succeed("test -d /home/dev/.docker")
    machine.succeed("test -f /home/dev/.docker/config.json")
    print("H1b: Docker config copied - PASSED")

    # H2: Share permissions - Directory permissions are set correctly
    # Check directory permissions are 700
    machine.succeed("stat -c '%a' /home/dev/.augment | grep -q 700")
    machine.succeed("stat -c '%a' /home/dev/.docker | grep -q 700")
    print("H2: Directory permissions - PASSED")

    # H3: Share file overrides - Per-file permission overrides are applied
    # Check file permission overrides (600)
    machine.succeed("stat -c '%a' /home/dev/.augment/session.json | grep -q 600")
    machine.succeed("stat -c '%a' /home/dev/.augment/.auggie.json | grep -q 600")
    machine.succeed("stat -c '%a' /home/dev/.docker/config.json | grep -q 600")
    print("H3: File permission overrides - PASSED")

    # H4: Share ownership - Files are owned by the user
    machine.succeed("stat -c '%U' /home/dev/.augment | grep -q dev")
    machine.succeed("stat -c '%U' /home/dev/.docker | grep -q dev")
    machine.succeed("stat -c '%U' /home/dev/.augment/session.json | grep -q dev")
    print("H4: File ownership - PASSED")

    print("All host-shares tests passed!")
  '';
}

