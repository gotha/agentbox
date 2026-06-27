# Quickstart: Pre-install devShell Packages at Build Time

A validation/run guide proving the feature end-to-end. For option details see
[contracts/module-options.md](./contracts/module-options.md); for the helper see
[contracts/extraction.md](./contracts/extraction.md).

## Prerequisites

- Nix with flakes enabled.
- Linux host, or macOS with a Linux builder (per README).
- A project flake that exposes `devShells.<system>.default` (or a named shell).

## 1. Wire the project flake into a consumer VM flake

The project is added as a **flake input** (so it is locked and readable at build time) and enabled via the new option:

```nix
{
  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-26.05";
    agentbox.url  = "github:gotha/agentbox";
    project.url   = "git+ssh://git@github.com/you/your-project";  # locked in flake.lock
    project.flake = true;
  };

  outputs = { self, nixpkgs, agentbox, project }:
  let allSystems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ]; in {
    nixosConfigurations = builtins.listToAttrs (map (hostSystem: {
      name = "vm-${hostSystem}";
      value = agentbox.lib.mkDevVm {
        inherit hostSystem;
        extraConfig = {
          # Runtime source (boot-time clone) — points at the same repo:
          agentbox.project.source.type    = "git";
          agentbox.project.source.git.url = "git@github.com:you/your-project.git";
          agentbox.project.marker         = "flake.nix";

          # NEW: bake the devShell packages into the image at build time
          agentbox.project.devShellPackages = {
            enable = true;
            flake  = project;     # the locked input above
            # name = "default";   # or a named devShell
          };
        };
      };
    }) allSystems);

    apps = agentbox.lib.mkVmApps { inherit (self) nixosConfigurations; };
  };
}
```

## 2. Build the VM

```bash
nix build .#nixosConfigurations.vm-x86_64-linux.config.system.build.vm
# or just: nix run .#vm
```

**Expected**: build succeeds; build output traces the resolved devShell package set
(FR-009). The devShell's closure is built and included in the image.

## 3. Validate: tools are present at boot, offline (SC-001, User Story 1)

```bash
nix run .#vm           # boot the VM
# inside the VM (ssh dev@... , empty password):
which <tool-from-devshell>      # e.g. `cowsay` / `go` / `node`
<tool-from-devshell> --version  # runs — no `nix develop`, no download
cat <pre-install manifest>      # enumerates what was baked in (FR-009 / SC-006)
```

To prove **offline** availability, boot with networking disabled (or run the
automated test below, which asserts this in a hermetic VM).

## 4. Validate failure modes (FR-006 / FR-007)

| Try | Expected |
|---|---|
| `enable = true;` with `flake` omitted (or `source.type = "mount"`/`"copy"`) | **Build fails** with an assertion naming `devShellPackages.flake` and the git-only requirement. |
| `name = "nope";` (no such shell) | **Build fails** with a `throw` listing available shell names. |
| Point `flake` at a project whose devShell has no packages | **Build fails** with "devShell declares no installable packages". |
| `enable = false;` | Build identical to baseline agentbox (SC-003). |

## 5. Automated tests

```bash
# Pure eval tests for the extraction helper:
nix eval .#checks.x86_64-linux.devshell-packages-eval   # (or via `nix flake check`)

# End-to-end: build VM with the feature on, boot offline, assert tool on PATH:
nix build .#checks.x86_64-linux.devshell-packages --print-build-logs

# Whole suite:
nix flake check
```

The VM test uses `tests/fixtures/devshell-project` (a flake whose devShell
declares a distinctive tool) and asserts that tool is on `PATH` in the booted
VM without network access — the concrete form of SC-001.

## Notes & limits

- **Reproducibility**: keep `devShellPackages.flake` and the runtime
  `source.git.url`/`ref` pointed at the same repo/ref. The baked set reflects the
  flake **at lock/build time**; updating the devShell means re-locking + rebuild.
- **Image size** grows by the devShell's build closure — expected.
- **Private repos**: locking the `project` input uses your normal git/SSH config;
  no extra agentbox credential setup is needed for the build-time read.
- **`getFlake`/URL fallback** (impure): if you cannot add an input, you may pin a
  `rev` and use the documented impure path — not the recommended default.
