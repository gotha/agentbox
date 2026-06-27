# Phase 0 Research: Pre-install devShell Packages at Build Time

This phase resolves the open technical decisions behind the plan. The spec already settled the two product-level questions (install mode = **global packages**; source scope = **git only**); the questions here are about *how* to realize that purely and reproducibly in Nix.

---

## Decision 1 — How the project flake reaches the evaluator at build time

**Decision**: The consumer passes their **project flake as a Nix value** (a flake input they already lock in their own `flake.lock`) into agentbox via a new option (`agentbox.project.devShellPackages.flake`). agentbox reads `flake.devShells.<guestSystem>.<name>` from it during evaluation.

**Rationale**:
- In a flake build, **build time is evaluation time**. The only repository contents the evaluator may read are those reachable through locked inputs or already-fetched sources. The current `source.git.url` is a runtime string for a boot-time `systemd` clone — invisible to the evaluator — so it cannot drive build-time extraction.
- A flake input is **pure and reproducible**: it is pinned in `flake.lock`, fetched with the host's normal git/SSH credentials at `nix flake lock` time (covers private repos), and requires **no `--impure`**.
- It is idiomatic Nix and composes with agentbox's existing model where the consumer writes their own flake and calls `agentbox.lib.mkDevVm`. Adding one input + one option is minimal boilerplate.

**Alternatives considered**:
- **`builtins.getFlake "git+ssh://…?ref=main"` from `source.git.url`** — most "automatic" and closest to the literal request ("download the remote repository"), but a *mutable* ref fails in pure evaluation ("cannot fetch … in pure evaluation mode"); it only works with a pinned `rev` or under `--impure`. Private-repo auth at eval time is brittle (depends on daemon environment / SSH agent). **Kept as a documented opt-in fallback** for users who pin a rev or accept `--impure`, but not the primary path.
- **Import-From-Derivation (IFD): clone in a derivation, then import its flake** — heavy, serializes the build, fragile, and still needs network during eval. Rejected.
- **Parse `flake.nix`/`devShell` statically (text scraping)** — cannot resolve real derivations, breaks on any non-trivial expression. Rejected.

**Reconciliation with the spec**: FR-002 ("locate the project's flake from the configured project source") is satisfied — the flake *is* the configured source, just provided as a locked input rather than a runtime URL string. FR-005 (git only; mount/copy report unavailable) is satisfied because only a build-time-readable flake can feed extraction; when the feature is enabled without such a flake (the situation for `mount`/`copy`), evaluation fails with a clear message (Decision 4). The spec's credential assumption resolves to "the host's standard git/SSH config used by Nix when locking inputs."

---

## Decision 2 — Extracting the package list from a devShell

**Decision**: Treat the selected devShell as a derivation and collect its declared inputs:
`(shell.buildInputs or []) ++ (shell.nativeBuildInputs or []) ++ (shell.propagatedBuildInputs or []) ++ (shell.propagatedNativeBuildInputs or [])`, then de-duplicate. These derivations are appended to `environment.systemPackages`.

**Rationale**:
- `pkgs.mkShell` (the near-universal way to define a devShell) merges its `packages` argument into `nativeBuildInputs` and keeps `buildInputs`; both are plain attributes on the resulting derivation, readable at eval time without building anything.
- `environment.systemPackages` realizes exactly those store paths into the system closure → baked into the image (global install, on `PATH`). Because they are the *same* derivations the flake's devShell references, a later `nix develop` finds them already in the store (satisfies FR-010 — no re-fetch from mismatch).
- Reading attributes is pure and cheap; no IFD, no build during eval.

**Alternatives considered**:
- **Add the whole `devShell` derivation to `systemPackages`** — a `mkShell` result is not a normal installable package (no usable `bin/`); installing it doesn't put tools on `PATH`. Rejected.
- **`nix print-dev-env` / `nix develop --profile` at build time** — runtime tooling, impure, not available during pure module evaluation. Rejected.
- **Only `buildInputs`** — misses tools passed via `packages =`/`nativeBuildInputs` (the common case). Rejected in favor of the union above.

**Edge handling**: if the shell is not a `mkShell`-style derivation, the `or []` fallbacks yield an empty union; combined with Decision 4 this surfaces as a "no packages detected" condition rather than a crash.

---

## Decision 3 — System matching (guest vs host)

**Decision**: Resolve the devShell at `devShells.<guestSystem>.<name>`, where `guestSystem` is the Linux system already computed in `lib/mk-dev-vm.nix` (`hostToGuest` map). Thread that value to the module via `specialArgs`/`config` so the module evaluates the correct platform.

**Rationale**: The VM is always Linux (`aarch64-linux`/`x86_64-linux`) even when the host is macOS. Extracting `devShells.x86_64-darwin.*` would yield Darwin store paths that cannot be installed in the guest. Using `guestSystem` guarantees the extracted closure matches the VM's architecture. `mk-dev-vm.nix` already exposes `hostSystem`/`gothaPkgs` via `specialArgs`; adding `guestSystem` is a one-line, consistent extension.

**Alternatives considered**: deriving the system from `pkgs.system` inside the module (works, but `mk-dev-vm.nix` is the single source of truth for the host→guest mapping; reuse it). Acceptable either way; prefer the explicit thread-through for clarity.

---

## Decision 4 — Error & no-op behavior (FR-006 / FR-007)

**Decision**: Fail the build with a **clear, actionable message** rather than silently producing an incomplete VM. Specifically:
- Feature **enabled but no `flake` provided** (the case for `mount`/`copy`, or a forgotten input) → module **assertion** failure naming the option and explaining git-only/build-time-flake requirement.
- `flake` provided but `devShells.<guestSystem>` or the selected `<name>` is **absent** → `throw` with the available shell names (or "none") listed.
- Selected devShell exists but **fails to evaluate / yields zero installable packages** → surface the evaluation error (do not swallow it) / `throw` a clear "devShell present but no packages could be extracted" message.

**Rationale**: The user explicitly opted in and supplied (or should have supplied) a flake, so any of these is almost certainly a misconfiguration. A hard, descriptive failure is the most "unambiguous" outcome (FR-006) and prevents the "partially pre-installed VM" FR-007 forbids. NixOS `assertions` and `throw` both abort evaluation with the message shown to the user — no silent path.

**Alternatives considered**: `lib.warn` + empty list (proceed) — reads as a near-silent no-op and risks shipping a VM the user believes is pre-baked but isn't. Rejected for the default. (A future "soft mode" option could allow warn-and-continue, but it is out of scope for v1.)

---

## Decision 5 — Selecting among multiple devShells (FR-008)

**Decision**: A `name` option (default `"default"`) selects which `devShells.<guestSystem>.<name>` to extract. If the named shell is missing, fail per Decision 4 and list the available names.

**Rationale**: Flakes commonly expose a `default` plus named shells. Defaulting to `default` matches `nix develop` with no argument; an explicit `name` covers projects whose dev tooling lives in a named shell. Simple, predictable, matches FR-008.

---

## Decision 6 — Opt-in, backward compatibility, and option placement

**Decision**: Gate everything behind `agentbox.project.devShellPackages.enable` (default `false`), declared in `modules/default.nix` with defaults in `config.nix`, implemented in a new `modules/devshell-packages.nix` imported by `modules/default.nix`. When disabled, the module contributes nothing.

**Rationale**: Mirrors every existing agentbox capability (`docker`, `auggie`, `codex`, `cursor`, `crush`, `claudecode`) — same `mkOption`/`defaults`/`mkIf` pattern, same import style. Guarantees FR-001/SC-003 (zero change when off) and keeps the new behavior discoverable and consistent.

**Alternatives considered**: folding the logic into `modules/packages.nix` — rejected; a dedicated module keeps concerns and assertions isolated and testable, consistent with the one-file-per-capability convention.

---

## Decision 7 — Testing strategy

**Decision**: Two layers.
1. **Pure eval tests** for `lib/extract-devshell-packages.nix` (extends `tests/lib.nix`): given a fixture flake, assert the extracted package set, the multi-shell selection, and the error cases (missing shell name → throws).
2. **NixOS VM test** (`tests/devshell-packages.nix`, registered in `tests/default.nix`): build a VM with the feature enabled against the `tests/fixtures/devshell-project` flake (devShell declaring a distinctive tool, e.g. `cowsay`), boot it, and assert the tool is on `PATH` **without network** — directly validating SC-001 and User Story 1.

**Rationale**: Matches the project's existing test conventions (`pkgs.nixosTest` + `tests/lib.nix`, fixtures under `tests/fixtures/`). The eval tests give fast feedback on the helper's logic and error paths; the VM test proves the end-to-end, offline-availability outcome the feature exists for.

**Note on test purity**: the fixture flake is referenced as a **path input** within the test, keeping the VM test hermetic (no network needed to obtain the project flake itself), which also lets the offline-boot assertion be meaningful.

---

## Resolved unknowns summary

| Unknown | Resolution |
|---|---|
| Make project flake visible at eval time | Consumer passes locked flake **input** as a Nix value (pure); `getFlake`/URL is a documented impure fallback |
| Get packages from a devShell | Union of `build/nativeBuild/propagated*` inputs of the `mkShell` derivation, de-duped → `environment.systemPackages` |
| Host vs guest architecture | Extract `devShells.<guestSystem>.<name>` using the existing host→guest mapping |
| No flake / no devShell / eval error | Assertion or `throw` with a clear message — never a silent no-op (FR-006/FR-007) |
| Multiple devShells | `name` option, default `"default"`; missing name → clear failure listing available names |
| Opt-in & backward compat | `devShellPackages.enable = false` default; dedicated module mirroring existing capability pattern |
| Testing | Pure eval tests for the helper + an offline-boot nixosTest asserting the tool is on `PATH` |

No `NEEDS CLARIFICATION` items remain.
