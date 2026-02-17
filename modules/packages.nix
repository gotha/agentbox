# System packages configuration
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
in
{
  environment.systemPackages = with pkgs; [
    sudo
    curl
    vim
    htop
    git
    direnv
  ] ++ cfg.packages.extra;
}

