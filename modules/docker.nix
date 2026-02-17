# Docker configuration module
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox.docker;
in
{
  options.agentbox.docker = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Docker daemon and install Docker packages";
    };

    syncConfigFromHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Copy Docker configuration from host ~/.docker to guest";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Docker daemon
    virtualisation.docker.enable = true;

    # Install Docker packages
    environment.systemPackages = with pkgs; [
      docker
      docker-compose
    ];

    # Add user to docker group
    users.users.${config.agentbox.user.name}.extraGroups = [ "docker" ];

    # Add host share for docker config if syncConfigFromHost is enabled
    agentbox.hostShares = lib.mkIf cfg.syncConfigFromHost [
      {
        tag = "host-docker";
        hostPath = ".docker";
        dest = ".docker";
        mode = "700";
        fileOverrides = [ "config.json:600" ];
      }
    ];
  };
}

