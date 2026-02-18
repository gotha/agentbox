# Project Source Setup

## Overview

This specification defines three different methods for exposing source code from the host to the guest VM. Each method serves different use cases and provides varying levels of isolation between the host and guest environments.

## Backward Compatibility

**There is no need for backward compatibility.** This is a new project and breaking changes are acceptable. The following breaking changes will be made:

- `mountPath` option → renamed to `destPath`
- `symlink` option → removed entirely

## Goals

- Provide flexibility in how source code is made available to the VM
- Support workflows that require isolation from host filesystem
- Enable reproducible environments via git-based source provisioning

## Design Decisions Summary

The following decisions were made through a Q&A refinement process:

| # | Decision | Choice |
|---|----------|--------|
| 1 | Source path configuration | Build-time (configured in Nix flake, not runtime detection) |
| 2 | Path required/optional | Optional - defaults to project marker auto-detection |
| 3 | Default path detection | Walk up from flake directory until finding marker file |
| 4 | Copy exclude patterns | Configurable with empty default (user must specify) |
| 5 | Git authentication | Via existing `hostShares` mechanism (share `~/.ssh`, `~/.gitconfig`) |
| 6 | Shallow clone | Configurable, default is **full clone** (`shallow = false`) |
| 7 | Persistence (copy/git) | Configurable via `refresh`, default `"if-missing"` (skip if exists) |
| 8 | Mount read/write mode | Always read-write (not configurable) |
| 9 | Error handling | Configurable via `required`, default `true` (fail to boot) |
| 10 | Marker validation | Configurable via `validateMarker`, default `true` |
| 11 | Git ref specification | Single `ref` option accepting branch, tag, or commit SHA |
| 12 | Default git ref | Repository's default branch (HEAD) when not specified |
| 13 | Option structure | Nested (`source.type`, `source.git`, `source.copy`, etc.) |
| 14 | Destination path naming | Rename `mountPath` to `destPath` |
| 15 | Backward compatibility | Not needed - breaking changes acceptable |
| 16 | Symlink option | Remove entirely |
| 17 | Copy tool | rsync (supports exclude patterns natively) |
| 18 | Exclude implementation | Via rsync `--exclude` patterns |
| 19 | Base packages | Always install `git` and `rsync` regardless of source type |

## Source Methods

### Method 1: Mount

**Type:** `mount`

Share the host directory directly with the guest via 9p virtfs. Changes made in the guest are immediately visible on the host and vice versa. The mount is always **read-write**.

**Use Cases:**
- Interactive development where you edit on host and run in guest
- Quick iteration without sync delays
- When you want changes persisted to host filesystem

**Configuration:**
```nix
agentbox.project = {
  source.type = "mount";
  source.path = "/home/user/myproject";  # Optional: defaults to auto-detect via marker
  destPath = "/home/dev/project";         # Where to mount in guest
  marker = "flake.nix";                   # File to identify project root
};
```

**Behavior:**
- Directory shared read-write via QEMU 9p virtfs
- If `source.path` not specified, walks up from flake directory to find project root using `marker`
- Validates presence of `marker` file (configurable via `validateMarker`)

---

### Method 2: Copy

**Type:** `copy`

Copy the source code from host to guest VM at boot time using **rsync**. The guest gets its own independent copy, so changes in the guest do not affect the original files on the host.

**Use Cases:**
- AI agents that may make destructive changes
- Testing potentially dangerous operations
- Sandboxed experimentation

**Configuration:**
```nix
agentbox.project = {
  source.type = "copy";
  source.path = "/home/user/myproject";   # Optional: defaults to auto-detect via marker
  source.copy.excludePatterns = [         # Optional: patterns to exclude (empty by default)
    ".git"
    "node_modules"
  ];
  source.refresh = "if-missing";          # Optional: "always" | "if-missing" (default: "if-missing")
  source.required = true;                 # Optional: fail boot if copy fails (default: true)
  destPath = "/home/dev/project";         # Destination in guest
};
```

**Behavior:**
- Source directory is shared read-only via 9p virtfs with a temporary tag
- On boot, a systemd service runs rsync to copy files to `destPath`
- If `refresh = "if-missing"` (default), skips copy if `destPath` already exists
- If `refresh = "always"`, re-copies on every boot
- Original files on host remain untouched regardless of guest changes

---

### Method 3: Git Clone

**Type:** `git`

Clone a git repository into the guest VM at boot time. Supports specifying branch, tag, or commit.

**Use Cases:**
- Reproducible environments from specific git refs
- CI/CD-like workflows
- Testing against specific branches or tags
- When source isn't available locally on host

**Configuration:**
```nix
agentbox.project = {
  source.type = "git";
  source.git = {
    url = "https://github.com/org/repo.git";  # Required: repository URL
    ref = "main";                              # Optional: branch, tag, or commit (default: repo's default branch)
    shallow = false;                           # Optional: shallow clone (default: false)
    depth = 1;                                 # Optional: clone depth if shallow (default: 1)
  };
  source.refresh = "if-missing";               # Optional: "always" | "if-missing" (default: "if-missing")
  source.required = true;                      # Optional: fail boot if clone fails (default: true)
  destPath = "/home/dev/project";              # Where to clone in guest
};
```

**Behavior:**
- On boot, a systemd service clones the repository to `destPath`
- If `ref` is specified, checks out that branch/tag/commit after clone
- If `ref` is not specified, uses repository's default branch
- Full clone by default (`shallow = false`)
- If `refresh = "if-missing"` (default), skips clone if `destPath` already exists
- Requires network access from guest VM

**Authentication:**
- Public repositories: no additional config needed
- Private repositories: use `agentbox.hostShares` to share `~/.ssh` or `~/.gitconfig` from host

---

## Configuration Schema

```nix
options.agentbox.project = {
  source = {
    type = mkOption {
      type = types.enum [ "mount" "copy" "git" ];
      default = "mount";
      description = "Method for providing source code to the VM";
    };

    path = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to source directory on host (for mount/copy types). If not specified, walks up from flake directory to find project root using marker.";
    };

    refresh = mkOption {
      type = types.enum [ "always" "if-missing" ];
      default = "if-missing";
      description = "When to refresh source (for copy/git types). 'always' = every boot, 'if-missing' = only if destPath doesn't exist";
    };

    required = mkOption {
      type = types.bool;
      default = true;
      description = "If true, VM fails to boot if source setup fails. If false, logs warning and continues.";
    };

    git = {
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Git repository URL";
      };

      ref = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Git ref to checkout (branch, tag, or commit). If not specified, uses repository's default branch.";
      };

      shallow = mkOption {
        type = types.bool;
        default = false;
        description = "Perform shallow clone";
      };

      depth = mkOption {
        type = types.int;
        default = 1;
        description = "Clone depth for shallow clones";
      };
    };

    copy = {
      excludePatterns = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Patterns to exclude when copying source (rsync --exclude format)";
      };
    };
  };

  destPath = mkOption {
    type = types.str;
    default = "/home/dev/project";
    description = "Destination path in the guest VM for the project source";
  };

  marker = mkOption {
    type = types.str;
    default = "flake.nix";
    description = "File that identifies the project root (used for auto-detection and validation)";
  };

  validateMarker = mkOption {
    type = types.bool;
    default = true;
    description = "If true, validates that the marker file exists in the source";
  };
};
```

## Base Packages

The following packages are **always** installed in the VM regardless of which source type is configured:
- `git` - required for git clone method, also useful for development
- `rsync` - required for copy method

This simplifies configuration and ensures tools are available if the user changes source types.

## Technical Implementation Details

### Path Auto-Detection Algorithm

When `source.path` is not specified for `mount` or `copy` types:

```bash
# Pseudo-code for path auto-detection
start_dir = directory containing the flake
current_dir = start_dir

while current_dir != "/":
  if file_exists(current_dir / marker):
    return current_dir
  current_dir = parent(current_dir)

# If marker not found, error or use start_dir based on validateMarker setting
```

### Mount Method Implementation

**Host side (`mk-vm-runner.nix`):**
```bash
# Share project directory via 9p virtfs
SHARE_ARGS="-virtfs local,path=$SOURCE_PATH,mount_tag=host-project,security_model=mapped-xattr"
```

**Guest side (`host-project-mount.nix`):**
```bash
# Systemd service mounts the 9p share
mount -t 9p -o trans=virtio,version=9p2000.L host-project $DEST_PATH
```

### Copy Method Implementation

**Host side (`mk-vm-runner.nix`):**
```bash
# Share project directory READ-ONLY via 9p virtfs
SHARE_ARGS="-virtfs local,path=$SOURCE_PATH,mount_tag=host-project-src,security_model=mapped-xattr,readonly=on"
```

**Guest side (`host-project-copy.nix`):**
```bash
# Mount read-only source to temporary location
mkdir -p /mnt/host-project-src
mount -t 9p -o trans=virtio,version=9p2000.L,ro host-project-src /mnt/host-project-src

# Check refresh policy
if [ "$REFRESH" = "if-missing" ] && [ -d "$DEST_PATH" ]; then
  echo "Destination exists, skipping copy"
  exit 0
fi

# rsync with exclude patterns
rsync -a --delete \
  ${EXCLUDE_PATTERNS:+$(printf -- '--exclude=%s ' $EXCLUDE_PATTERNS)} \
  /mnt/host-project-src/ $DEST_PATH/

# Cleanup
umount /mnt/host-project-src
```

### Git Method Implementation

**Guest side (`host-project-git.nix`):**
```bash
# Check refresh policy
if [ "$REFRESH" = "if-missing" ] && [ -d "$DEST_PATH/.git" ]; then
  echo "Repository exists, skipping clone"
  exit 0
fi

# Remove existing if refresh=always
if [ "$REFRESH" = "always" ] && [ -d "$DEST_PATH" ]; then
  rm -rf "$DEST_PATH"
fi

# Clone options
CLONE_OPTS=""
if [ "$SHALLOW" = "true" ]; then
  CLONE_OPTS="--depth $DEPTH"
fi

# Clone repository
git clone $CLONE_OPTS "$GIT_URL" "$DEST_PATH"

# Checkout specific ref if provided
if [ -n "$GIT_REF" ]; then
  cd "$DEST_PATH"
  git checkout "$GIT_REF"
fi
```

### Error Handling

When `required = true` (default):
- Systemd service is marked as `ConditionPathExists=` or fails with `exit 1`
- Boot process halts at the service failure
- User sees clear error message in boot logs

When `required = false`:
- Systemd service logs warning but exits with `exit 0`
- Boot continues normally
- User can manually fix the issue after login

### Marker Validation

When `validateMarker = true` (default):
- For `mount`/`copy`: Validates marker exists in `source.path` before mounting/copying
- For `git`: Validates marker exists in cloned repo after clone completes
- Validation failure respects `required` setting

When `validateMarker = false`:
- No validation performed
- Useful for projects without a standard marker file

## Implementation Plan

### Phase 1: Refactor Options
1. Add new option definitions in `modules/default.nix`
2. Update `config.nix` with new defaults
3. Remove `mountPath` (replaced by `destPath`)
4. Remove `symlink` option

### Phase 2: Implement Mount Method
1. Update `lib/mk-vm-runner.nix` to handle `source.type = "mount"`
2. Update `modules/services/host-project-mount.nix` with new options
3. Implement marker validation and auto-detection

### Phase 3: Implement Copy Method
1. Create `modules/services/host-project-copy.nix` systemd service
2. Modify `mk-vm-runner.nix` to share source read-only when `type = "copy"`
3. Implement rsync-based copy with exclude patterns
4. Handle `refresh` and `required` options

### Phase 4: Implement Git Method
1. Create `modules/services/host-project-git.nix` systemd service
2. Implement git clone logic with ref support
3. Handle `refresh` and `required` options
4. No changes needed to `mk-vm-runner.nix` (no host share required)

### Phase 5: Documentation
1. Update README with new configuration options
2. Add examples for each method

## Files to Modify/Create

| File | Action | Description |
|------|--------|-------------|
| `modules/default.nix` | Modify | Add new option definitions, remove old options |
| `config.nix` | Modify | Update default values |
| `lib/mk-vm-runner.nix` | Modify | Handle different source types, marker auto-detection |
| `modules/packages.nix` | Modify | Add `git` and `rsync` to base packages |
| `modules/services/host-project-mount.nix` | Modify | Update for new options |
| `modules/services/host-project-copy.nix` | Create | Copy service implementation |
| `modules/services/host-project-git.nix` | Create | Git clone service implementation |
| `modules/services/default.nix` | Modify | Import new service modules |
| `README.md` | Modify | Document new options |

## Example Configurations

### Example 1: Mount (Default Behavior)

Minimal configuration - uses auto-detection:

```nix
{
  agentbox.project = {
    # source.type defaults to "mount"
    # source.path auto-detected via marker
    # destPath defaults to "/home/dev/project"
    # marker defaults to "flake.nix"
  };
}
```

### Example 2: Mount with Explicit Path

```nix
{
  agentbox.project = {
    source.type = "mount";
    source.path = "/home/user/my-project";
    destPath = "/home/dev/code";
    marker = "go.mod";
  };
}
```

### Example 3: Copy for AI Agent Sandbox

```nix
{
  agentbox.project = {
    source.type = "copy";
    source.path = "/home/user/my-project";
    source.copy.excludePatterns = [
      ".git"
      "node_modules"
      ".direnv"
      "target"
      "__pycache__"
    ];
    source.refresh = "always";  # Fresh copy every boot
    destPath = "/home/dev/project";
  };
}
```

### Example 4: Git Clone Public Repository

```nix
{
  agentbox.project = {
    source.type = "git";
    source.git = {
      url = "https://github.com/org/repo.git";
      ref = "v2.0.0";  # Specific tag
    };
    destPath = "/home/dev/project";
  };
}
```

### Example 5: Git Clone Private Repository

```nix
{
  agentbox.project = {
    source.type = "git";
    source.git = {
      url = "git@github.com:org/private-repo.git";
      ref = "develop";
    };
    source.required = true;
    destPath = "/home/dev/project";
  };

  # Share SSH keys for authentication
  agentbox.hostShares = [
    { hostPath = "~/.ssh"; guestPath = "/home/dev/.ssh"; }
  ];
}
```

### Example 6: Git Clone with Shallow Clone

```nix
{
  agentbox.project = {
    source.type = "git";
    source.git = {
      url = "https://github.com/large/monorepo.git";
      shallow = true;
      depth = 1;
    };
    destPath = "/home/dev/project";
  };
}
```

### Example 7: Non-Required Source (Optional Project)

```nix
{
  agentbox.project = {
    source.type = "git";
    source.git.url = "https://github.com/org/repo.git";
    source.required = false;  # Boot even if clone fails
    validateMarker = false;   # Don't require marker file
    destPath = "/home/dev/project";
  };
}
```

## Consumer Flake Examples

These examples show how a project would use agentbox in their own `flake.nix` to set up a development VM.

### Consumer Example 1: Mount Source (Default)

A project that wants to mount its source code for interactive development:

```nix
# myproject/devenv/flake.nix
{
  description = "Development VM for myproject";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";  # or path to agentbox
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      # VM packages
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "myproject-dev";
        projectMarker = "go.mod";  # Project uses Go
        extraConfig = {
          agentbox.project = {
            source.type = "mount";
            # source.path not specified - auto-detects via marker
            destPath = "/home/dev/myproject";
            marker = "go.mod";
          };
        };
      };
    };
}
```

**Usage:**
```bash
cd myproject/devenv
nix run .#vm      # Headless VM
nix run .#vm-gui  # GUI VM
# Source at /home/dev/myproject is live-synced with host
```

---

### Consumer Example 2: Mount with Explicit Path

When the flake is not in the project directory:

```nix
# ~/vms/golang-dev/flake.nix
{
  description = "Generic Go development VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "golang-dev";
        projectMarker = "go.mod";
        extraConfig = {
          agentbox.project = {
            source.type = "mount";
            source.path = "/home/user/projects/my-go-app";  # Explicit path
            destPath = "/home/dev/project";
            marker = "go.mod";
          };

          # Additional Go tooling
          agentbox.packages = [ "go" "gopls" "delve" ];
        };
      };
    };
}
```

---

### Consumer Example 3: Copy Source for AI Agent

A project that wants to give an AI agent a sandboxed copy:

```nix
# myproject/devenv/flake.nix
{
  description = "AI Agent sandbox for myproject";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "myproject-agent";
        projectMarker = "flake.nix";
        extraConfig = {
          agentbox.project = {
            source.type = "copy";
            # source.path auto-detected via marker
            source.copy.excludePatterns = [
              ".git"
              "node_modules"
              ".direnv"
              "result"
              "*.log"
            ];
            source.refresh = "always";  # Fresh copy every boot
            destPath = "/home/dev/project";
          };

          # Enable AI coding assistant
          agentbox.auggie.enable = true;
        };
      };
    };
}
```

**Usage:**
```bash
cd myproject/devenv
nix run .#vm
# AI agent can freely modify /home/dev/project without affecting host files
```

---

### Consumer Example 4: Copy with Persistence

Copy source once, keep changes between reboots:

```nix
# myproject/devenv/flake.nix
{
  description = "Persistent sandbox for myproject";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "myproject-sandbox";
        projectMarker = "package.json";
        extraConfig = {
          agentbox.project = {
            source.type = "copy";
            source.copy.excludePatterns = [ "node_modules" ".git" ];
            source.refresh = "if-missing";  # Only copy if not exists (default)
            destPath = "/home/dev/project";
            marker = "package.json";
          };

          # Persistent VM disk
          agentbox.vm.diskSize = "20G";
        };
      };
    };
}
```

**Usage:**
```bash
nix run .#vm
# First boot: copies source to VM
# Subsequent boots: uses existing copy, changes preserved
```

---

### Consumer Example 5: Git Clone Public Repository

Clone a public repository at boot:

```nix
# ~/vms/oss-contrib/flake.nix
{
  description = "VM for contributing to open source project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "nixpkgs-contrib";
        projectMarker = "flake.nix";
        extraConfig = {
          agentbox.project = {
            source.type = "git";
            source.git = {
              url = "https://github.com/NixOS/nixpkgs.git";
              ref = "nixos-unstable";
              shallow = true;   # Large repo, use shallow clone
              depth = 1;
            };
            source.refresh = "if-missing";
            destPath = "/home/dev/nixpkgs";
            marker = "flake.nix";
          };
        };
      };
    };
}
```

**Usage:**
```bash
nix run .#vm
# Clones nixpkgs at boot (or uses existing if already cloned)
```

---

### Consumer Example 6: Git Clone Private Repository

Clone a private repository with SSH authentication:

```nix
# ~/vms/work-project/flake.nix
{
  description = "VM for private work project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "work-project";
        projectMarker = "Cargo.toml";
        extraConfig = {
          agentbox.project = {
            source.type = "git";
            source.git = {
              url = "git@github.com:mycompany/private-repo.git";
              ref = "develop";
            };
            source.refresh = "if-missing";
            source.required = true;  # Fail boot if clone fails
            destPath = "/home/dev/project";
            marker = "Cargo.toml";
          };

          # Share SSH keys for git authentication
          agentbox.hostShares = [
            {
              hostPath = "~/.ssh";
              guestPath = "/home/dev/.ssh";
            }
            {
              hostPath = "~/.gitconfig";
              guestPath = "/home/dev/.gitconfig";
            }
          ];

          # Rust development tools
          agentbox.packages = [ "rustc" "cargo" "rust-analyzer" ];
        };
      };
    };
}
```

**Usage:**
```bash
nix run .#vm
# Uses host's SSH keys to clone private repo
```

---

### Consumer Example 7: Git Clone Specific Commit

Clone and checkout a specific commit for reproducibility:

```nix
# ~/vms/repro-build/flake.nix
{
  description = "Reproducible build environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "repro-build";
        projectMarker = "flake.nix";
        extraConfig = {
          agentbox.project = {
            source.type = "git";
            source.git = {
              url = "https://github.com/org/project.git";
              ref = "a1b2c3d4e5f6";  # Specific commit SHA
            };
            source.refresh = "always";  # Always checkout exact commit
            destPath = "/home/dev/project";
            validateMarker = false;  # Don't require marker at this commit
          };
        };
      };
    };
}
```

---

### Consumer Example 8: Multiple Projects

Mount main project, clone dependency:

```nix
# myproject/devenv/flake.nix
{
  description = "VM with main project and cloned dependency";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "multi-project";
        projectMarker = "flake.nix";
        extraConfig = {
          # Primary project (mounted from host)
          agentbox.project = {
            source.type = "mount";
            destPath = "/home/dev/main-project";
          };

          # Note: For additional projects, use systemd services or
          # configure in VM's shell init. The agentbox.project option
          # handles the primary project only.
        };
      };
    };
}
```

---

### Consumer Example 9: Minimal Configuration

Rely entirely on defaults:

```nix
# myproject/devenv/flake.nix
{
  description = "Minimal dev VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentbox.url = "github:user/agentbox";
  };

  outputs = { self, nixpkgs, agentbox }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = agentbox.lib.mkVmPackages {
        inherit system;
        vmName = "dev";
        projectMarker = "flake.nix";
        # extraConfig not needed - all defaults work:
        # - source.type = "mount"
        # - source.path = auto-detect via marker
        # - destPath = "/home/dev/project"
        # - marker = "flake.nix"
      };
    };
}
```

**Directory structure:**
```
myproject/
├── flake.nix          # Project's main flake (marker file)
├── src/
└── devenv/
    └── flake.nix      # VM configuration (this file)
```

**Usage:**
```bash
cd myproject/devenv
nix run .#vm
# Auto-detects myproject/ as root, mounts to /home/dev/project
```
