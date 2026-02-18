# Basic VM boot tests
# Tests: B1-B5
# Run: nix build .#checks.x86_64-linux.boot --print-build-logs
{ pkgs, self }:

pkgs.testers.nixosTest {
  name = "agentbox-boot";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    # Minimal configuration for boot test
    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for boot tests (no 9p share available)
    agentbox.project.source.required = false;
  };

  testScript = ''
    # B1: Basic boot - VM boots to multi-user.target
    machine.start()
    machine.wait_for_unit("multi-user.target")
    print("B1: Basic boot - PASSED")

    # B2: User exists - Primary user (dev) exists and can log in
    machine.succeed("id dev")
    machine.succeed("getent passwd dev")
    machine.succeed("test -d /home/dev")
    print("B2: User exists - PASSED")

    # B3: Sudo works - User has passwordless sudo access
    machine.succeed("sudo -u dev sudo -n true")
    machine.succeed("sudo -u dev sudo whoami | grep -q root")
    print("B3: Sudo works - PASSED")

    # B4: SSH enabled - SSH service is running
    machine.wait_for_unit("sshd.service")
    machine.succeed("systemctl is-active sshd.service")
    print("B4: SSH enabled - PASSED")

    # B5: Base packages - Core packages are available
    machine.succeed("which git")
    machine.succeed("which rsync")
    machine.succeed("which vim")
    machine.succeed("which curl")
    machine.succeed("which htop")
    machine.succeed("which direnv")
    print("B5: Base packages - PASSED")

    print("All boot tests passed!")
  '';
}

