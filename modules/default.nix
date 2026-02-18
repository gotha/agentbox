# Main agentbox module - defines options and imports sub-modules
{ config, lib, pkgs, ... }:
with lib;
let
  defaults = import ../config.nix;

  # Host share submodule type
  hostShareType = types.submodule {
    options = {
      tag = mkOption {
        type = types.str;
        description = "9p mount tag used by QEMU";
        example = "host-docker";
      };
      hostPath = mkOption {
        type = types.str;
        description = "Path relative to $HOME on host";
        example = ".docker";
      };
      dest = mkOption {
        type = types.str;
        description = "Path relative to user home in VM";
        example = ".docker";
      };
      mode = mkOption {
        type = types.str;
        default = "700";
        description = "Directory permissions";
      };
      fileOverrides = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Per-file permission overrides in format 'filename:mode'";
        example = [ "config.json:600" ];
      };
    };
  };
in
{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ./packages.nix
    ./development.nix
    ./environment.nix
    ./docker.nix
    ./auggie.nix
    ./services
  ];

  options.agentbox = {
    # VM Resources
    vm = {
      cores = mkOption {
        type = types.int;
        default = defaults.vm.cores;
        description = "Number of CPU cores";
      };
      memorySize = mkOption {
        type = types.int;
        default = defaults.vm.memorySize;
        description = "RAM in megabytes";
      };
      diskSize = mkOption {
        type = types.int;
        default = defaults.vm.diskSize;
        description = "Disk size in megabytes";
      };
      hostname = mkOption {
        type = types.str;
        default = defaults.vm.hostname;
        description = "VM hostname";
      };
    };

    # User configuration
    user = {
      name = mkOption {
        type = types.str;
        default = defaults.user.name;
        description = "Primary user name";
      };
      home = mkOption {
        type = types.str;
        default = defaults.user.home;
        description = "User home directory";
      };
      extraGroups = mkOption {
        type = types.listOf types.str;
        default = defaults.user.extraGroups;
        description = "Additional groups for the user";
      };
      shell = mkOption {
        type = types.package;
        default = pkgs.bash;
        description = "User's login shell";
      };
      hashedPassword = mkOption {
        type = types.str;
        default = "";
        description = "Hashed password (empty for no password)";
      };
    };

    # Networking
    networking = {
      ports = mkOption {
        type = types.listOf types.int;
        default = defaults.networking.ports;
        description = "TCP ports to open in firewall";
      };
      ssh = {
        enable = mkOption {
          type = types.bool;
          default = defaults.networking.ssh.enable;
          description = "Enable SSH server";
        };
        permitRootLogin = mkOption {
          type = types.str;
          default = defaults.networking.ssh.permitRootLogin;
          description = "Root login policy";
        };
        passwordAuth = mkOption {
          type = types.bool;
          default = defaults.networking.ssh.passwordAuth;
          description = "Allow password authentication";
        };
      };
    };

    # Host shares
    hostShares = mkOption {
      type = types.listOf hostShareType;
      default = defaults.hostShares;
      description = "Host directories to sync into VM on boot";
    };

    # Project mounting
    project = {
      mountPath = mkOption {
        type = types.str;
        default = defaults.project.mountPath;
        description = "Where to mount host project";
      };
      marker = mkOption {
        type = types.str;
        default = defaults.project.marker;
        description = "File that identifies project root";
      };
      symlink = mkOption {
        type = types.nullOr types.str;
        default = defaults.project.symlink;
        description = "Optional symlink to create pointing to mount";
      };
    };

    # Packages
    packages = {
      extra = mkOption {
        type = types.listOf types.package;
        default = [];
        description = "Additional packages to install";
      };
    };

    # Environment
    environment = {
      editor = mkOption {
        type = types.str;
        default = defaults.environment.editor;
        description = "Default editor";
      };
      variables = mkOption {
        type = types.attrsOf types.str;
        default = defaults.environment.variables;
        description = "Environment variables to set";
      };
    };

    # Development tools
    development = {
      nix = {
        enableFlakes = mkOption {
          type = types.bool;
          default = defaults.development.nix.enableFlakes;
          description = "Enable Nix flakes";
        };
      };
      direnv = {
        enable = mkOption {
          type = types.bool;
          default = defaults.development.direnv.enable;
          description = "Enable direnv";
        };
        whitelist = mkOption {
          type = types.listOf types.str;
          default = defaults.development.direnv.whitelist;
          description = "Paths to auto-allow .envrc";
        };
      };
      git = {
        safeDirectories = mkOption {
          type = types.listOf types.str;
          default = defaults.development.git.safeDirectories;
          description = "Git safe.directory entries";
        };
      };
    };

  };

  # System state version
  config.system.stateVersion = "25.11";
}

