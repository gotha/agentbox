# Hermetic devShell test fixture for agentbox devShellPackages tests.
#
# Returns a flake-shaped value (an attrset with `devShells.<system>`) that the
# `agentbox.project.devShellPackages.flake` option accepts directly. Using a
# synthetic value (rather than a real on-disk flake fetched over the network)
# keeps both the eval tests and the offline-boot VM test fully hermetic.
#
# Shells:
#   default - declares a distinctive tool (cowsay) for PATH assertions
#   ci      - a named shell (hello) to exercise `name` selection
#   empty   - declares no packages, to exercise the "no installable packages" error
{ pkgs, system }:
{
  devShells.${system} = {
    default = pkgs.mkShell {
      packages = [ pkgs.cowsay ];
    };

    ci = pkgs.mkShell {
      packages = [ pkgs.hello ];
    };

    empty = pkgs.mkShell { };
  };
}
