# Service to copy host configurations (Docker, Augment, etc.) on boot
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;

  # Generate copy commands for each host share
  copyCommands = lib.concatMapStringsSep "\n" (share:
    let
      fileOverrides = lib.concatMapStringsSep " " (o: ''"${o}"'') share.fileOverrides;
    in ''
      copy_host_config "${share.tag}" "${cfg.user.home}/${share.dest}" "${share.mode}" ${fileOverrides}
    ''
  ) cfg.hostShares;

  # Only enable if there are shares configured
  hasShares = cfg.hostShares != [];
in
{
  config = lib.mkIf hasShares {
    systemd.services.copy-host-configs = {
      description = "Copy host configurations";
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

        # Helper function to copy a host config directory via 9p mount
        # Usage: copy_host_config <mount_tag> <dest_dir> <dir_mode> [file_mode_overrides...]
        # file_mode_overrides are in format "filename:mode"
        copy_host_config() {
          local tag="$1"
          local dest="$2"
          local dir_mode="$3"
          shift 3
          local file_overrides=("$@")

          local mount_point="/mnt/$tag"
          mkdir -p "$mount_point"

          # Check if already mounted (e.g., by test infrastructure or earlier boot)
          local already_mounted=false
          if mountpoint -q "$mount_point" 2>/dev/null; then
            already_mounted=true
            echo "Mount point $mount_point is already mounted"
          fi

          # Try to mount if not already mounted
          if [ "$already_mounted" = false ]; then
            if mount -t 9p -o trans=virtio,version=9p2000.L,ro "$tag" "$mount_point" 2>/dev/null; then
              echo "Mounted $tag at $mount_point"
            else
              echo "Host config '$tag' not available (skipping)"
              return 0
            fi
          fi

          # Now check if there are files to copy
          if [ -d "$mount_point" ] && [ "$(ls -A "$mount_point" 2>/dev/null)" ]; then
            echo "Copying $tag -> $dest"

            mkdir -p "$dest"
            cp -r "$mount_point/." "$dest/" 2>/dev/null || true
            chown -R ${cfg.user.name}:users "$dest"
            chmod "$dir_mode" "$dest"

            # Apply file-specific permission overrides
            for override in "''${file_overrides[@]}"; do
              local file="''${override%%:*}"
              local mode="''${override##*:}"
              [ -f "$dest/$file" ] && chmod "$mode" "$dest/$file"
            done

            echo "Files in $dest:"
            ls -la "$dest/" || true
          else
            echo "Mount point $mount_point has no files (skipping)"
          fi

          # Unmount only if we mounted it ourselves
          if [ "$already_mounted" = false ]; then
            umount "$mount_point" || true
          fi
        }

        ${copyCommands}

        echo "Host config copy complete."
      '';
    };
  };
}

