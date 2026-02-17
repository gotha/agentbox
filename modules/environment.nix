# Environment variables configuration
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
in
{
  environment.variables = {
    EDITOR = cfg.environment.editor;
  } // cfg.environment.variables;
}

