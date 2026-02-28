# Claude Code configuration module
{ config, lib, pkgs, ... }:
let cfg = config.agentbox.claudecode;
in
{
  options.agentbox.claudecode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Claude Code package";
    };

    syncConfigFromHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Copy Claude Code configuration from host ~/.claude to guest";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.claude-code ];

    agentbox.hostShares = lib.mkIf cfg.syncConfigFromHost [{
      tag = "host-claude-code";
      hostPath = ".claude";
      dest = ".claude";
      mode = "700";
      fileOverrides = [ ];
    }];
  };
}

