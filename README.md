# Agentbox

A NixOS-based virtual machine for providing safe, isolated development environments for AI agents.

## Overview

Agentbox creates reproducible, sandboxed Linux VMs where AI coding agents can safely execute code, run tests, and interact with development tools without affecting the host system.

## Features

- **Isolated execution** - Agents run in a fully sandboxed NixOS VM
- **Host file sharing** - Securely share project files and configurations via 9p virtfs
- **Reproducible environments** - Declarative Nix configuration ensures consistency
- **Customizable** - Override any option to match your project's needs
- **Cross-platform** - Works on macOS (Apple Silicon & Intel) and Linux

## Prerequisites

### Linux

No additional setup required. Just ensure you have Nix with flakes enabled.

### macOS

Building Linux VMs on macOS requires a Linux builder. You have two options:

1. [nix-darwin](https://github.com/nix-darwin/nix-darwin) with [linux-builder](https://nix-darwin.github.io/nix-darwin/manual/#opt-nix.linux-builder.enable) based on QEMU

2. [Determinate Nix with linux-builder](https://determinate.systems/blog/changelog-determinate-nix-384/) - uses Apple's virtualization framework (at the time of writing this, it is not a publicly available feature)


## Quick Start

```bash
# Clone and run
git clone https://github.com/gotha/agentbox
cd agentbox
nix run .#vm
```

## Usage as a Flake Input

Import agentbox into your own flake to create project-specific VMs:

```nix
{
  description = "My project development VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    agentbox.url = "github:gotha/agentbox";
  };

  outputs = { self, nixpkgs, agentbox, ... }:
    let
      # Map host systems to VM guest systems
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
    in
    {
      # Create VM configurations for each supported host system
      nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
        name = "vm-${hostSystem}";
        value = agentbox.lib.mkDevVm {
          inherit hostSystem;
          extraConfig = {
            # Customize your VM
            agentbox.vm.hostname = "my-project-vm";
            agentbox.vm.memorySize = 8192;  # 8GB RAM
            agentbox.vm.cores = 4;

            # Open ports for your services
            agentbox.networking.ports = [ 22 3000 8080 ];

            # Configure project mounting
            agentbox.project = {
              mountPath = "/home/dev/project";
              marker = "package.json";  # File that identifies project root
              symlink = "/home/dev/my-project";
            };

            # Add project-specific packages
            agentbox.packages.extra = with nixpkgs.legacyPackages.${
              if hostSystem == "aarch64-darwin" then "aarch64-linux"
              else if hostSystem == "x86_64-darwin" then "x86_64-linux"
              else hostSystem
            }; [
              nodejs_22
              yarn
            ];

            # Set environment variables
            agentbox.environment.variables = {
              NODE_ENV = "development";
              API_URL = "http://localhost:8080";
            };
          };
        };
      }) systems);
    };
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `agentbox.vm.hostname` | string | `"dev-vm"` | VM hostname |
| `agentbox.vm.cores` | int | `4` | Number of CPU cores |
| `agentbox.vm.memorySize` | int | `8192` | RAM in megabytes |
| `agentbox.vm.diskSize` | int | `50000` | Disk size in megabytes |
| `agentbox.user.name` | string | `"dev"` | Primary user name |
| `agentbox.networking.ports` | list of int | `[22]` | TCP ports to open |
| `agentbox.project.mountPath` | string | `"/home/dev/project"` | Where to mount host project |
| `agentbox.project.marker` | string | `"flake.nix"` | File that identifies project root |
| `agentbox.packages.extra` | list of package | `[]` | Additional packages to install |
| `agentbox.environment.variables` | attrs of string | `{}` | Environment variables |
| `agentbox.hostShares` | list of hostShare | `[]` | Host directories to sync into VM |
| `agentbox.docker.enable` | bool | `false` | Enable Docker daemon and packages |
| `agentbox.docker.syncConfigFromHost` | bool | `false` | Copy `~/.docker` from host to guest |
| `agentbox.auggie.enable` | bool | `false` | Enable Auggie (Augment Code CLI) |
| `agentbox.auggie.syncConfigFromHost` | bool | `false` | Copy `~/.augment` from host to guest |

## Docker

Docker is disabled by default. To enable it:

```nix
extraConfig = {
  agentbox.docker.enable = true;

  # Optionally sync Docker config (credentials, settings) from host
  agentbox.docker.syncConfigFromHost = true;
};
```

When enabled, this installs the Docker daemon, `docker` and `docker-compose` CLI tools, and adds the user to the `docker` group.

## Auggie (Augment Code CLI)

[Auggie](https://docs.augmentcode.com/cli/overview) is the Augment Code CLI tool for AI-assisted development. It is disabled by default. To enable it:

```nix
extraConfig = {
  agentbox.auggie.enable = true;

  # Optionally sync Augment config (credentials, settings) from host
  agentbox.auggie.syncConfigFromHost = true;
};
```

When enabled, this installs the `auggie` CLI tool from [gotha/nixpkgs](https://github.com/gotha/nixpkgs).

If `syncConfigFromHost` is enabled, the `~/.augment` directory from your host machine will be copied into the VM on boot, allowing the agent to use your Augment credentials.

## Host Shares

Share host directories (like dotfiles) with the VM:

```nix
agentbox.hostShares = [
  {
    tag = "host-config";      # 9p mount tag
    hostPath = ".config";     # Path relative to $HOME on host
    dest = ".config";         # Path relative to user home in VM
    mode = "700";             # Directory permissions
    fileOverrides = [ "secrets.json:600" ];  # Per-file permissions
  }
];
```

## License

BSD 3-Clause License. See [LICENSE.txt](LICENSE.txt) for details.
