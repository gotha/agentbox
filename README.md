# Agentbox

A NixOS-based virtual machine for providing safe, isolated development environments for AI agents.

## Overview

Agentbox creates reproducible, sandboxed Linux VMs where AI coding agents can safely execute code, run tests, and interact with development tools without affecting the host system.

## Features

- **Isolated execution** - Agents run in a fully sandboxed NixOS VM
- **Flexible project sources** - Mount from host, copy for isolation, or clone from git
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

Import agentbox into your own flake to create project-specific VMs. See the [examples](./examples) folder for complete configurations:

- **[minimal-auggie-mount](./examples/minimal-auggie-mount)** - Minimal VM with Auggie CLI and mounted project source
- **[minimal-cursor-mount](./examples/minimal-cursor-mount)** - Minimal VM with Cursor CLI and mounted project source
- **[custom-tools-git-clone](./examples/custom-tools-git-clone)** - Full-featured Go project VM with git source, SSH keys, Docker, and custom packages

### Running Your VM

After creating your `flake.nix`, run the VM with:

```bash
# Run VM in headless mode (recommended)
nix run .#vm
```

The default credentials are:
- **Username:** `dev`
- **Password:** empty

## Configuration Options

### VM Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `agentbox.vm.hostname` | string | `"dev-vm"` | VM hostname |
| `agentbox.vm.cores` | int | `4` | Number of CPU cores |
| `agentbox.vm.memorySize` | int | `8192` | RAM in megabytes |
| `agentbox.vm.diskSize` | int | `50000` | Disk size in megabytes |
| `agentbox.user.name` | string | `"dev"` | Primary user name |
| `agentbox.networking.ports` | list of int | `[22]` | TCP ports to open |
| `agentbox.packages.extra` | list of package | `[]` | Additional packages to install |
| `agentbox.environment.variables` | attrs of string | `{}` | Environment variables |
| `agentbox.hostShares` | list of hostShare | `[]` | Host directories to sync into VM |

### Project Source Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `agentbox.project.source.type` | enum | `"mount"` | Source type: `"mount"`, `"copy"`, or `"git"` |
| `agentbox.project.source.path` | string or null | `null` | Host path for mount/copy (auto-detects via marker if null) |
| `agentbox.project.source.refresh` | enum | `"if-missing"` | Refresh policy: `"always"` or `"if-missing"` (copy/git only) |
| `agentbox.project.source.required` | bool | `true` | Fail boot if source setup fails |
| `agentbox.project.source.git.url` | string or null | `null` | Git repository URL (required for git type) |
| `agentbox.project.source.git.ref` | string or null | `null` | Git ref to checkout (uses default branch if null) |
| `agentbox.project.source.git.shallow` | bool | `false` | Use shallow clone |
| `agentbox.project.source.git.depth` | int | `1` | Clone depth (when shallow is true) |
| `agentbox.project.source.copy.excludePatterns` | list of string | `[]` | Patterns to exclude from rsync copy |
| `agentbox.project.destPath` | string | `"/home/dev/project"` | Destination path in VM |
| `agentbox.project.marker` | string | `"flake.nix"` | File that identifies project root |
| `agentbox.project.validateMarker` | bool | `true` | Validate marker file exists after setup |

### Tool Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `agentbox.docker.enable` | bool | `false` | Enable Docker daemon and packages |
| `agentbox.docker.syncConfigFromHost` | bool | `false` | Copy `~/.docker` from host to guest |
| `agentbox.auggie.enable` | bool | `false` | Enable Auggie (Augment Code CLI) |
| `agentbox.auggie.syncConfigFromHost` | bool | `false` | Copy `~/.augment` from host to guest |
| `agentbox.cursor.enable` | bool | `false` | Enable Cursor CLI |
| `agentbox.cursor.syncConfigFromHost` | bool | `false` | Copy `~/.cursor` from host to guest |

## Project Source

Agentbox supports three methods to provide project source code to the VM:

### Mount (Default)

Mounts the host project directory directly into the VM via 9p virtfs. Changes in the VM are immediately reflected on the host (read-write).

```nix
agentbox.project = {
  source.type = "mount";
  # source.path is auto-detected by walking up to find marker file
  destPath = "/home/dev/project";
  marker = "flake.nix";
};
```

**Use case:** Interactive development where you want changes to persist to the host.

### Copy

Copies the project from host to VM using rsync at boot time. The VM has its own isolated copy (changes don't affect host).

```nix
agentbox.project = {
  source.type = "copy";
  source.refresh = "always";  # or "if-missing" to persist changes across reboots
  source.copy.excludePatterns = [ ".git" "node_modules" "target" ];
  destPath = "/home/dev/project";
};
```

**Use case:** AI agent sandboxes where you want isolation from the host filesystem.

### Git

Clones a git repository directly into the VM at boot time. Supports private repos via SSH keys shared through `hostShares`.

```nix
agentbox.project = {
  source.type = "git";
  source.git.url = "https://github.com/user/repo.git";
  source.git.ref = "main";  # optional: branch, tag, or commit
  source.git.shallow = true;  # optional: shallow clone
  destPath = "/home/dev/project";
};
```

For private repositories, share SSH keys:

```nix
agentbox.hostShares = [{
  tag = "ssh-keys";
  hostPath = ".ssh";
  dest = ".ssh";
  mode = "700";
  fileOverrides = [ "id_ed25519:600" "id_rsa:600" ];
}];

agentbox.project = {
  source.type = "git";
  source.git.url = "git@github.com:user/private-repo.git";
};
```

**Use case:** CI/CD environments, reproducible builds, or when you don't have the project locally.

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

## Cursor CLI

[Cursor](https://www.cursor.com/) CLI for AI-assisted development. It is disabled by default. To enable it:

```nix
extraConfig = {
  agentbox.cursor.enable = true;

  # Optionally sync Cursor config from host
  agentbox.cursor.syncConfigFromHost = true;
};
```

When enabled, this installs the `cursor-cli` from nixpkgs.

If `syncConfigFromHost` is enabled, the `~/.cursor` directory from your host machine will be copied into the VM on boot.

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

## Development

### Running Tests

Agentbox uses the NixOS VM testing framework for end-to-end tests. Tests boot actual VMs and verify functionality.

```bash
# Run all tests
nix flake check

# Run a specific test with build logs
nix build .#checks.x86_64-linux.boot --print-build-logs

# Available tests:
#   boot          - Basic VM boot tests (B1-B5)
#   project-mount - Mount source type tests (M1-M6)
#   project-copy  - Copy source type tests (C1-C6)
#   project-git   - Git source type tests (G1-G7)
#   host-shares   - Host shares sync tests (H1-H4)
#   tools-docker  - Docker integration tests (D1-D4)
```

### Debugging Tests

For interactive debugging, you can run the test driver manually:

```bash
# Build the interactive test driver
nix build .#checks.x86_64-linux.boot.driverInteractive

# Run the driver
./result/bin/nixos-test-driver

# In the Python REPL:
>>> start_all()           # Start the VM
>>> machine.shell_interact()  # Get an interactive shell
>>> machine.succeed("id dev")  # Run commands
>>> machine.screenshot("debug")  # Take a screenshot
```

### Adding New Tests

Tests are located in `tests/`. Each test file follows this pattern:

```nix
# tests/my-feature.nix
{ pkgs, self }:

pkgs.nixosTest {
  name = "agentbox-my-feature";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];
    # Configure the VM...
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    # Add assertions...
  '';
}
```

Then add the test to `tests/default.nix` and update `flake.nix` if needed.

## License

BSD 3-Clause License. See [LICENSE.txt](LICENSE.txt) for details.
