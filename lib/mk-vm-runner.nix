# Generate wrapper scripts for running the VM
{ pkgs
, vmDrv
, vmName ? "dev-vm"
, projectMarker ? "flake.nix"
, projectSourceType ? "mount"
, projectSourcePath ? null  # null means auto-detect
, projectDestPath ? "/home/dev/project"
, hostShares ? []
}:
let
  # Generate shell code to set up host shares
  shareSetupCode = builtins.concatStringsSep "\n" (map (share: ''
    if [ -d "$HOME/${share.hostPath}" ]; then
      echo "Sharing: $HOME/${share.hostPath} -> ${share.tag}"
      SHARE_ARGS="$SHARE_ARGS -virtfs local,path=$HOME/${share.hostPath},mount_tag=${share.tag},security_model=none,readonly=on"
    fi
  '') hostShares);

  # Function to auto-detect project directory by walking up to find marker
  autoDetectProjectCode = ''
    find_project_root() {
      local dir="$1"
      local marker="$2"

      while [ "$dir" != "/" ]; do
        if [ -f "$dir/$marker" ]; then
          echo "$dir"
          return 0
        fi
        dir="$(dirname "$dir")"
      done
      return 1
    }
  '';

  # Determine project directory based on configuration
  projectDirCode = if projectSourcePath != null then ''
    # Use explicit source path from configuration
    PROJECT_DIR="${projectSourcePath}"
    if [ ! -d "$PROJECT_DIR" ]; then
      echo "Error: Configured source path does not exist: $PROJECT_DIR"
      exit 1
    fi
  '' else ''
    # Auto-detect project directory by walking up to find marker
    START_DIR="$(pwd)"
    PROJECT_DIR=$(find_project_root "$START_DIR" "${projectMarker}")
    if [ -z "$PROJECT_DIR" ]; then
      echo "Warning: Could not find project directory with ${projectMarker}"
      echo "Searched from: $START_DIR"
      echo "Run from the project directory or set source.path in your configuration."
      PROJECT_DIR=""
    fi
  '';

  # Set up project share based on source type
  projectShareCode = if projectSourceType == "mount" then ''
    # Mount source type: share read-write via 9p virtfs
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
      echo "Sharing project (mount): $PROJECT_DIR -> ${projectDestPath}"
      SHARE_ARGS="$SHARE_ARGS -virtfs local,path=$PROJECT_DIR,mount_tag=host-project,security_model=mapped-xattr"
    fi
  '' else if projectSourceType == "copy" then ''
    # Copy source type: share read-only via 9p virtfs (VM will rsync to local disk)
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
      echo "Sharing project (copy): $PROJECT_DIR -> ${projectDestPath}"
      SHARE_ARGS="$SHARE_ARGS -virtfs local,path=$PROJECT_DIR,mount_tag=host-project-src,security_model=mapped-xattr,readonly=on"
    fi
  '' else ''
    # Git source type: no host share needed (VM will clone from URL)
    echo "Project source type: git (no host share needed)"
  '';

  # Common script logic shared between headless and GUI modes
  commonScript = ''
    # Pick a random SSH port in range 20000-30000
    SSH_PORT=$((20000 + RANDOM % 10000))

    SHARE_ARGS=""

    ${autoDetectProjectCode}

    ${projectDirCode}

    ${projectShareCode}

    # Set up host config shares
    ${shareSetupCode}

    # Add SSH port forwarding
    NET_ARGS="-netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22 -device virtio-net-pci,netdev=net0"

    # Save SSH port to a file for easy reference
    echo "$SSH_PORT" > /tmp/${vmName}-ssh-port
  '';

  # Headless mode banner
  headlessBanner = ''
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ${vmName}                                                 ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  SSH:  ssh dev@localhost -p $SSH_PORT                       ║"
    echo "║  Exit: Ctrl+A X                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Port saved to /tmp/${vmName}-ssh-port"
    echo ""
  '';
in
{
  headless = pkgs.writeShellScriptBin "run-${vmName}" ''
    ${commonScript}
    ${headlessBanner}
    exec ${vmDrv}/bin/run-*-vm -nographic $SHARE_ARGS $NET_ARGS "$@"
  '';

  gui = pkgs.writeShellScriptBin "run-${vmName}-gui" ''
    ${commonScript}
    echo "SSH: ssh dev@localhost -p $SSH_PORT"
    echo "Port saved to /tmp/${vmName}-ssh-port"
    echo ""
    exec ${vmDrv}/bin/run-*-vm $SHARE_ARGS $NET_ARGS "$@"
  '';
}

