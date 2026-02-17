# Development tools configuration: Nix, direnv, git
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;

  # Generate git safe.directory entries
  gitSafeDirectories = lib.concatMapStringsSep "\n" (dir: ''
        directory = ${dir}'') cfg.development.git.safeDirectories;

  # Generate direnv whitelist entries
  direnvWhitelist = lib.concatMapStringsSep ", " (path: ''"${path}"'') cfg.development.direnv.whitelist;
in
{
  # Enable Nix with flakes support
  nix.settings.experimental-features =
    lib.optionals cfg.development.nix.enableFlakes [ "nix-command" "flakes" ];

  # Configure Git to trust mounted directories
  environment.etc."gitconfig".text = ''
    [safe]
    ${gitSafeDirectories}
  '';

  # Enable direnv with nix-direnv integration
  programs.direnv = lib.mkIf cfg.development.direnv.enable {
    enable = true;
    nix-direnv.enable = true;
  };

  # Whitelist directories for direnv (auto-allow .envrc)
  environment.etc."direnv/direnv.toml".text = lib.mkIf cfg.development.direnv.enable ''
    [whitelist]
    prefix = [ ${direnvWhitelist} ]
  '';
}

