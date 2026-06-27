# Build-time pre-install of a project flake's devShell packages.
#
# When agentbox.project.devShellPackages.enable is true, this reads the project
# flake's selected devShell at evaluation time, extracts its packages, and adds
# them to environment.systemPackages so they are baked into the VM image and
# available on PATH the moment the VM boots (no download, offline-capable).
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox.project.devShellPackages;

  extractDevShellPackages = import ../lib/extract-devshell-packages.nix { inherit lib; };

  # The VM is always built for the guest system; pkgs is the guest's package set,
  # so pkgs.system is the correct system to resolve devShells.<system> against.
  # (Works both via lib.mkDevVm and when the module is used directly in tests.)
  system = pkgs.stdenv.hostPlatform.system;

  # Guard extraction so a null flake produces the friendly assertion below
  # instead of a raw "no devShells" throw.
  extracted =
    if cfg.flake == null
    then [ ]
    else extractDevShellPackages {
      inherit (cfg) flake name;
      inherit system;
    };

  pkgNames = map (p: lib.getName p) extracted;

  # Surface what was pre-installed at build time (FR-009).
  tracedPackages =
    if extracted == [ ]
    then extracted
    else builtins.trace
      "agentbox.project.devShellPackages: pre-installing from devShell '${cfg.name}' (${system}): ${lib.concatStringsSep ", " pkgNames}"
      extracted;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.flake != null;
        message = ''
          agentbox.project.devShellPackages.enable is true but
          agentbox.project.devShellPackages.flake is null.

          Provide the project flake as a Nix value (a locked flake input), e.g.:
            agentbox.project.devShellPackages.flake = inputs.project;

          Build-time devShell extraction requires a flake readable at evaluation
          time, so it is supported only for git-style flake inputs - not for
          mount/copy project sources, whose contents only exist after boot.
        '';
      }
    ];

    # Bake the devShell's packages into the image as global packages (on PATH).
    environment.systemPackages = tracedPackages;

    # Readable manifest of what was pre-installed, enumerable from inside the VM.
    environment.etc."agentbox/devshell-packages".text =
      lib.concatStringsSep "\n" pkgNames + "\n";
  };
}
