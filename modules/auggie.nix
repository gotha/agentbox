# Auggie (Augment Code CLI) configuration module
{ config, lib, gothaPkgs ? {}, ... }:
let
  cfg = config.agentbox.auggie;
in
{
  options.agentbox.auggie = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Auggie (Augment Code CLI) package";
    };

    syncConfigFromHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Copy Auggie configuration from host ~/.augment to guest";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install auggie package from gotha-nixpkgs
    environment.systemPackages = lib.mkIf (gothaPkgs ? auggie) [ gothaPkgs.auggie ];

    # Disable auto-update (managed by Nix)
    environment.variables.AUGMENT_DISABLE_AUTO_UPDATE = "1";

    # Add host share for auggie config if syncConfigFromHost is enabled
    agentbox.hostShares = lib.mkIf cfg.syncConfigFromHost [
      {
        tag = "host-augment";
        hostPath = ".augment";
        dest = ".augment";
        mode = "700";
        fileOverrides = [];
      }
    ];
  };
}

