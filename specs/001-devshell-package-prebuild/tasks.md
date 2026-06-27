---
description: "Task list for Pre-install devShell Packages at Build Time"
---

# Tasks: Pre-install devShell Packages at Build Time

**Input**: Design documents from `specs/001-devshell-package-prebuild/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Test tasks ARE included. Rationale: the plan's Constitution gate ("Tested via NixOS VM framework") and research Decision 7 make tests part of this feature's deliverable, and every existing agentbox capability ships with a `tests/` entry. Tests here are not strict TDD-first; they validate each story's behavior.

**Organization**: Tasks are grouped by user story (US1 = P1, US2 = P2, US3 = P3) so each story is an independently testable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Path Conventions

This is a **Nix module library** (no `src/` tree). Code lives in `lib/`, `modules/`, `config.nix`; tests in `tests/` (+ `tests/fixtures/`); consumer examples in `examples/`. All paths below are repository-relative.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Defaults and a reusable, hermetic test fixture that the rest of the work builds on.

- [x] T001 [P] Add a `project.devShellPackages` defaults block (`enable = false; flake = null; name = "default";`) to `config.nix` (mirrors existing default groups; see data-model.md).
- [x] T002 [P] Create a hermetic devShell test fixture at `tests/fixtures/devshell-project/default.nix` — a `{ pkgs, system }:` function returning `{ devShells.${system} = { default = pkgs.mkShell { packages = [ pkgs.cowsay ]; }; ci = pkgs.mkShell { packages = [ pkgs.hello ]; }; empty = pkgs.mkShell { }; }; }`. Distinctive tools (`cowsay`, `hello`) make PATH assertions unambiguous; reused by eval and VM tests with no network.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The pure extraction helper, option surface, and plumbing that EVERY user story depends on. No user-visible behavior yet.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 [P] Implement the pure helper `lib/extract-devshell-packages.nix` per `contracts/extraction.md`: resolve `flake.devShells.${system}.${name}`; return the de-duplicated union of `buildInputs ++ nativeBuildInputs ++ propagatedBuildInputs ++ propagatedNativeBuildInputs`; `throw` clear messages on missing system, missing `name` (listing available names), and empty package set. No build, no `--impure`.
- [x] T004 Export `extractDevShellPackages` from `lib/default.nix` (depends on T003).
- [x] T005 [P] Resolve the guest system inside `modules/devshell-packages.nix` via `pkgs.stdenv.hostPlatform.system` (the module's `pkgs` is always the guest's package set, so this is the guest system on macOS hosts too — and unlike `specialArgs` threading it also works when the module is used directly in `pkgs.testers.nixosTest`). Refinement of research Decision 3; `lib/mk-dev-vm.nix` left unchanged.
- [x] T006 [P] Declare the `agentbox.project.devShellPackages` options (`enable`, `flake` as `nullOr unspecified`, `name`) in `modules/default.nix`, backed by the `config.nix` defaults from T001 (see contracts/module-options.md).

**Checkpoint**: Helper is unit-testable; options exist and evaluate; nothing yet alters the image.

---

## Phase 3: User Story 1 - Pre-bake devShell dependencies into the VM (Priority: P1) 🎯 MVP

**Goal**: With the feature enabled and a project flake provided, the devShell's packages are baked into the VM as global packages — present on `PATH` at boot, offline.

**Independent Test**: Build a VM with `devShellPackages.enable = true` against the fixture's `default` shell, boot with networking disabled, and confirm `cowsay` is on `PATH` with zero downloads.

### Tests for User Story 1

- [x] T007 [P] [US1] Create `tests/devshell-packages-eval.nix` with a pure eval test: feeding the T002 fixture `default` shell through `extractDevShellPackages` returns a set containing `cowsay` (properties P1/P2/P7 in contracts/extraction.md). Depends on T003/T004.
- [x] T008 [P] [US1] Create the VM test `tests/devshell-packages.nix`: a `pkgs.nixosTest` that imports `self.nixosModules.default`, sets `agentbox.project.devShellPackages = { enable = true; flake = <T002 fixture value>; }`, boots, and asserts `cowsay` is on the dev user's `PATH` (`machine.succeed`) — validating SC-001/SC-004.
- [x] T009 [US1] Register `devshell-packages` (VM) and `devshell-packages-eval` in `tests/default.nix` (depends on T007, T008).

### Implementation for User Story 1

- [x] T010 [US1] Create `modules/devshell-packages.nix`: `lib.mkIf cfg.project.devShellPackages.enable`, read `guestSystem`, call `extractDevShellPackages { flake; system = guestSystem; inherit name; }`, and append the result to `environment.systemPackages` (without clobbering base packages or `agentbox.packages.extra`); add the file to `imports` in `modules/default.nix`. Depends on T003, T004, T005, T006. (Realizes FR-002/003/004, FR-010, FR-011.)
- [x] T011 [US1] Run the quickstart happy-path validation (build the VM, boot offline, confirm the tool on `PATH`) per quickstart.md §3; fix any wiring gaps. Depends on T009, T010.

**Checkpoint**: MVP — pre-installed devShell tools are available at boot, offline. Feature is demoable.

---

## Phase 4: User Story 2 - Opt-in, with safe default behavior (Priority: P2)

**Goal**: Disabled by default (zero change to existing builds); when enabled but misconfigured (no build-time flake / mount-copy / missing shell / empty shell), the build fails clearly instead of producing a confusing VM.

**Independent Test**: (a) Build with the option off → identical to baseline. (b) Enable with `flake = null` → build fails with a message naming `devShellPackages.flake`. (c) `name = "nope"` → build fails listing available shells.

### Implementation for User Story 2

- [x] T012 [US2] Add a module-level assertion in `modules/devshell-packages.nix`: when `enable == true && flake == null`, fail with a clear message naming `devShellPackages.flake` and explaining the build-time-flake / git-only requirement (mount/copy unsupported). Depends on T010. (Realizes FR-005/FR-006, contract C3.)

### Tests for User Story 2

- [x] T013 [US2] Extend `tests/devshell-packages-eval.nix` with failure-mode eval tests: missing system throws; missing `name` throws and lists available names; the fixture `empty` shell throws "no installable packages" (properties P4/P5/P6, FR-006/FR-007). Depends on T007.
- [x] T014 [US2] Add a default-off regression test (eval/build assertion that with `enable = false` the module contributes nothing and `systemPackages` matches baseline) to `tests/devshell-packages-eval.nix` (SC-003, FR-001). Depends on T013.
- [x] T015 [US2] Add a test that `enable = true` with `flake = null` fails the build with the expected assertion message (contract C3) to `tests/devshell-packages-eval.nix`. Depends on T012, T013.
- [x] T016 [US2] Run the quickstart failure-mode validations (table in quickstart.md §4) and confirm each produces the documented clear failure. Depends on T012, T015.

**Checkpoint**: Feature is safe to ship — invisible when off, loud and clear when misconfigured.

---

## Phase 5: User Story 3 - Visibility into what was pre-installed (Priority: P3)

**Goal**: The user can enumerate exactly which packages were extracted and baked in — at build time and from inside the running VM.

**Independent Test**: Build with the feature on; confirm the build output lists the resolved package names and a manifest inside the VM lists the same set (including `cowsay`).

### Implementation for User Story 3

- [x] T017 [US3] In `modules/devshell-packages.nix`, emit the resolved package names at build time via `builtins.trace`/`lib.warn` (FR-009, contract C8). Depends on T010.
- [x] T018 [US3] In `modules/devshell-packages.nix`, write a readable manifest into the image listing the pre-installed package names (e.g. `environment.etc."agentbox/devshell-packages".text`). Depends on T017. (SC-006.)

### Tests for User Story 3

- [x] T019 [US3] Extend `tests/devshell-packages.nix` to assert the manifest file exists in the booted VM and lists the fixture tool (`cowsay`). Depends on T008, T018.
- [x] T020 [US3] Run the quickstart observability validation (quickstart.md §3, manifest read). Depends on T018, T019.

**Checkpoint**: All three stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T021 [P] Update `README.md`: document `agentbox.project.devShellPackages` (option table row + a dedicated section), the flake-input wiring, the git-only/build-time limitation, image-size trade-off, the impure `getFlake` fallback, and add `devshell-packages` to the "Available tests" list.
- [x] T022 [P] Create the example consumer flake `examples/devshell-prebuild-git/flake.nix` (+ `flake.lock`) wiring a project as an input and enabling `devShellPackages` (mirror `examples/custom-tools-git-clone` style; per quickstart.md §1).
- [x] T023 Code-consistency pass over `lib/extract-devshell-packages.nix` and `modules/devshell-packages.nix` (naming, comments, dedup logic match existing module conventions). Depends on T010, T018.
- [x] T024 Run the full suite `nix flake check` and the complete quickstart end-to-end on a clean checkout; confirm all `checks` pass. Depends on all prior tasks.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup (uses T001 defaults). BLOCKS all user stories.
- **User Stories (Phase 3–5)**: All depend on Foundational. US1 is the MVP. US2 and US3 build on US1's module file (they extend `modules/devshell-packages.nix`), so they layer on after US1 rather than in full parallel.
- **Polish (Phase 6)**: Depends on the desired user stories being complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational. Self-contained MVP.
- **US2 (P2)**: After US1 (adds an assertion to and tests around US1's module). Independently testable via its own failure-mode tests.
- **US3 (P3)**: After US1 (adds trace + manifest to US1's module). Independently testable via the manifest assertion.

### Within Each User Story

- Foundational helper/options before module wiring.
- Module behavior before its tests can pass; eval tests can be authored alongside the helper.
- Story complete (checkpoint) before moving to the next priority.

### Parallel Opportunities

- Setup: **T001 and T002** in parallel (different files).
- Foundational: **T003, T005, T006** in parallel (different files); T004 after T003.
- US1: **T007 and T008** (two new test files) in parallel; then T009, T010, T011.
- Polish: **T021 and T022** in parallel (README vs example).
- Sequential within a file: T012/T017/T018 all edit `modules/devshell-packages.nix` (not parallel); T013/T014/T015 all edit `tests/devshell-packages-eval.nix` (not parallel).

---

## Parallel Example: Foundational Phase

```bash
# After Setup, launch the independent foundational files together:
Task: "Implement lib/extract-devshell-packages.nix (pure helper)"        # T003
Task: "Thread guestSystem via specialArgs in lib/mk-dev-vm.nix"           # T005
Task: "Declare devShellPackages options in modules/default.nix"          # T006
# Then: T004 (export in lib/default.nix) once T003 lands.
```

## Parallel Example: User Story 1 Tests

```bash
Task: "Eval test for extractDevShellPackages in tests/devshell-packages-eval.nix"  # T007
Task: "Offline-boot VM test in tests/devshell-packages.nix"                         # T008
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup (T001–T002)
2. Phase 2: Foundational (T003–T006) — **blocks everything**
3. Phase 3: User Story 1 (T007–T011)
4. **STOP and VALIDATE**: build + boot offline; confirm devShell tools on `PATH`. This is a shippable MVP.

### Incremental Delivery

1. Setup + Foundational → plumbing ready
2. US1 → pre-install works (MVP) → demo
3. US2 → safe default + clear failures → demo
4. US3 → observability/manifest → demo
5. Polish → docs, example, full `nix flake check`

### MVP Scope

**User Story 1 (T001–T011)** delivers the core value on its own: devShell packages baked into the VM, available at boot, offline. US2 (safety/clarity) and US3 (visibility) are valuable hardening layers but not required to demonstrate the feature.

---

## Notes

- `[P]` = different files, no incomplete dependencies.
- `[Story]` labels map tasks to spec.md user stories for traceability.
- US2 and US3 deliberately extend US1's module file; sequence them after US1 rather than forcing artificial file-level parallelism.
- Tests use **synthetic flake-value attrsets** (the T002 fixture) so both eval and VM tests stay hermetic and the offline-boot assertion is meaningful — no project repo is fetched during tests.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
