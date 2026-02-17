# Networking configuration: hostname, firewall, SSH
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
in
{
  # Hostname
  networking.hostName = cfg.vm.hostname;

  # Firewall - open configured ports
  networking.firewall.allowedTCPPorts = cfg.networking.ports;

  # SSH access
  services.openssh = lib.mkIf cfg.networking.ssh.enable {
    enable = true;
    settings = {
      PasswordAuthentication = cfg.networking.ssh.passwordAuth;
      PermitRootLogin = cfg.networking.ssh.permitRootLogin;
    };
  };
}

