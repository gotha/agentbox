# Implementation Plan: Pre-install devShell Packages at Build Time

**Branch**: `001-devshell-package-prebuild` | **Date**: 2026-06-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-devshell-package-prebuild/spec.md`

## Summary

Add an **opt-in** capability to agentbox so that, at VM **build time**, it reads a project's Nix flake `devShell`, extracts the packages that shell declares, and bakes them into the VM image as **globally installed** packages (`environment.systemPackages`). The result: when the user boots the VM, the project's dev tools are already on `PATH` — no download, no build, works offline — and a later `nix develop` finds the identical store paths already present.

The core technical constraint drives the whole design: in a flake-based build, **build time == Nix evaluation time**. The existing `agentbox.project.source.git.url` is only a runtime string handed to a boot-time `systemd` service; the evaluator never sees the repository. To extract packages during evaluation, the project flake must be reachable by the evaluator. The chosen approach (see [research.md](./research.md)) is to accept the **project flake as a Nix value** (a locked flake input the consumer already has), keeping evaluation pure and reproducible, and to construct the package list with a small pure helper that reads `devShells.<guestSystem>.<name>`.

## Technical Context

**Language/Version**: Nix (flakes enabled); NixOS module system; nixpkgs `nixos-26.05`; guest `system.stateVersion = "25.11"`. Boot-time glue is POSIX `sh` in `systemd` oneshot services.

**Primary Dependencies**: `nixpkgs` (nixos-26.05) + `gotha-nixpkgs` flake inputs; `nixpkgs.lib` (module system, `mkOption`, `mkIf`, assertions); `modulesPath + /virtualisation/qemu-vm.nix`; the consumer project flake's `devShells` output (typically built with `pkgs.mkShell`).

**Storage**: N/A — declarative. The unit of persistence is the VM image / Nix store closure produced by the build.

**Testing**: NixOS VM testing framework (`pkgs.nixosTest`, see `tests/`), run via `nix flake check` / `nix build .#checks.<system>.<name>`; plus pure evaluation tests for the extraction helper (`tests/lib.nix` pattern). A test fixture flake with a known devShell goes under `tests/fixtures/`.

**Target Platform**: NixOS guest VM (`aarch64-linux`, `x86_64-linux`), built from Linux hosts directly or macOS hosts via a Linux builder. Guest system is mapped from host in `lib/mk-dev-vm.nix`.

**Project Type**: Nix flake / NixOS module library (single project). No application src/ tree — code lives in `modules/`, `lib/`, `config.nix`, with tests in `tests/` and consumer examples in `examples/`.

**Performance Goals**: Build-time evaluation/extraction overhead is negligible relative to building the package closure. Primary win is runtime: first availability of the dev toolchain inside the VM drops from "download + build on first `nix develop`" to "already present at boot" (offline-capable). Image size grows by the devShell's build closure — an accepted trade-off.

**Constraints**: Must stay **pure-eval** (no `--impure` required for the primary path). Must be **backward compatible** — default off, zero change when disabled. Must **fail clearly** (build error) when enabled but no usable devShell is reachable. Supported source: **git** (a build-time-readable flake); `mount`/`copy` must report unavailability rather than silently skip.

**Scale/Scope**: Small, additive change — one new module (`modules/devshell-packages.nix`), one new lib helper (`lib/extract-devshell-packages.nix`), option wiring in `modules/default.nix` + `config.nix`, one fixture flake, one VM test + eval tests, README + one example. No changes to existing source-type services.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is still the **unfilled template** — no principles are ratified, so there are no formal constitutional gates to enforce. In their absence, this plan is held to the project's **de-facto conventions**, evident from the codebase:

| Gate (de-facto) | Status | Notes |
|---|---|---|
| **Opt-in / backward compatible** — new behavior defaults off, existing configs unchanged | PASS | Feature gated behind `agentbox.project.devShellPackages.enable = false` by default (mirrors `docker.enable`, `auggie.enable`, etc.). |
| **Declarative, reproducible, pure eval** — no `--impure`, no impure builtins on the primary path | PASS | Project flake consumed as a locked Nix input; extraction is a pure function. Impure `getFlake`/URL path documented only as an explicit fallback. |
| **Option-driven module pattern** — config via `agentbox.*` options backed by `config.nix` defaults | PASS | New options follow the exact `mkOption` + `defaults` pattern in `modules/default.nix`. |
| **Tested via NixOS VM framework** — end-to-end behavior covered by `pkgs.nixosTest` + added to `tests/default.nix` | PASS | New VM test boots offline and asserts the tool is on `PATH`; pure eval tests cover the helper. |
| **Clear failure over silent partial state** | PASS | Assertions/`throw` on misconfiguration and unevaluatable devShells (FR-006/FR-007). |

No violations → Complexity Tracking left empty. (Recommend running `/speckit-constitution` to ratify principles; this plan will need a re-check if real gates are later defined.)

## Project Structure

### Documentation (this feature)

```text
specs/001-devshell-package-prebuild/
├── plan.md              # This file (/speckit-plan output)
├── spec.md              # Feature specification (/speckit-specify output)
├── research.md          # Phase 0 output — design decisions & rationale
├── data-model.md        # Phase 1 output — config/eval entities
├── quickstart.md        # Phase 1 output — wire-up + validation guide
├── contracts/           # Phase 1 output — interface contracts
│   ├── module-options.md   # agentbox.project.devShellPackages option surface
│   └── extraction.md       # extract-devshell-packages helper contract
├── checklists/
│   └── requirements.md  # Spec quality checklist (already complete)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

Actual agentbox layout; new/changed paths marked. No application `src/` tree exists — this is a Nix module library.

```text
lib/
├── default.nix                       # CHANGED: expose extractDevShellPackages helper
├── mk-dev-vm.nix                     # CHANGED (minimal): pass guestSystem context so the
│                                     #   devshell module can resolve devShells.<guestSystem>
├── extract-devshell-packages.nix     # NEW: pure helper — flake -> [packages] (+ error cases)
├── mk-vm-apps.nix                    # (unchanged)
└── mk-vm-runner.nix                  # (unchanged)

modules/
├── default.nix                       # CHANGED: declare agentbox.project.devShellPackages options
│                                     #   + import ./devshell-packages.nix
├── devshell-packages.nix             # NEW: consumes options, runs extraction, appends to
│                                     #   environment.systemPackages, defines assertions
├── packages.nix                      # (unchanged — systemPackages already aggregates)
└── ...                               # (other modules unchanged)

config.nix                            # CHANGED: add project.devShellPackages defaults

tests/
├── default.nix                       # CHANGED: register the new test(s)
├── devshell-packages.nix             # NEW: nixosTest — build w/ feature on, boot offline,
│                                     #   assert fixture tool on PATH; assert clear failure cases
├── lib.nix                           # CHANGED (or new eval test): pure tests for the helper
└── fixtures/
    └── devshell-project/             # NEW: minimal flake fixture exposing devShells.<sys>.default
        └── flake.nix                 #   declaring a distinctive package (e.g. `hello`/`cowsay`)

examples/
└── devshell-prebuild-git/            # NEW: example consumer flake wiring project as an input
    ├── flake.nix                     #   + enabling devShellPackages
    └── flake.lock

README.md                             # CHANGED: document the option, the input wiring, limits
CLAUDE.md                             # CHANGED: SPECKIT markers point to this plan
```

**Structure Decision**: Single Nix module-library project. The feature is delivered as (1) a **pure lib helper** (`lib/extract-devshell-packages.nix`) that is independently unit-testable at eval time, (2) a thin **NixOS module** (`modules/devshell-packages.nix`) that wires options → helper → `environment.systemPackages` and owns the assertions, and (3) **option declarations** in `modules/default.nix` backed by defaults in `config.nix` — matching how every existing agentbox capability (docker, auggie, codex, …) is structured. No existing source-type service is modified; this is purely additive at build/eval time.

## Complexity Tracking

> No constitution gate violations. No entries required.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
