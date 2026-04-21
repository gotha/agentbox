# Charmbracelet Crush tests
# Tests: CR1-CR2
# Run: nix build .#checks.x86_64-linux.tools-crush --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };

  # Create mock crush config directory (stored in .local/share/crush)
  mockCrushConfig = lib.mkMockConfig {
    files = {
      "crush.json" = ''{"provider": "anthropic", "model": "claude-3-opus"}'';
      "sessions.db" = '''';
    };
  };

  # Create a mock crush package for testing
  mockCrush = pkgs.writeShellScriptBin "crush" ''
    echo "crush mock v1.0.0"
  '';
in
pkgs.testers.nixosTest {
  name = "agentbox-tools-crush";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for this test
    agentbox.project.source.required = false;

    # Enable crush with config sync
    agentbox.crush.enable = true;
    agentbox.crush.syncConfigFromHost = true;

    # Override the crush package with our mock
    nixpkgs.overlays = [
      (final: prev: {
        crush = mockCrush;
      })
    ];

    # Use virtualisation.sharedDirectories to simulate 9p mount
    # Note: crush stores config in .local/share/crush
    virtualisation.sharedDirectories = {
      host-crush = {
        source = "${mockCrushConfig}";
        target = "/mnt/host-crush";
      };
    };
  };

  testScript = ''
    # CR1: Crush installed - crush binary exists when enabled
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("which crush")
    machine.succeed("crush | grep -q 'crush mock'")
    print("CR1: Crush installed - PASSED")

    # CR2: Crush config synced - ~/.local/share/crush is copied from host when syncConfigFromHost=true
    machine.wait_for_unit("copy-host-configs.service")
    machine.succeed("test -d /home/dev/.local/share/crush")
    machine.succeed("test -f /home/dev/.local/share/crush/crush.json")
    machine.succeed("stat -c '%U' /home/dev/.local/share/crush | grep -q dev")
    machine.succeed("stat -c '%a' /home/dev/.local/share/crush | grep -q 700")
    print("CR2: Crush config synced - PASSED")

    print("All Crush tests passed!")
  '';
}
