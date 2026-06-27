# Phase 1 Data Model: Pre-install devShell Packages at Build Time

This feature has no persistent/runtime data store. The "entities" are **evaluation-time** values: module configuration, the project flake value, and the derived package set. They are modeled here as the option schema and the helper's input/output shapes.

---

## Entity: `devShellPackages` configuration (option group)

New option group `agentbox.project.devShellPackages`, declared in `modules/default.nix`, defaults in `config.nix`.

| Field | Type | Default | Required when enabled | Description |
|---|---|---|---|---|
| `enable` | bool | `false` | — | Master opt-in. When `false`, the module is inert and the build is identical to current behavior (FR-001, SC-003). |
| `flake` | nullOr (flake value / attrset) | `null` | **yes** | The project flake, passed as a Nix value (a locked input from the consumer's `flake.lock`). Source of `devShells`. (Decision 1) |
| `name` | str | `"default"` | — | Which `devShells.<guestSystem>.<name>` to extract (FR-008, Decision 5). |

**Validation rules** (enforced in `modules/devshell-packages.nix`; see `contracts/module-options.md`):
- `enable == true && flake == null` → **assertion failure** (clear message; this is the `mount`/`copy` / forgotten-input case — FR-005, FR-006).
- `enable == true && flake != null` but `flake.devShells.<guestSystem>` missing **or** `<name>` missing → **`throw`** listing available shell names or "none" (FR-006, Decision 4/5).
- `enable == true` and the selected devShell evaluates but yields **zero** installable packages → **`throw`** "devShell present but no packages extracted" (FR-007).
- `enable == false` → no assertions, no contributions (FR-001).

**State**: none (no transitions). The value is fixed at evaluation time; changing the project's devShell requires re-locking the input and rebuilding (spec Assumption: pre-installed set reflects build-time state).

---

## Entity: Project flake

The consumer's project flake, supplied as `devShellPackages.flake`.

- **Relevant shape**: `flake.devShells.<system>.<name>` → a derivation (typically a `pkgs.mkShell` result).
- **Origin**: a locked flake input in the consumer's flake (`inputs.project`), fetched with the host's git/SSH credentials at lock time.
- **Relationship**: read-only input to the **Extraction helper**; independent of the runtime `source.git.*` config used for the boot-time clone (the two should point at the same repo/ref for consistency — documented, not enforced).

---

## Entity: devShell derivation

The selected `devShells.<guestSystem>.<name>` value.

- **Relevant attributes** (all read at eval time, no build): `buildInputs`, `nativeBuildInputs`, `propagatedBuildInputs`, `propagatedNativeBuildInputs` — each a list of package derivations. Absent attributes default to `[]`.
- **Relationship**: the union of these lists (de-duplicated) is the **Extracted package set**.

---

## Entity: Extracted package set

The output of the helper — a list of package derivations.

- **Derivation**: `dedup(buildInputs ++ nativeBuildInputs ++ propagatedBuildInputs ++ propagatedNativeBuildInputs)` of the selected devShell (Decision 2).
- **Consumption**: appended to `environment.systemPackages` (alongside base packages and `agentbox.packages.extra`), realized into the system closure → baked into the image (global install, on `PATH`).
- **Constraints**: every element must be buildable for `<guestSystem>` (guaranteed by extracting from `devShells.<guestSystem>`). Determines the image-size growth noted in the spec.
- **Observability** (FR-009, SC-006): the set must be enumerable by the user — surfaced via a build-time trace and/or a readable artifact in the VM (see `contracts/extraction.md`).

---

## Entity: Guest system (derived)

`guestSystem` ∈ { `aarch64-linux`, `x86_64-linux` }, mapped from `hostSystem` in `lib/mk-dev-vm.nix`.

- **Role**: selects the platform slice of the project flake's `devShells` (Decision 3).
- **Relationship**: threaded into the module so extraction resolves the correct architecture regardless of host OS (macOS hosts still build Linux guests).

---

## Relationships (summary)

```text
consumer flake
  └─ inputs.project (locked)  ──passed as──▶  devShellPackages.flake
                                                     │
                          guestSystem ──┐            │
                                        ▼            ▼
                        flake.devShells.<guestSystem>.<name>   (devShell derivation)
                                        │
                              extract-devshell-packages
                                        │
                                        ▼
                              Extracted package set  ──▶  environment.systemPackages  ──▶  VM image (PATH)
```
