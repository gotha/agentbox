# Claude Code tests
# Tests: CC1-CC2
# Run: nix build .#checks.x86_64-linux.tools-claude-code --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };

  # Create mock claude config directory
  mockClaudeConfig = lib.mkMockConfig {
    files = {
      "settings.json" = ''{"model": "claude-3-opus"}'';
      "credentials.json" = ''{"api_key": "test-key"}'';
    };
  };

  # Create a mock claude-code package for testing
  mockClaudeCode = pkgs.writeShellScriptBin "claude" ''
    echo "claude-code mock v1.0.0"
  '';
in
pkgs.testers.nixosTest {
  name = "agentbox-tools-claude-code";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for this test
    agentbox.project.source.required = false;

    # Enable claude-code with config sync
    agentbox.claudecode.enable = true;
    agentbox.claudecode.syncConfigFromHost = true;

    # Override the claude-code package with our mock
    nixpkgs.overlays = [
      (final: prev: {
        claude-code = mockClaudeCode;
      })
    ];

    # Use virtualisation.sharedDirectories to simulate 9p mount
    virtualisation.sharedDirectories = {
      host-claude-code = {
        source = "${mockClaudeConfig}";
        target = "/mnt/host-claude-code";
      };
    };
  };

  testScript = ''
    # CC1: Claude Code installed - claude binary exists when enabled
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("which claude")
    machine.succeed("claude | grep -q 'claude-code mock'")
    print("CC1: Claude Code installed - PASSED")

    # CC2: Claude Code config synced - ~/.claude is copied from host when syncConfigFromHost=true
    machine.wait_for_unit("copy-host-configs.service")
    machine.succeed("test -d /home/dev/.claude")
    machine.succeed("test -f /home/dev/.claude/settings.json")
    machine.succeed("test -f /home/dev/.claude/credentials.json")
    machine.succeed("stat -c '%U' /home/dev/.claude | grep -q dev")
    machine.succeed("stat -c '%a' /home/dev/.claude | grep -q 700")
    print("CC2: Claude Code config synced - PASSED")

    print("All Claude Code tests passed!")
  '';
}
