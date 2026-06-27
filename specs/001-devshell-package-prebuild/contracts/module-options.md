# Contract: `agentbox.project.devShellPackages` module options

This is the consumer-facing interface (the agentbox "API" is its NixOS option surface). It extends `modules/default.nix` and `config.nix`, following the same pattern as `agentbox.docker`, `agentbox.auggie`, etc.

## Option surface

```nix
agentbox.project.devShellPackages = {
  enable = mkOption {
    type = types.bool;
    default = false;                       # from config.nix
    description = ''
      Pre-install the packages declared in the project flake's devShell into the
      VM at build time, as globally available packages (on PATH at boot).
      Opt-in; when false the build is unchanged.
    '';
  };

  flake = mkOption {
    type = types.nullOr types.unspecified; # a flake value (attrset with devShells)
    default = null;                        # from config.nix
    example = literalExpression "inputs.project";
    description = ''
      The project flake, passed as a Nix value (a locked input from the
      consumer's flake.lock). Its devShells.<guestSystem>.<name> is read at
      build time. Required when enable = true. Only a build-time-readable flake
      works here, so mount/copy sources are not supported (see git source).
    '';
  };

  name = mkOption {
    type = types.str;
    default = "default";                   # from config.nix
    description = ''
      Which devShell to extract: devShells.<guestSystem>.<name>.
    '';
  };
};
```

## Behavioral contract

| # | Given | Then | Maps to |
|---|---|---|---|
| C1 | `enable = false` | Module contributes nothing; no assertions; build identical to today. | FR-001, FR-011, SC-003 |
| C2 | `enable = true`, valid `flake`, devShell with packages | The devShell's packages are appended to `environment.systemPackages`; available on `PATH` in the booted VM with no network. | FR-002, FR-003, FR-004, SC-001, SC-004 |
| C3 | `enable = true`, `flake = null` | **Assertion failure** with message naming `devShellPackages.flake` and explaining the build-time-flake (git-only) requirement. | FR-005, FR-006 |
| C4 | `enable = true`, `flake` set, `devShells.<guestSystem>` or `<name>` absent | **`throw`** listing available shell names (or "none"). | FR-006, FR-008 |
| C5 | `enable = true`, selected devShell unevaluatable / yields 0 packages | **`throw`** / surfaced eval error; build fails, no partial image. | FR-007 |
| C6 | `enable = true`, `name` set to a present named shell | That named shell is used instead of `default`. | FR-008 |
| C7 | any | Runtime `source.{type,git,…}` behavior is unchanged; this option only affects what is baked at build time. | FR-011 |
| C8 | C2 holds | The extracted package set is **observable** to the user (build trace and/or readable manifest in the VM). | FR-009, SC-006 |

## Defaults added to `config.nix`

```nix
project.devShellPackages = {
  enable = false;
  flake = null;
  name = "default";
};
```

## Non-goals (explicit)

- No new credential-handling flow — fetching/locking the `flake` input uses the host's standard git/SSH config.
- No `mount`/`copy` build-time support — those populate the VM only at boot.
- No continuous sync — the set reflects the flake at build/lock time; refresh = rebuild.
