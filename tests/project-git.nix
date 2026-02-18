# Project source: git tests
# Tests: G1-G7
# Run: nix build .#checks.x86_64-linux.project-git --print-build-logs
{ pkgs, self }:

let
  # Create a local git repository for testing (no network access in sandbox)
  mockGitRepo = ./fixtures/mock-git-repo;
in
pkgs.testers.nixosTest {
  name = "agentbox-project-git";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";

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
    agentbox.project.source.git.shallow = true;
    agentbox.project.destPath = "/home/dev/project";

    # Mock repo has a README file, use that as marker
    agentbox.project.marker = "README";
    agentbox.project.validateMarker = true;
  };

  testScript = ''
    # G1: Git clone - Repository is cloned successfully from local repo
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("clone-host-project.service")
    machine.succeed("test -d /home/dev/project")
    machine.succeed("test -d /home/dev/project/.git")
    machine.succeed("test -f /home/dev/project/README")
    print("G1: Git clone - PASSED")

    # G2: Git clone shallow - Shallow clone has limited history
    # Shallow clones have a .git/shallow file
    machine.succeed("test -f /home/dev/project/.git/shallow")
    print("G2: Git clone shallow - PASSED")

    # G3: Git checkout ref - Specific branch is checked out
    machine.succeed("cd /home/dev/project && git rev-parse --abbrev-ref HEAD | grep -q master")
    print("G3: Git checkout ref - PASSED")

    # G4: Git ownership - Cloned files are owned by the user
    machine.succeed("stat -c '%U' /home/dev/project | grep -q dev")
    print("G4: Git ownership - PASSED")

    # G5: Git writable - User can modify cloned repository
    machine.succeed("sudo -u dev touch /home/dev/project/test-file.txt")
    machine.succeed("sudo -u dev rm /home/dev/project/test-file.txt")
    print("G5: Git writable - PASSED")

    # G7: Git marker validation - Marker file is validated after clone
    # The service succeeded, which means marker validation passed
    machine.succeed("test -f /home/dev/project/README")
    print("G7: Git marker validation - PASSED")

    print("All project-git tests passed!")
  '';
}

