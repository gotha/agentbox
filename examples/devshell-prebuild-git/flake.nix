{
  description = "Example VM that pre-installs a project's devShell packages at build time";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    agentbox.url = "github:gotha/agentbox";

    # The project whose devShell packages get baked into the VM image at build
    # time. It is passed to agentbox as a Nix value, so it must be a flake input
    # readable at evaluation time (fetched/locked with your normal git/SSH creds).
    #
    # In real use, point this at your repository, e.g.:
    #   project.url = "git+ssh://git@github.com/you/your-project";
    #
    # Here it references a bundled sample project so the example is self-contained.
    project.url = "path:./project";
  };

  outputs = { self, nixpkgs, agentbox, project }:
    let
      allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in
    {
      nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
        name = "vm-${hostSystem}";
        value = agentbox.lib.mkDevVm {
          inherit hostSystem;
          extraConfig = {
            agentbox.vm.hostname = "devshell-vm";

            # Optionally also clone the same repo at runtime. The runtime source
            # (a git URL string, cloned after boot) is independent of the
            # build-time devShell extraction (the flake input below).
            # agentbox.project.source.type = "git";
            # agentbox.project.source.git.url = "git@github.com:you/your-project.git";

            # Bake the project's devShell packages into the image at build time.
            # After boot they are on PATH - no download, no `nix develop` needed.
            agentbox.project.devShellPackages = {
              enable = true;
              flake = project;
              # name = "default";   # or a named devShell: devShells.<system>.<name>
            };
          };
        };
      }) allSystems);

      apps = agentbox.lib.mkVmApps {
        inherit (self) nixosConfigurations;
      };
    };
}
