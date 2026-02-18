# Docker integration tests
# Tests: D1-D4
# Run: nix build .#checks.x86_64-linux.tools-docker --print-build-logs
{ pkgs, self }:

pkgs.testers.nixosTest {
  name = "agentbox-tools-docker";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Disable project source for this test
    agentbox.project.source.required = false;

    # Enable docker
    agentbox.docker.enable = true;

    # Required for Docker in NixOS tests
    virtualisation.docker.enable = true;
  };

  testScript = ''
    # D2: Docker enabled - Docker daemon starts when enable=true
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("docker.service")
    machine.succeed("systemctl is-active docker.service")
    print("D2: Docker enabled - PASSED")

    # D3: Docker user access - User can run docker commands without sudo
    # User should be in the docker group
    machine.succeed("id dev | grep -q docker")
    machine.succeed("sudo -u dev docker version")
    print("D3: Docker user access - PASSED")

    # D4: Docker info - Docker daemon is functional (skip container run due to no network)
    # Verify docker info works - checks server version indicates daemon is responsive
    machine.succeed("sudo -u dev docker info --format '{{.ServerVersion}}'")
    print("D4: Docker info - PASSED")

    print("All docker tests passed!")
  '';
}

