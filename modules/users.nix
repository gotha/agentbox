# User configuration: accounts, sudo, PAM
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
in
{
  # Disable mutable users for reproducibility
  users.mutableUsers = false;

  # Primary development user
  users.users.${cfg.user.name} = {
    isNormalUser = true;
    home = cfg.user.home;
    hashedPassword = cfg.user.hashedPassword;
    extraGroups = cfg.user.extraGroups;
    shell = cfg.user.shell;
  };

  # Root user for emergency access (dev VM only!)
  users.users.root.hashedPassword = "";

  # Allow empty passwords for login (dev VM only!)
  # This enables passwordless SSH and console login
  security.pam.services.login.allowNullPassword = true;
  security.pam.services.sshd.allowNullPassword = true;

  # Passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}

