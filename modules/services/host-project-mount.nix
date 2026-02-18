# Service to mount host project directory via 9p virtfs
# Only active when source.type = "mount"
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
  projectCfg = cfg.project;
  isMount = projectCfg.source.type == "mount";
in
{
  systemd.services.mount-host-project = lib.mkIf isMount {
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

      DEST_PATH="${projectCfg.destPath}"
      MARKER="${projectCfg.marker}"
      VALIDATE_MARKER="${if projectCfg.validateMarker then "true" else "false"}"
      REQUIRED="${if projectCfg.source.required then "true" else "false"}"

      # Load 9p modules if not already loaded
      modprobe 9pnet_virtio || true
      modprobe 9p || true

      # Create mount point
      mkdir -p "$DEST_PATH"

      # Check if already mounted (e.g., by test infrastructure or earlier boot)
      already_mounted=false
      if mountpoint -q "$DEST_PATH" 2>/dev/null; then
        already_mounted=true
        echo "Destination $DEST_PATH is already mounted"
      fi

      # Try to mount the host project share if not already mounted
      mounted=false
      if [ "$already_mounted" = true ]; then
        mounted=true
      elif mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600 host-project "$DEST_PATH" 2>/dev/null; then
        echo "Successfully mounted host project directory at $DEST_PATH"
        mounted=true
      fi

      if [ "$mounted" = true ]; then
        chown ${cfg.user.name}:users "$DEST_PATH" 2>/dev/null || true

        # Validate marker if configured
        if [ "$VALIDATE_MARKER" = "true" ]; then
          if [ ! -f "$DEST_PATH/$MARKER" ]; then
            echo "Warning: Marker file '$MARKER' not found in mounted directory"
            if [ "$REQUIRED" = "true" ]; then
              echo "Error: Project source is required but marker validation failed"
              exit 1
            fi
          else
            echo "Marker file '$MARKER' found"
          fi
        fi
      else
        echo "Host project share not available (not passed via QEMU)"
        if [ "$REQUIRED" = "true" ]; then
          echo "Error: Project source is required but mount failed"
          exit 1
        fi
      fi
    '';
  };
}

