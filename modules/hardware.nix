# Hardware configuration: boot, filesystems, QEMU guest support
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
in
{
  # Boot configuration for QEMU
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # Enable 9p kernel modules for host filesystem sharing
  boot.initrd.availableKernelModules = [ "9p" "9pnet" "9pnet_virtio" ];
  boot.kernelModules = [ "9p" "9pnet" "9pnet_virtio" ];

  # QEMU guest support
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  # VM resources (configured via options)
  virtualisation = {
    cores = cfg.vm.cores;
    memorySize = cfg.vm.memorySize;
    diskSize = cfg.vm.diskSize;

    # Disable default qemu-vm.nix networking to avoid duplicate network interfaces.
    # The runner script (mk-vm-runner.nix) provides custom networking with SSH port forwarding.
    # Must use lib.mkForce because qemu-vm.nix sets a default value in config, not in option definition.
    qemu.networkingOptions = lib.mkForce [];
  };
}

