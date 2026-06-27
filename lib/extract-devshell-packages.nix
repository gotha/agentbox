# Pure helper: extract the packages declared by a project flake's devShell.
#
# Build time == evaluation time for a flake-based build, so this reads the
# project flake (a Nix value) during evaluation and returns the list of package
# derivations its selected devShell makes available. The caller (the
# devshell-packages module) appends the result to environment.systemPackages so
# the tools are baked into the VM image and available on PATH at boot.
#
# Signature: extractDevShellPackages { flake, system, name ? "default" } -> [ <package> ]
#
# Errors (clear, fail-loud — never a silent no-op):
#   - flake has no devShells for the given system  -> throw
#   - the named devShell does not exist            -> throw (lists available names)
#   - the devShell declares no installable packages -> throw
{ lib }:

{ flake, system, name ? "default" }:
let
  hasDevShellsForSystem =
    flake ? devShells && flake.devShells ? ${system};

  devShellsForSystem =
    if hasDevShellsForSystem
    then flake.devShells.${system}
    else throw "agentbox.project.devShellPackages: project flake has no devShells for system '${system}'";

  availableNames = builtins.attrNames devShellsForSystem;

  shell =
    if devShellsForSystem ? ${name}
    then devShellsForSystem.${name}
    else throw "agentbox.project.devShellPackages: devShell '${name}' not found for system '${system}'. Available: ${
      if availableNames == [] then "none" else builtins.concatStringsSep ", " availableNames
    }";

  # mkShell merges `packages` into nativeBuildInputs; collect every input kind so
  # tools declared via packages/buildInputs/propagated* are all captured.
  collected =
    (shell.buildInputs or [])
    ++ (shell.nativeBuildInputs or [])
    ++ (shell.propagatedBuildInputs or [])
    ++ (shell.propagatedNativeBuildInputs or []);

  # De-duplicate by derivation identity (same package referenced twice).
  deduped = lib.unique collected;
in
if deduped == []
then throw "agentbox.project.devShellPackages: devShell '${name}' for system '${system}' declares no installable packages"
else deduped
