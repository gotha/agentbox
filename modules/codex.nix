# OpenAI Codex CLI configuration module
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox.codex;
in
{
  options.agentbox.codex = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OpenAI Codex CLI package";
    };

    syncConfigFromHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Copy Codex configuration from host ~/.codex to guest";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.codex ];

    agentbox.hostShares = lib.mkIf cfg.syncConfigFromHost [{
      tag = "host-codex";
      hostPath = ".codex";
      dest = ".codex";
      mode = "700";
      fileOverrides = [ ];
    }];
  };
}

