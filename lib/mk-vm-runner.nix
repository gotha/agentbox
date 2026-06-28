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

  background = pkgs.writeShellScriptBin "run-${vmName}-headless" ''
    CONSOLE_LOG="/tmp/${vmName}-console.log"
    PID_FILE="/tmp/${vmName}.pid"
    PORT_FILE="/tmp/${vmName}-ssh-port"

    # If a VM with this name is already running, don't try to start another one
    # (QEMU would fail to lock the pidfile). Point the user at the running VM
    # instead, and leave its recorded SSH port untouched.
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
      echo "VM '${vmName}' is already running (PID $(cat "$PID_FILE"))." >&2
      if [ -s "$PORT_FILE" ]; then
        echo "Connect with: ssh dev@localhost -p $(cat "$PORT_FILE")" >&2
      fi
      echo "Stop it with: kill \$(cat $PID_FILE)" >&2
      exit 1
    fi

    # Remember the previously recorded port; commonScript overwrites PORT_FILE
    # with a fresh random port below, so we can restore it if the launch fails.
    PREV_PORT="$(cat "$PORT_FILE" 2>/dev/null || true)"

    ${commonScript}

    # Launch QEMU fully detached: no display, no monitor, serial captured to a
    # log file, and qemu daemonizes itself while recording its PID for control.
    if ! ${vmDrv}/bin/run-*-vm \
      -display none \
      -monitor none \
      -serial "file:$CONSOLE_LOG" \
      -pidfile "$PID_FILE" \
      -daemonize \
      $SHARE_ARGS $NET_ARGS "$@"; then
      # Launch failed (commonScript already clobbered PORT_FILE) — restore the
      # previous port so it keeps pointing at whatever VM is actually running.
      if [ -n "$PREV_PORT" ]; then echo "$PREV_PORT" > "$PORT_FILE"; fi
      echo "" >&2
      echo "Error: failed to start VM '${vmName}'." >&2
      echo "A VM with this name is probably already running." >&2
      if [ -n "$PREV_PORT" ]; then
        echo "Try connecting to the existing one: ssh dev@localhost -p $PREV_PORT" >&2
      fi
      echo "Find it with: pgrep -af '${vmName}'" >&2
      exit 1
    fi

    echo ""
    echo "VM '${vmName}' started in background."
    echo ""
    echo "  SSH:         ssh dev@localhost -p $SSH_PORT"
    echo "  Port file:   $PORT_FILE"
    echo "  Console log: $CONSOLE_LOG"
    echo "  Stop:        kill \$(cat $PID_FILE)"
    echo ""
  '';
}

