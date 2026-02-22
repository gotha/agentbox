{
  description = "Minimal agentbox VM with Cursor CLI";

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
            agentbox.project = {
              source.type = "mount";
              marker = "package.json";
            };

            agentbox.cursor = {
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

