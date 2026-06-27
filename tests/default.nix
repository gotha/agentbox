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

  # Claude Code tests (CC1-CC2)
  tools-claude-code = import ./tools-claude-code.nix { inherit pkgs self; };

  # OpenAI Codex CLI tests (CX1-CX2)
  tools-codex = import ./tools-codex.nix { inherit pkgs self; };

  # Charmbracelet Crush tests (CR1-CR2)
  tools-crush = import ./tools-crush.nix { inherit pkgs self; };

  # Cursor CLI tests (CU1-CU2)
  tools-cursor = import ./tools-cursor.nix { inherit pkgs self; };

  # devShellPackages build-time pre-install: VM integration test (DS1-DS2)
  devshell-packages = import ./devshell-packages.nix { inherit pkgs self; };

  # devShellPackages extraction helper: pure eval tests
  devshell-packages-eval = import ./devshell-packages-eval.nix { inherit pkgs self; };

  # devShellPackages module behavior: NixOS eval tests (default-off, null-flake assertion)
  devshell-packages-module-eval = import ./devshell-packages-module-eval.nix { inherit pkgs self; };
}

