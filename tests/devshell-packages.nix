# devShellPackages build-time pre-install - VM integration tests
# Tests: DS1-DS2
# Run: nix build .#checks.x86_64-linux.devshell-packages --print-build-logs
#
# Boots a VM built with devShellPackages enabled against the hermetic fixture
# and asserts the devShell's tool is on PATH (offline, no `nix develop`) and that
# the pre-install manifest is present.
{ pkgs, self }:

let
  fixture = import ./fixtures/devshell-project { inherit pkgs; system = pkgs.stdenv.hostPlatform.system; };
in
pkgs.testers.nixosTest {
  name = "agentbox-devshell-packages";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # No project source needed for this test - we only exercise build-time
    # pre-install of the devShell packages.
    agentbox.project.source.required = false;

    agentbox.project.devShellPackages = {
      enable = true;
      flake = fixture;
      name = "default";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # DS1: devShell tool baked in and on PATH, no network, no `nix develop` (US1 / SC-001)
    machine.succeed("which cowsay")
    machine.succeed("cowsay agentbox | grep -q agentbox")
    print("DS1: devShell package on PATH - PASSED")

    # DS2: pre-install manifest lists the baked-in packages (US3 / SC-006 / FR-009)
    machine.succeed("test -f /etc/agentbox/devshell-packages")
    machine.succeed("grep -q '^cowsay$' /etc/agentbox/devshell-packages")
    print("DS2: pre-install manifest present - PASSED")

    print("All devshell-packages tests passed!")
  '';
}
