---
name: agentbox
description: Create and run isolated NixOS VM development environments for safe code execution, testing, and sandboxed AI agent workflows
version: 1.0.0
author: gotha
category: Development
tags:
  - vm
  - sandbox
  - nix
  - nixos
  - isolation
  - development
  - testing
  - docker
platforms:
  - claude-code
  - cursor
  - augment
  - codex
  - opencode
  - cline
  - roo
  - windsurf
  - github-copilot
---

# Agentbox

Create isolated NixOS VMs for safe code execution and development. Use this skill when you need to execute code in a sandboxed environment, run tests safely, or work on projects without affecting the host system.

## When to Use

- Execute code that might be destructive or have side effects
- Run tests in a clean, reproducible environment
- Work on projects requiring specific dependencies without polluting the host
- Any task where isolation from the host system is beneficial

## When NOT to Use

- Tasks requiring GUI applications (VMs are headless)
- Tasks requiring direct GPU or hardware access
- Production deployments

## Prerequisites

Before using agentbox, verify these prerequisites are met:

### 1. Nix Package Manager

Check if Nix is installed:
```bash
nix --version
```

If not installed, guide the user to install via:
- https://nixos.org/download.html (official)
- https://determinate.systems/nix-installer (recommended for macOS)

### 2. Flakes Enabled

Check if flakes are enabled:
```bash
nix flake --help
```

If not enabled, add to `~/.config/nix/nix.conf`:
```
experimental-features = nix-command flakes
```

### 3. Linux Builder (macOS only)

On macOS, a Linux builder is required. Check with:
```bash
nix build --system x86_64-linux nixpkgs#hello --dry-run
```

If it fails, the user needs either:
- nix-darwin with linux-builder enabled
- Determinate Nix with linux-builder

**Stop and wait for user confirmation if prerequisites are missing.**

## Project Analysis

Before creating a VM, analyze the project:

### 1. Check for Existing Agentbox Config

```bash
ls -la .agentbox/flake.nix 2>/dev/null || echo "No existing config"
```

### 2. Determine Source Type

```bash
# Check for git remote
git remote -v 2>/dev/null
```

**Decision logic:**
- Has git remote → Use `source.type = "git"` with SSH URL
- Has .git but no remote → Use `source.type = "copy"`
- User explicitly requests live sync → Use `source.type = "mount"`
- No git at all → Use `source.type = "copy"`

### 3. Detect Required Packages

Scan project files and add corresponding packages:

| File | Packages |
|------|----------|
| `package.json` | `nodejs` + `npm`/`yarn`/`pnpm` |
| `go.mod` | `go gopls` |
| `Cargo.toml` | `rustc cargo rust-analyzer` |
| `requirements.txt` / `pyproject.toml` | `python3 pip` |
| `Gemfile` | `ruby bundler` |
| `Makefile` | `gnumake` |
| `Dockerfile` / `docker-compose.yml` | Enable Docker support |

### 4. Get Project Name

```bash
basename "$(pwd)"
```

Use this for VM hostname: `{project-name}-vm`

## Creating the Flake Configuration

### Default Location

Create `.agentbox/flake.nix` unless merging with an existing root flake is more appropriate.

### Flake Template

```nix
{
  description = "Agentbox VM for {project-name}";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    agentbox.url = "github:gotha/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in {
      nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
        name = "vm-${hostSystem}";
        value = agentbox.lib.mkDevVm {
          inherit hostSystem;
          extraConfig = {
            agentbox.vm.hostname = "{project-name}-vm";

            # Project source - adjust based on analysis
            agentbox.project = {
              source.type = "git";  # or "copy" or "mount"
              source.git = {
                url = "git@github.com:user/repo.git";
                ref = "main";
              };
              destPath = "/home/dev/project";
              marker = "flake.nix";  # or package.json, go.mod, etc.
            };

            # Always share SSH and git config for git source type
            agentbox.hostShares = [
              {
                tag = "ssh-keys";
                hostPath = ".ssh";
                dest = ".ssh";
                mode = "700";
                fileOverrides = [ "id_ed25519:600" "id_rsa:600" ];
              }
              {
                tag = "gitconfig";
                hostPath = ".gitconfig";
                dest = ".gitconfig";
              }
            ];

            # Enable your AI tool (choose one based on which agent is running)
            agentbox.auggie.enable = true;
            agentbox.auggie.syncConfigFromHost = true;
            # OR: agentbox.cursor.enable = true;
            # OR: agentbox.codex.enable = true;
            # OR: agentbox.claudecode.enable = true;
            # OR: agentbox.crush.enable = true;

            # Auto-detected packages (example)
            agentbox.packages.extra = with nixpkgs.legacyPackages.x86_64-linux; [
              # Add detected packages here
            ];

            # Docker support (if Dockerfile detected)
            # agentbox.docker.enable = true;
          };
        };
      }) allSystems);

      apps = agentbox.lib.mkVmApps {
        inherit (self) nixosConfigurations;
      };
    };
}
```

## Starting the VM

### 1. Build and Run

```bash
cd .agentbox  # or project root if merged
nix run .#vm
```

The VM starts in headless mode. Note the SSH port displayed in the banner.

### 2. Wait for VM Ready

Poll until SSH is available:

```bash
PORT=$(cat /tmp/{project-name}-vm-ssh-port)
until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null dev@localhost -p $PORT true 2>/dev/null; do
  sleep 2
done
```

### 3. Check for Running VM

Before starting a new VM, check if one is already running:

```bash
if [ -f /tmp/{project-name}-vm-ssh-port ]; then
  PORT=$(cat /tmp/{project-name}-vm-ssh-port)
  if ssh -o ConnectTimeout=2 dev@localhost -p $PORT true 2>/dev/null; then
    # VM is running - ask user: "A VM is already running. Reuse it or start fresh?"
  fi
fi
```

## Working in the VM

### Simple Commands (via SSH)

```bash
PORT=$(cat /tmp/{project-name}-vm-ssh-port)
ssh dev@localhost -p $PORT "cd /home/dev/project && make test"
```

### Complex Tasks

For complex, multi-step work, use the AI tool running inside the VM. The tool is pre-installed and configured with credentials from the host.

### Port Forwarding

To access services running in the VM (web servers, databases), use SSH tunneling:

```bash
# Forward local port 3000 to VM port 3000
ssh -L 3000:localhost:3000 dev@localhost -p $PORT -N &
```

### Getting Changes Back

For `git` source type, commit and push from inside the VM:

```bash
ssh dev@localhost -p $PORT "cd /home/dev/project && git add -A && git commit -m 'Changes from VM' && git push"
```

## Configuration Evolution

As the project evolves, update the flake configuration:

1. **New dependencies detected** → Add to `agentbox.packages.extra`
2. **Docker now needed** → Add `agentbox.docker.enable = true`
3. **New git remote** → Consider switching from `copy` to `git` source

After updating the flake, inform the user:
> "I've updated `.agentbox/flake.nix` to add [packages/features]. The VM needs to be rebuilt to apply changes. Would you like to restart the VM now?"

## Error Handling

When errors occur in the VM:

1. **Missing package** → Add to flake, suggest rebuild
2. **Permission denied** → Check SSH key sharing, file permissions
3. **Build failure** → Show error output, suggest fixes if obvious
4. **Network issues** → Verify VM has internet access

If the fix isn't obvious, escalate to the user with full error context.

## Cleanup

### Remove Agentbox Configuration

```bash
rm -rf .agentbox/
```

### Clean Nix Store

```bash
nix-collect-garbage -d
```

### Remove VM Disk Images

VM disk images are stored in `/tmp` and cleaned on reboot, or manually:

```bash
rm -f /tmp/nixos-*.qcow2
```

## Reference

For complete examples, see:
- `examples/minimal-auggie-mount` - Basic VM with Augment CLI
- `examples/minimal-cursor-mount` - Basic VM with Cursor CLI
- `examples/custom-tools-git-clone` - Full-featured VM with git source
- `examples/custom-tools-dotfiles-git-clone` - VM with dotfiles and home-manager

Full documentation: https://github.com/gotha/agentbox
