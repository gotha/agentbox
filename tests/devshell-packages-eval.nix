# devShellPackages extraction helper - pure evaluation tests
# Run: nix build .#checks.x86_64-linux.devshell-packages-eval --print-build-logs
#
# Tests the pure helper lib/extract-devshell-packages.nix against the hermetic
# fixture: happy-path extraction (US1) and the fail-loud error cases (US2).
{ pkgs, self }:

let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  extract = self.lib.extractDevShellPackages;
  fixture = import ./fixtures/devshell-project { inherit pkgs system; };

  hasPkg = name: list: lib.any (p: lib.getName p == name) list;

  # True when calling extract with these args throws (fail-loud cases).
  throwsFor = args: !(builtins.tryEval (lib.deepSeq (extract args) true)).success;

  checks = {
    # US1 - happy path
    default_has_cowsay = hasPkg "cowsay" (extract { flake = fixture; inherit system; name = "default"; });
    ci_has_hello = hasPkg "hello" (extract { flake = fixture; inherit system; name = "ci"; });

    # US2 - fail-loud error cases (FR-006 / FR-007)
    missing_name_throws = throwsFor { flake = fixture; inherit system; name = "nope"; };
    missing_system_throws = throwsFor { flake = { devShells = { }; }; inherit system; name = "default"; };
    empty_shell_throws = throwsFor { flake = fixture; inherit system; name = "empty"; };
  };

  failed = lib.attrNames (lib.filterAttrs (_: v: v != true) checks);
in
assert lib.assertMsg (failed == [ ])
  "devshell-packages-eval failed checks: ${lib.concatStringsSep ", " failed}";
pkgs.runCommand "agentbox-devshell-packages-eval" { } ''
  {
    echo "agentbox devShell extraction eval checks:"
    ${lib.concatStringsSep "\n" (map (n: "echo '  PASS - ${n}'") (lib.attrNames checks))}
  } > $out
''
