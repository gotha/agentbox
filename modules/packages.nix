# System packages configuration
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
in
{
  environment.systemPackages = with pkgs; [
    # Base utilities
    sudo
    curl
    vim
    htop
    direnv

    # Always install git and rsync to support all project source types
    git
    rsync
  ] ++ cfg.packages.extra;
}

