# Service to clone git repository
# Only active when source.type = "git"
{ config, lib, pkgs, ... }:
let
  cfg = config.agentbox;
  projectCfg = cfg.project;
  gitCfg = projectCfg.source.git;
  isGit = projectCfg.source.type == "git";
in
{
  systemd.services.clone-host-project = lib.mkIf isGit {
    description = "Clone git repository for project";
    wantedBy = [ "multi-user.target" ];

    # Wait for network since we need to clone from remote
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = [ pkgs.coreutils pkgs.git pkgs.openssh ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Run as the dev user to use their SSH keys
      User = cfg.user.name;
      Group = "users";
    };

    script = ''
      set -e

      DEST_PATH="${projectCfg.destPath}"
      MARKER="${projectCfg.marker}"
      VALIDATE_MARKER="${if projectCfg.validateMarker then "true" else "false"}"
      REQUIRED="${if projectCfg.source.required then "true" else "false"}"
      REFRESH="${projectCfg.source.refresh}"

      GIT_URL="${if gitCfg.url != null then gitCfg.url else ""}"
      GIT_REF="${if gitCfg.ref != null then gitCfg.ref else ""}"
      GIT_SHALLOW="${if gitCfg.shallow then "true" else "false"}"
      GIT_DEPTH="${toString gitCfg.depth}"

      # Validate git URL is provided
      if [ -z "$GIT_URL" ]; then
        echo "Error: git URL is not configured (source.git.url)"
        if [ "$REQUIRED" = "true" ]; then
          exit 1
        fi
        exit 0
      fi

      # Check refresh policy - skip if destination exists and refresh is "if-missing"
      if [ "$REFRESH" = "if-missing" ] && [ -d "$DEST_PATH/.git" ]; then
        echo "Repository exists at $DEST_PATH and refresh=if-missing, skipping clone"
        exit 0
      fi

      # Remove existing directory if refresh=always
      if [ "$REFRESH" = "always" ] && [ -d "$DEST_PATH" ]; then
        echo "Removing existing directory for fresh clone..."
        rm -rf "$DEST_PATH"
      fi

      # Build clone options
      CLONE_OPTS=""
      if [ "$GIT_SHALLOW" = "true" ]; then
        CLONE_OPTS="--depth $GIT_DEPTH"
      fi

      # Clone repository
      echo "Cloning $GIT_URL to $DEST_PATH..."
      if git clone $CLONE_OPTS "$GIT_URL" "$DEST_PATH"; then
        echo "Successfully cloned repository"

        # Checkout specific ref if provided
        if [ -n "$GIT_REF" ]; then
          echo "Checking out ref: $GIT_REF"
          cd "$DEST_PATH"
          git checkout "$GIT_REF"
        fi

        # Validate marker if configured
        if [ "$VALIDATE_MARKER" = "true" ]; then
          if [ ! -f "$DEST_PATH/$MARKER" ]; then
            echo "Warning: Marker file '$MARKER' not found in cloned repository"
            if [ "$REQUIRED" = "true" ]; then
              echo "Error: Project source is required but marker validation failed"
              exit 1
            fi
          else
            echo "Marker file '$MARKER' found"
          fi
        fi
      else
        echo "Failed to clone repository"
        if [ "$REQUIRED" = "true" ]; then
          echo "Error: Project source is required but clone failed"
          exit 1
        fi
      fi
    '';
  };
}

