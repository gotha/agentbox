# Contract: `extractDevShellPackages` helper

Pure evaluation-time function in `lib/extract-devshell-packages.nix`, exposed via `lib/default.nix`. It is the testable core of the feature (no I/O, no build, no impurity).

## Signature

```nix
extractDevShellPackages :: {
  flake    :: <flake value>,   # attrset exposing devShells
  system   :: String,          # guest system, e.g. "x86_64-linux"
  name     :: String ? "default",
} -> [ <package derivation> ]
```

## Semantics

1. Resolve `shell = flake.devShells.${system}.${name}`.
   - If `flake.devShells.${system}` is missing → **throw**: `"devShellPackages: project flake has no devShells for system '${system}'"`.
   - Else if `${name}` is missing → **throw**: `"devShellPackages: devShell '${name}' not found for '${system}'. Available: <comma-separated names | none>"`.
2. Collect inputs:
   `pkgs = (shell.buildInputs or []) ++ (shell.nativeBuildInputs or []) ++ (shell.propagatedBuildInputs or []) ++ (shell.propagatedNativeBuildInputs or [])`.
3. **De-duplicate** by store path / derivation identity.
4. If the de-duplicated list is **empty** → **throw**: `"devShellPackages: devShell '${name}' declares no installable packages"` (FR-007 — avoid a silent no-op image).
5. Return the de-duplicated, non-empty list.

## Properties (verified by pure eval tests)

| Property | Expectation |
|---|---|
| P1 — happy path | Fixture devShell declaring `[cowsay hello]` ⇒ result contains both (and any `mkShell` implicit inputs), de-duplicated. |
| P2 — `packages =` arg | Tools passed via `mkShell { packages = [...]; }` appear (they land in `nativeBuildInputs`). |
| P3 — named shell | `name = "ci"` extracts `devShells.<system>.ci`, not `default`. |
| P4 — missing system | Unknown `system` ⇒ throws the system-missing message. |
| P5 — missing name | Unknown `name` ⇒ throws, message lists available names. |
| P6 — empty shell | devShell with no inputs ⇒ throws the "no installable packages" message. |
| P7 — purity | Function evaluates with no build and no `--impure`. |

## Module integration contract (`modules/devshell-packages.nix`)

- Guarded by `lib.mkIf cfg.project.devShellPackages.enable`.
- `assertions = [{ assertion = flake != null; message = "..."; }]` for the null-flake case (C3) before calling the helper.
- Calls `extractDevShellPackages { flake; system = guestSystem; inherit name; }` and appends the result to `environment.systemPackages`.
- **Observability (FR-009/SC-006)**: emit the resolved package names via `builtins.trace`/`lib.warn` at build time **and** write a readable manifest into the image (e.g. a file under the user's project area or `/etc`) listing the pre-installed package names, so the set is enumerable from inside the VM after boot.

## Guest-system source

`guestSystem` is provided by `lib/mk-dev-vm.nix` (host→guest map) and threaded to the module via `specialArgs`/config, ensuring extraction targets the VM's Linux architecture even on macOS hosts (Decision 3).
