# OpenAI Codex CLI tests
# Tests: CX1-CX2
# Run: nix build .#checks.x86_64-linux.tools-codex --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };

  # Create mock codex config directory
  mockCodexConfig = lib.mkMockConfig {
    files = {
      "config.json" = ''{"model": "gpt-4"}'';
      "instructions.md" = ''# Custom instructions'';
    };
  };

  # Create a mock codex package for testing
  mockCodex = pkgs.writeShellScriptBin "codex" ''
    echo "codex mock v1.0.0"
  '';
in
pkgs.testers.nixosTest {
  name = "agentbox-tools-codex";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for this test
    agentbox.project.source.required = false;

    # Enable codex with config sync
    agentbox.codex.enable = true;
    agentbox.codex.syncConfigFromHost = true;

    # Override the codex package with our mock
    nixpkgs.overlays = [
      (final: prev: {
        codex = mockCodex;
      })
    ];

    # Use virtualisation.sharedDirectories to simulate 9p mount
    virtualisation.sharedDirectories = {
      host-codex = {
        source = "${mockCodexConfig}";
        target = "/mnt/host-codex";
      };
    };
  };

  testScript = ''
    # CX1: Codex installed - codex binary exists when enabled
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("which codex")
    machine.succeed("codex | grep -q 'codex mock'")
    print("CX1: Codex installed - PASSED")

    # CX2: Codex config synced - ~/.codex is copied from host when syncConfigFromHost=true
    machine.wait_for_unit("copy-host-configs.service")
    machine.succeed("test -d /home/dev/.codex")
    machine.succeed("test -f /home/dev/.codex/config.json")
    machine.succeed("test -f /home/dev/.codex/instructions.md")
    machine.succeed("stat -c '%U' /home/dev/.codex | grep -q dev")
    machine.succeed("stat -c '%a' /home/dev/.codex | grep -q 700")
    print("CX2: Codex config synced - PASSED")

    print("All Codex tests passed!")
  '';
}
