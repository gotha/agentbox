# Service to mount host project directory via 9p virtfs
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
in
{
  systemd.services.mount-host-project = {
    description = "Mount host project directory via 9p";
    wantedBy = [ "multi-user.target" ];

    after = [ "local-fs.target" "systemd-modules-load.service" ];
    path = [ pkgs.coreutils pkgs.kmod pkgs.util-linux ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -e

      # Load 9p modules if not already loaded
      modprobe 9pnet_virtio || true
      modprobe 9p || true

      # Create mount point
      mkdir -p ${cfg.project.mountPath}

      # Try to mount the host project share
      if mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600 host-project ${cfg.project.mountPath} 2>/dev/null; then
        echo "Successfully mounted host project directory at ${cfg.project.mountPath}"
        chown ${cfg.user.name}:users ${cfg.project.mountPath}
      else
        echo "Host project share not available (not passed via QEMU)"
      fi

      ${lib.optionalString (cfg.project.symlink != null) ''
        # Create symlink if configured
        if [ -d "${cfg.project.mountPath}" ]; then
          ln -sfn ${cfg.project.mountPath} ${cfg.project.symlink}
          echo "Created symlink: ${cfg.project.symlink} -> ${cfg.project.mountPath}"
        fi
      ''}
    '';
  };
}

