# Charmbracelet Crush AI coding assistant configuration module
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox.crush;
in
{
  options.agentbox.crush = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Charmbracelet Crush AI coding assistant";
    };

    syncConfigFromHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Copy Crush configuration from host ~/.local/share/crush to guest";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.crush ];

    agentbox.hostShares = lib.mkIf cfg.syncConfigFromHost [{
      tag = "host-crush";
      hostPath = ".local/share/crush";
      dest = ".local/share/crush";
      mode = "700";
      fileOverrides = [ ];
    }];
  };
}
