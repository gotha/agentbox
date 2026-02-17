# Generate wrapper scripts for running the VM
{ pkgs
, vmDrv
, vmName ? "dev-vm"
, projectMarker ? "go.mod"
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

  # Common script logic shared between headless and GUI modes
  commonScript = ''
    # Pick a random SSH port in range 20000-30000
    SSH_PORT=$((20000 + RANDOM % 10000))

    SHARE_ARGS=""

    # Share the project directory - use PWD since $0 points to nix store
    PROJECT_DIR="$(pwd)"
    # If we're in devenv, go up one level
    if [ "$(basename "$PROJECT_DIR")" = "devenv" ]; then
      PROJECT_DIR="$(dirname "$PROJECT_DIR")"
    fi
    if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/${projectMarker}" ]; then
      echo "Sharing project: $PROJECT_DIR -> /home/dev/project"
      SHARE_ARGS="-virtfs local,path=$PROJECT_DIR,mount_tag=host-project,security_model=mapped-xattr"
    else
      echo "Warning: Could not find project directory with ${projectMarker} in $PROJECT_DIR"
      echo "Run from the project root or devenv directory to enable project mounting."
    fi

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

