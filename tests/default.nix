# Agentbox test suite
# Run all tests: nix flake check
# Run specific test: nix build .#checks.x86_64-linux.boot --print-build-logs
{ pkgs, self }:

{
  # Basic VM boot tests (B1-B5)
  boot = import ./boot.nix { inherit pkgs self; };

  # Project source: mount tests (M1-M6)
  project-mount = import ./project-mount.nix { inherit pkgs self; };

  # Project source: copy tests (C1-C6)
  project-copy = import ./project-copy.nix { inherit pkgs self; };

  # Project source: git tests (G1-G7)
  project-git = import ./project-git.nix { inherit pkgs self; };

  # Project source: git with SSH keys tests (GS1-GS3)
  project-git-ssh = import ./project-git-ssh.nix { inherit pkgs self; };

  # Host shares sync tests (H1-H4)
  host-shares = import ./host-shares.nix { inherit pkgs self; };

  # Docker integration tests (D1-D4)
  tools-docker = import ./tools-docker.nix { inherit pkgs self; };

  # Auggie (Augment Code CLI) tests (A1-A3)
  tools-auggie = import ./tools-auggie.nix { inherit pkgs self; };

  # Cursor CLI tests (CU1-CU2)
  tools-cursor = import ./tools-cursor.nix { inherit pkgs self; };
}

