# Cursor CLI tests
# Tests: CU1-CU2
# Run: nix build .#checks.x86_64-linux.tools-cursor --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };

  # Create mock cursor config directory
  mockCursorConfig = lib.mkMockConfig {
    files = {
      "settings.json" = ''{"theme": "dark"}'';
      "extensions.json" = ''[]'';
    };
  };

  # Create a mock cursor package for testing (cursor-cli is unfree)
  mockCursor = pkgs.writeShellScriptBin "cursor" ''
    echo "cursor mock v1.0.0"
  '';
in
pkgs.testers.nixosTest {
  name = "agentbox-tools-cursor";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for this test
    agentbox.project.source.required = false;

    # Enable cursor config sync but don't use the module's package installation
    # (cursor-cli is unfree and can't be used in tests)
    agentbox.cursor.enable = true;
    agentbox.cursor.syncConfigFromHost = true;

    # Override the cursor package with our mock (cursor-cli is unfree)
    nixpkgs.overlays = [
      (final: prev: {
        cursor-cli = mockCursor;
      })
    ];

    # Use virtualisation.sharedDirectories to simulate 9p mount
    virtualisation.sharedDirectories = {
      host-cursor = {
        source = "${mockCursorConfig}";
        target = "/mnt/host-cursor";
      };
    };
  };

  testScript = ''
    # CU1: Cursor installed - cursor binary exists when enabled
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("which cursor")
    machine.succeed("cursor | grep -q 'cursor mock'")
    print("CU1: Cursor installed - PASSED")

    # CU2: Cursor config synced - ~/.cursor is copied from host when syncConfigFromHost=true
    machine.wait_for_unit("copy-host-configs.service")
    machine.succeed("test -d /home/dev/.cursor")
    machine.succeed("test -f /home/dev/.cursor/settings.json")
    machine.succeed("test -f /home/dev/.cursor/extensions.json")
    machine.succeed("stat -c '%U' /home/dev/.cursor | grep -q dev")
    machine.succeed("stat -c '%a' /home/dev/.cursor | grep -q 700")
    print("CU2: Cursor config synced - PASSED")

    print("All cursor tests passed!")
  '';
}

