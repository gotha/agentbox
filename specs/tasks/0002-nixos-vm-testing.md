# NixOS VM Testing Framework

## Overview

This specification defines the requirements and implementation plan for end-to-end testing of agentbox using the NixOS VM testing framework. The goal is to ensure that all VM functionality works correctly, including boot services, project source methods, and tool configurations.

## Goals

- Verify that VMs boot successfully with different configurations
- Test all three project source methods (mount, copy, git)
- Ensure boot-time services complete successfully
- Validate that tools (docker, auggie, cursor) work when enabled
- Provide fast feedback during development
- Enable CI/CD integration

## Non-Goals

- Unit testing of individual Nix expressions (covered by `nix flake check`)
- Performance benchmarking
- Security auditing
- Testing on all host platforms (tests run on Linux only)

## Testing Framework Requirements

### R1: Use NixOS VM Testing Framework

Tests MUST use the built-in NixOS VM testing framework (`pkgs.nixosTest`).

**Rationale:**
- Native to NixOS, well-maintained by nixpkgs community
- Supports testing boot-time services
- Can simulate multi-VM scenarios if needed in the future
- Built-in helpers for common assertions
- Automatic screenshot capture on failure
- Declarative test definitions in Nix

### R2: Test Isolation

Each test MUST be independent and isolated:
- Tests must not depend on state from other tests
- Each test should create its own VM configuration
- Tests should clean up any external resources they create

### R3: Test Organization

Tests MUST be organized by feature area:

```
devenv/
├── tests/
│   ├── default.nix           # Main entry point, exports all tests
│   ├── lib.nix               # Shared test utilities and helpers
│   ├── boot.nix              # Basic VM boot tests
│   ├── project-mount.nix     # Mount source type tests
│   ├── project-copy.nix      # Copy source type tests
│   ├── project-git.nix       # Git source type tests
│   ├── host-shares.nix       # Host shares sync tests
│   ├── tools-docker.nix      # Docker integration tests
│   ├── tools-auggie.nix      # Auggie CLI tests (if possible)
│   └── tools-cursor.nix      # Cursor CLI tests (if possible)
```

### R4: Test Naming Convention

Tests MUST follow a consistent naming pattern:

- Test files: `<feature-area>.nix`
- Test names: `agentbox-<feature>-<scenario>`
- Example: `agentbox-project-mount-basic`, `agentbox-project-copy-with-excludes`

### R5: Flake Integration

Tests MUST be exposed via the flake:

```nix
# In flake.nix outputs
checks.x86_64-linux = {
  boot = import ./tests/boot.nix { inherit pkgs; };
  project-mount = import ./tests/project-mount.nix { inherit pkgs; };
  # ...
};
```

This enables running tests via:
- `nix flake check` - runs all tests
- `nix build .#checks.x86_64-linux.boot` - runs specific test

### R6: Test Helpers Library

A shared library MUST provide common test utilities:

```nix
# tests/lib.nix
{
  # Create a minimal agentbox VM configuration for testing
  mkTestVm = { extraConfig ? {} }: { ... };
  
  # Common test assertions
  assertServiceSucceeded = service: ''
    machine.succeed("systemctl is-active ${service}.service")
  '';
  
  assertPathExists = path: ''
    machine.succeed("test -e ${path}")
  '';
  
  assertPathIsDirectory = path: ''
    machine.succeed("test -d ${path}")
  '';
  
  assertFileContains = { path, content }: ''
    machine.succeed("grep -q '${content}' ${path}")
  '';
  
  assertUserCanWrite = { user, path }: ''
    machine.succeed("sudo -u ${user} touch ${path}/.write-test && rm ${path}/.write-test")
  '';
}
```

### R7: Timeouts and Reliability

Tests MUST handle timing appropriately:
- Use `wait_for_unit` instead of arbitrary sleeps
- Set appropriate timeouts for network-dependent tests (git clone)
- Tests should be deterministic and not flaky

### R8: Error Messages

Test failures MUST provide clear, actionable error messages:
- Include relevant service logs on failure
- Show actual vs expected values
- Indicate which assertion failed

### R9: CI/CD Compatibility

Tests MUST be runnable in CI environments:
- No interactive prompts
- No GUI requirements
- Reasonable resource requirements (memory, disk)
- Exit with appropriate codes (0 for success, non-zero for failure)

### R10: Documentation

Each test file MUST include:
- Comment header explaining what the test covers
- Comments for non-obvious test steps
- Example of how to run the test individually

## Test Scenarios

### Boot Tests (`boot.nix`)

| ID | Scenario | Description |
|----|----------|-------------|
| B1 | Basic boot | VM boots to multi-user.target |
| B2 | User exists | Primary user (dev) exists and can log in |
| B3 | Sudo works | User has passwordless sudo access |
| B4 | SSH enabled | SSH service is running and accepting connections |
| B5 | Base packages | Core packages (git, rsync, vim, curl) are available |

### Project Mount Tests (`project-mount.nix`)

| ID | Scenario | Description |
|----|----------|-------------|
| M1 | Mount basic | Project directory is mounted at destPath |
| M2 | Mount writable | User can create/modify files in mounted directory |
| M3 | Mount marker validation | Service validates marker file exists |
| M4 | Mount marker skip | Service skips validation when validateMarker=false |
| M5 | Mount required fail | Boot fails when mount fails and required=true |
| M6 | Mount optional | Boot continues when mount fails and required=false |

### Project Copy Tests (`project-copy.nix`)

| ID | Scenario | Description |
|----|----------|-------------|
| C1 | Copy basic | Project is copied to destPath |
| C2 | Copy ownership | Copied files are owned by the user |
| C3 | Copy excludes | Excluded patterns are not copied |
| C4 | Copy refresh always | Directory is replaced on each boot |
| C5 | Copy refresh if-missing | Existing directory is preserved |
| C6 | Copy required fail | Boot fails when copy fails and required=true |

### Project Git Tests (`project-git.nix`)

| ID | Scenario | Description |
|----|----------|-------------|
| G1 | Git clone public | Public repository is cloned successfully |
| G2 | Git clone shallow | Shallow clone has limited history |
| G3 | Git checkout ref | Specific branch/tag/commit is checked out |
| G4 | Git refresh always | Repository is re-cloned on each boot |
| G5 | Git refresh if-missing | Existing repository is preserved |
| G6 | Git required fail | Boot fails when clone fails and required=true |
| G7 | Git marker validation | Marker file is validated after clone |

### Host Shares Tests (`host-shares.nix`)

| ID | Scenario | Description |
|----|----------|-------------|
| H1 | Share basic | Files from shared directory are copied to user home |
| H2 | Share permissions | Directory and file permissions are set correctly |
| H3 | Share file overrides | Per-file permission overrides are applied |
| H4 | Share multiple | Multiple host shares are all synced |

### Docker Tests (`tools-docker.nix`)

| ID | Scenario | Description |
|----|----------|-------------|
| D1 | Docker disabled | Docker is not installed when enable=false |
| D2 | Docker enabled | Docker daemon starts when enable=true |
| D3 | Docker user access | User can run docker commands without sudo |
| D4 | Docker run | Basic container runs successfully |

### Tool Tests (Optional)

These tests may be skipped if the tools require external authentication:

| ID | Scenario | Description |
|----|----------|-------------|
| T1 | Auggie installed | auggie binary exists when enabled |
| T2 | Cursor installed | cursor-cli binary exists when enabled |

## Test Implementation Details

### NixOS Test Structure

Each test file follows this pattern:

```nix
# tests/project-mount.nix
# Tests for project source type: mount
# Run: nix build .#checks.x86_64-linux.project-mount
{ pkgs, ... }:

let
  lib = import ./lib.nix { inherit pkgs; };
in
pkgs.nixosTest {
  name = "agentbox-project-mount";

  # Define test VMs
  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules ];

    # Test-specific configuration
    agentbox.project.source.type = "mount";
    agentbox.project.destPath = "/home/dev/project";

    # Provide a mock project directory for testing
    # (In real tests, we need to handle this specially)
  };

  # Test script (Python)
  testScript = ''
    start_all()

    # Wait for boot
    machine.wait_for_unit("multi-user.target")

    # Test assertions
    machine.wait_for_unit("mount-host-project.service")
    machine.succeed("test -d /home/dev/project")
  '';
}
```

### Mock Project Directory

For mount and copy tests, we need to provide a mock project directory. Options:

**Option A: Use a derivation as mock project**
```nix
mockProject = pkgs.runCommand "mock-project" {} ''
  mkdir -p $out
  echo "test content" > $out/flake.nix
  echo "data" > $out/README.md
'';
```

**Option B: Create directory in test script**
```python
machine.succeed("mkdir -p /tmp/mock-project")
machine.succeed("echo 'mock' > /tmp/mock-project/flake.nix")
```

**Option C: Use virtualisation.sharedDirectories**
```nix
virtualisation.sharedDirectories.project = {
  source = toString ./fixtures/mock-project;
  target = "/mnt/host-project";
};
```

Recommended: **Option C** for mount/copy tests, as it most closely simulates the real scenario.

### Git Test Repository

For git tests, use a public test repository:

```nix
agentbox.project = {
  source.type = "git";
  source.git.url = "https://github.com/octocat/Hello-World.git";
  # Or use a local git server in the test
};
```

Alternative: Run a local git server in the test VM:

```nix
nodes.gitserver = { ... }: {
  services.gitDaemon.enable = true;
  # Set up test repository
};

nodes.machine = { ... }: {
  agentbox.project.source.git.url = "git://gitserver/test-repo.git";
};
```

### Handling Service Dependencies

The project services depend on 9p shares being passed from the host. In tests, we need to either:

1. **Mock the 9p share** using `virtualisation.sharedDirectories`
2. **Skip the mount step** and test the service logic separately
3. **Use a different test approach** for services that require host interaction

Recommended approach for each source type:

| Source Type | Test Approach |
|-------------|---------------|
| mount | Use `virtualisation.sharedDirectories` to simulate 9p share |
| copy | Use `virtualisation.sharedDirectories` for source, test rsync logic |
| git | Clone from public repo or local git server |

## Implementation Plan

### Phase 1: Test Infrastructure Setup

**Tasks:**
1. Create `tests/` directory structure
2. Create `tests/lib.nix` with shared utilities
3. Create `tests/default.nix` to export all tests
4. Update `flake.nix` to expose tests via `checks` output
5. Create test fixtures directory (`tests/fixtures/`)

**Files to create:**
| File | Purpose |
|------|---------|
| `tests/default.nix` | Aggregates and exports all tests |
| `tests/lib.nix` | Shared test helpers and utilities |
| `tests/fixtures/mock-project/` | Mock project for mount/copy tests |

**Acceptance criteria:**
- `nix flake check` runs without errors
- Empty test infrastructure is in place

### Phase 2: Boot Tests

**Tasks:**
1. Create `tests/boot.nix` with basic boot tests
2. Test user creation and sudo access
3. Test SSH availability
4. Test base package installation

**Acceptance criteria:**
- All B1-B5 scenarios pass
- Tests complete in under 2 minutes

### Phase 3: Project Mount Tests

**Tasks:**
1. Create `tests/project-mount.nix`
2. Set up shared directory fixture
3. Implement M1-M6 test scenarios
4. Handle marker validation tests

**Acceptance criteria:**
- All M1-M6 scenarios pass
- Mount permissions work correctly

### Phase 4: Project Copy Tests

**Tasks:**
1. Create `tests/project-copy.nix`
2. Set up source directory fixture with excludable content
3. Implement C1-C6 test scenarios
4. Test exclude patterns work correctly

**Acceptance criteria:**
- All C1-C6 scenarios pass
- Exclude patterns filter correctly

### Phase 5: Project Git Tests

**Tasks:**
1. Create `tests/project-git.nix`
2. Configure network access for git clone
3. Implement G1-G7 test scenarios
4. Handle shallow clone and ref checkout

**Acceptance criteria:**
- All G1-G7 scenarios pass
- Git operations complete successfully

### Phase 6: Docker Tests

**Tasks:**
1. Create `tests/tools-docker.nix`
2. Test docker enable/disable
3. Test container execution

**Acceptance criteria:**
- All D1-D4 scenarios pass
- Docker daemon starts and runs containers

### Phase 7: Documentation

**Tasks:**
1. Add "Development" section to README.md
2. Document how to run tests locally
3. Document how to debug failing tests
4. Document how to add new tests

**Acceptance criteria:**
- Developers can run tests following README instructions
- Debug workflow is documented

## Files to Modify/Create

| File | Action | Purpose |
|------|--------|---------|
| `tests/default.nix` | Create | Export all tests |
| `tests/lib.nix` | Create | Shared test utilities |
| `tests/boot.nix` | Create | Basic boot tests |
| `tests/project-mount.nix` | Create | Mount source tests |
| `tests/project-copy.nix` | Create | Copy source tests |
| `tests/project-git.nix` | Create | Git source tests |
| `tests/host-shares.nix` | Create | Host shares sync tests |
| `tests/tools-docker.nix` | Create | Docker integration tests |
| `tests/fixtures/mock-project/` | Create | Test fixtures directory |
| `tests/fixtures/mock-config/` | Create | Mock host config for hostShares tests |
| `flake.nix` | Modify | Add `checks` output |
| `README.md` | Modify | Add "Development" section with test instructions |

## Example Test Implementation

### Boot Test Example

```nix
# tests/boot.nix
# Basic VM boot tests
# Run: nix build .#checks.x86_64-linux.boot --print-build-logs
{ pkgs, self }:

pkgs.nixosTest {
  name = "agentbox-boot";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    # Minimal configuration
    agentbox.vm.hostname = "test-vm";
    agentbox.user.name = "dev";
  };

  testScript = ''
    # B1: Basic boot
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # B2: User exists
    machine.succeed("id dev")
    machine.succeed("getent passwd dev")

    # B3: Sudo works
    machine.succeed("sudo -u dev sudo -n true")

    # B4: SSH enabled
    machine.wait_for_unit("sshd.service")
    machine.succeed("systemctl is-active sshd")

    # B5: Base packages
    machine.succeed("which git")
    machine.succeed("which rsync")
    machine.succeed("which vim")
    machine.succeed("which curl")
  '';
}
```

### Project Mount Test Example

```nix
# tests/project-mount.nix
# Tests for project source type: mount
# Run: nix build .#checks.x86_64-linux.project-mount --print-build-logs
{ pkgs, self }:

let
  # Create a mock project directory
  mockProject = pkgs.runCommand "mock-project" {} ''
    mkdir -p $out
    echo '{ }' > $out/flake.nix
    echo '# Test Project' > $out/README.md
    mkdir -p $out/src
    echo 'console.log("hello")' > $out/src/index.js
  '';
in
pkgs.nixosTest {
  name = "agentbox-project-mount";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    agentbox.project = {
      source.type = "mount";
      destPath = "/home/dev/project";
      marker = "flake.nix";
      validateMarker = true;
    };

    # Simulate the 9p share from host
    virtualisation.sharedDirectories.host-project = {
      source = "${mockProject}";
      target = "/home/dev/project";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # M1: Mount basic
    machine.succeed("test -d /home/dev/project")
    machine.succeed("test -f /home/dev/project/flake.nix")
    machine.succeed("test -f /home/dev/project/README.md")

    # M2: Files are readable
    machine.succeed("cat /home/dev/project/flake.nix")
    machine.succeed("cat /home/dev/project/src/index.js")

    # M3: Marker validation (implicit - boot succeeded means marker was valid)
    # If marker validation failed, mount-host-project.service would have failed
  '';
}
```

## Running Tests

### Run All Tests

```bash
# Via flake check (includes all checks)
nix flake check

# Build all test derivations
nix build .#checks.x86_64-linux --print-build-logs
```

### Run Specific Test

```bash
# Run only boot tests
nix build .#checks.x86_64-linux.boot --print-build-logs

# Run only project-mount tests
nix build .#checks.x86_64-linux.project-mount --print-build-logs
```

### Debug Failed Test

```bash
# Run test with verbose output
nix build .#checks.x86_64-linux.boot --print-build-logs -L

# Interactive debugging (if test setup supports it)
nix build .#checks.x86_64-linux.boot.driverInteractive
./result/bin/nixos-test-driver
```

## Design Decisions

The following decisions were made through a Q&A refinement process:

| # | Decision | Choice |
|---|----------|--------|
| 1 | Git test network access | Use public test repository (e.g., `github.com/octocat/Hello-World`) |
| 2 | hostShares testing | Use `virtualisation.sharedDirectories` to simulate host shares and test sync logic |
| 3 | CI integration | No CI for now; tests run locally by developers only |
| 4 | Test coverage tracking | No tracking; maintain test scenario tables manually |

## Running Tests (Developer Guide)

Tests are run locally by developers. A "Development" section in README.md will explain:

```bash
# Run all tests
nix flake check

# Run specific test with logs
nix build .#checks.x86_64-linux.boot --print-build-logs

# Run with verbose output
nix build .#checks.x86_64-linux.project-mount --print-build-logs -L

# Interactive debugging
nix build .#checks.x86_64-linux.boot.driverInteractive
./result/bin/nixos-test-driver
```


