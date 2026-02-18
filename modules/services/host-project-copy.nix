# Service to copy host project directory via rsync
# Only active when source.type = "copy"
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
  projectCfg = cfg.project;
  isCopy = projectCfg.source.type == "copy";

  # Build rsync exclude arguments
  excludeArgs = lib.concatMapStringsSep " " (p: "--exclude='${p}'") projectCfg.source.copy.excludePatterns;
in
{
  systemd.services.copy-host-project = lib.mkIf isCopy {
    description = "Copy host project directory via rsync";
    wantedBy = [ "multi-user.target" ];

    after = [ "local-fs.target" "systemd-modules-load.service" ];
    path = [ pkgs.coreutils pkgs.kmod pkgs.util-linux pkgs.rsync ];

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
      REFRESH="${projectCfg.source.refresh}"
      SRC_MOUNT="/mnt/host-project-src"

      # Load 9p modules if not already loaded
      modprobe 9pnet_virtio || true
      modprobe 9p || true

      # Check refresh policy - skip if destination exists and refresh is "if-missing"
      if [ "$REFRESH" = "if-missing" ] && [ -d "$DEST_PATH" ] && [ "$(ls -A "$DEST_PATH" 2>/dev/null)" ]; then
        echo "Destination $DEST_PATH exists and refresh=if-missing, skipping copy"
        exit 0
      fi

      # Create temporary mount point for source
      mkdir -p "$SRC_MOUNT"

      # Check if already mounted (e.g., by test infrastructure or earlier boot)
      already_mounted=false
      if mountpoint -q "$SRC_MOUNT" 2>/dev/null; then
        already_mounted=true
        echo "Source mount $SRC_MOUNT is already mounted"
      fi

      # Try to mount the host project share (read-only) if not already mounted
      mounted=false
      if [ "$already_mounted" = true ]; then
        mounted=true
      elif mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600,ro host-project-src "$SRC_MOUNT" 2>/dev/null; then
        echo "Mounted host project source at $SRC_MOUNT"
        mounted=true
      fi

      if [ "$mounted" = true ]; then

        # Validate marker in source if configured
        if [ "$VALIDATE_MARKER" = "true" ]; then
          if [ ! -f "$SRC_MOUNT/$MARKER" ]; then
            echo "Warning: Marker file '$MARKER' not found in source directory"
            umount "$SRC_MOUNT" 2>/dev/null || true
            if [ "$REQUIRED" = "true" ]; then
              echo "Error: Project source is required but marker validation failed"
              exit 1
            fi
            exit 0
          fi
        fi

        # Create destination directory
        mkdir -p "$DEST_PATH"

        # Copy with rsync
        echo "Copying project to $DEST_PATH..."
        rsync -a --delete ${excludeArgs} "$SRC_MOUNT/" "$DEST_PATH/"

        # Set ownership and make files writable
        chown -R ${cfg.user.name}:users "$DEST_PATH"
        chmod -R u+w "$DEST_PATH"

        echo "Successfully copied project to $DEST_PATH"

        # Unmount source only if we mounted it ourselves
        if [ "$already_mounted" = false ]; then
          umount "$SRC_MOUNT"
          rmdir "$SRC_MOUNT" 2>/dev/null || true
        fi
      else
        echo "Host project source share not available (not passed via QEMU)"
        if [ "$REQUIRED" = "true" ]; then
          echo "Error: Project source is required but copy failed"
          exit 1
        fi
      fi
    '';
  };
}

