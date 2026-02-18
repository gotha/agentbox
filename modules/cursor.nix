# Cursor CLI configuration module
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox.cursor;
in
{
  options.agentbox.cursor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Cursor CLI package";
    };

    syncConfigFromHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Copy Cursor configuration from host ~/.cursor to guest";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install cursor-cli package
    environment.systemPackages = [ pkgs.cursor-cli ];

    # Add host share for cursor config if syncConfigFromHost is enabled
    agentbox.hostShares = lib.mkIf cfg.syncConfigFromHost [
      {
        tag = "host-cursor";
        hostPath = ".cursor";
        dest = ".cursor";
        mode = "700";
        fileOverrides = [];
      }
    ];
  };
}

