{
  description = "Sample project flake with a devShell (consumed by the agentbox example)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # agentbox reads devShells.<system>.<name> from this flake at build time
      # and bakes the declared packages into the VM image.
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.jq
              pkgs.ripgrep
              pkgs.hello
            ];
          };
        });
    };
}
