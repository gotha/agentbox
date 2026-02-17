# Services module - imports all systemd services
{ ... }:
{
  imports = [
    ./host-config-sync.nix
    ./host-project-mount.nix
  ];
}

