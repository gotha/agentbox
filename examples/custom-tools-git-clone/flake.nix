{
  description = "Example Go project development VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    agentbox.url = "github:gotha/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in
    {
      nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
        name = "vm-${hostSystem}";
        value = agentbox.lib.mkDevVm {
          inherit hostSystem;
          extraConfig = {
            agentbox.vm.hostname = "hellogo-vm";

            agentbox.project = {
              source.type = "git";
              source.git.url = "git@github.com:gotha/hellogo-private.git";
              destPath = "/home/dev/project";
              marker = "go.mod";
            };

            # SSH keys for git authentication - synced from host
            agentbox.hostShares = [{
              tag = "ssh-keys";
              hostPath = ".ssh";
              dest = ".ssh";
              mode = "700";
              fileOverrides = [ "id_rsa:600" "id_rsa.pub:644" "known_hosts:644" ];
            }];

            # Add project-specific packages
            agentbox.packages.extra = with nixpkgs.legacyPackages.${
              if hostSystem == "aarch64-darwin" then "aarch64-linux"
              else if hostSystem == "x86_64-darwin" then "x86_64-linux"
              else hostSystem
            }; [
              actionlint
              go
              gnumake
              golangci-lint
              go-swag
              gosec
            ];

            # Set environment variables
            agentbox.environment.variables = {
              CGO_ENABLED = 0;
              API_URL = "http://localhost:8080";
            };

            # Enable auggie with config sync from host
            agentbox.auggie = {
              enable = true;
              syncConfigFromHost = true;
            };

            # Enable docker with config sync from host
            agentbox.docker = {
              enable = true;
              syncConfigFromHost = true;
            };
          };
        };
      }) allSystems);

      apps = agentbox.lib.mkVmApps {
        inherit (self) nixosConfigurations;
      };
    };
}

