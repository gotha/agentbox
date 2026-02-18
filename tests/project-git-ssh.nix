# Project source: git with SSH keys tests
# Tests: GS1-GS3
# Verifies that git clone service waits for host config sync (SSH keys, known_hosts)
# Run: nix build .#checks.x86_64-linux.project-git-ssh --print-build-logs
{ pkgs, self }:

let
  lib = import ./lib.nix { inherit pkgs self; };

  # Create a local git repository for testing (no network access in sandbox)
  mockGitRepo = ./fixtures/mock-git-repo;

  # Create mock SSH config directory (simulating ~/.ssh from host)
  mockSshConfig = lib.mkMockConfig {
    files = {
      "config" = ''
Host github.com
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking no
'';
      "known_hosts" = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      "id_ed25519.pub" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAATEST test@example.com";
    };
  };
in
pkgs.testers.nixosTest {
  name = "agentbox-project-git-ssh";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

    # Configure SSH keys share (simulates sharing ~/.ssh from host)
    agentbox.hostShares = [
      {
        tag = "ssh-keys";
        hostPath = ".ssh";
        dest = ".ssh";
        mode = "700";
        fileOverrides = [ "id_ed25519:600" "id_ed25519.pub:644" ];
      }
    ];

    # Share mock SSH config into the VM
    virtualisation.sharedDirectories.ssh-keys = {
      source = "${mockSshConfig}";
      target = "/mnt/ssh-keys";
    };

    # Share the local git repo into the VM
    virtualisation.sharedDirectories.mock-git-repo = {
      source = "${mockGitRepo}";
      target = "/mnt/mock-git-repo";
    };

    # Configure git source type with local repo (file:// protocol)
    agentbox.project.source.type = "git";
    agentbox.project.source.required = true;
    agentbox.project.source.refresh = "always";
    agentbox.project.source.git.url = "file:///mnt/mock-git-repo";
    agentbox.project.source.git.ref = "master";
    agentbox.project.destPath = "/home/dev/project";
    agentbox.project.marker = "README";
    agentbox.project.validateMarker = true;
  };

  testScript = ''
    # GS1: Service ordering - clone-host-project depends on copy-host-configs
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Verify the dependency exists in systemd
    output = machine.succeed("systemctl show clone-host-project.service --property=After")
    assert "copy-host-configs.service" in output, f"Expected copy-host-configs.service in After, got: {output}"
    print("GS1a: clone-host-project has After dependency on copy-host-configs - PASSED")

    output = machine.succeed("systemctl show clone-host-project.service --property=Requires")
    assert "copy-host-configs.service" in output, f"Expected copy-host-configs.service in Requires, got: {output}"
    print("GS1b: clone-host-project has Requires dependency on copy-host-configs - PASSED")

    # GS2: SSH config is copied before git clone
    # Both services should have completed successfully
    machine.wait_for_unit("copy-host-configs.service")
    machine.wait_for_unit("clone-host-project.service")

    # Verify SSH config was copied
    machine.succeed("test -d /home/dev/.ssh")
    machine.succeed("test -f /home/dev/.ssh/config")
    machine.succeed("test -f /home/dev/.ssh/known_hosts")
    print("GS2: SSH config copied before git clone - PASSED")

    # Verify SSH directory permissions
    machine.succeed("stat -c '%a' /home/dev/.ssh | grep -q 700")
    print("GS2b: SSH directory has correct permissions (700) - PASSED")

    # GS3: Git clone succeeded with SSH config available
    machine.succeed("test -d /home/dev/project")
    machine.succeed("test -d /home/dev/project/.git")
    machine.succeed("test -f /home/dev/project/README")
    print("GS3: Git clone succeeded with SSH config available - PASSED")

    print("All project-git-ssh tests passed!")
  '';
}

