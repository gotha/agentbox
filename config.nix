# Default configuration values for the development VM
# These can be overridden via module options in consuming flakes
{
  # VM Resources
  vm = {
    cores = 4;
    memorySize = 8192;  # MB
    diskSize = 50000;   # MB
    hostname = "dev-vm";
  };

  # Primary user configuration
  user = {
    name = "dev";
    home = "/home/dev";
    extraGroups = [ "wheel" ];
  };

  # Network configuration
  networking = {
    ports = [ 22 ];  # Base ports, projects add their own
    ssh = {
      enable = true;
      permitRootLogin = "no";
      passwordAuth = true;
    };
  };

  # Host shares to sync into VM on boot
  # Projects should override this with their specific needs
  hostShares = [];

  # Project mounting
  project = {
    mountPath = "/home/dev/project";
    marker = "flake.nix";  # File that identifies project root
    symlink = null;        # Optional symlink path
  };

  # Environment variables
  environment = {
    editor = "vim";
    variables = {};
  };

  # Development tools
  development = {
    nix = {
      enableFlakes = true;
    };
    direnv = {
      enable = true;
      whitelist = [ "/home/dev/project" ];
    };
    git = {
      safeDirectories = [ "/home/dev/project" "*" ];
    };
  };

}

