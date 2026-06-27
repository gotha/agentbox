# devShellPackages module - NixOS evaluation tests (no VM build)
# Run: nix build .#checks.x86_64-linux.devshell-packages-module-eval --print-build-logs
#
# Verifies module-level behavior without booting a VM:
#   - default off: the module contributes nothing (no manifest) - SC-003 / FR-001
#   - enabled with a null flake: a failing assertion is raised  - FR-005 / FR-006
{ pkgs, self }:

let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  fixture = import ./fixtures/devshell-project { inherit pkgs system; };

  # Evaluate the real production assembly (imports qemu-vm + all agentbox modules)
  # so module behavior is tested exactly as it is built, without booting a VM.
  evalCfg = extra: (self.lib.mkDevVm {
    hostSystem = system;
    modules = [ extra { agentbox.project.source.required = false; } ];
  }).config;

  # Default off: module is inert.
  offCfg = evalCfg { };
  defaultOffNoManifest = !(offCfg.environment.etc ? "agentbox/devshell-packages");

  # Enabled with no flake: a failing assertion must be present.
  nullFlakeCfg = evalCfg { agentbox.project.devShellPackages.enable = true; };
  nullFlakeFailsAssertion = lib.any (a: !a.assertion) nullFlakeCfg.assertions;

  # Enabled with the fixture flake: packages baked into systemPackages + manifest.
  onCfg = evalCfg { agentbox.project.devShellPackages = { enable = true; flake = fixture; }; };
  onSystemHasCowsay = lib.any (p: lib.getName p == "cowsay") onCfg.environment.systemPackages;
  onManifestHasCowsay = lib.hasInfix "cowsay" onCfg.environment.etc."agentbox/devshell-packages".text;

  checks = {
    default_off_no_manifest = defaultOffNoManifest;
    null_flake_fails_assertion = nullFlakeFailsAssertion;
    enabled_systempackages_has_cowsay = onSystemHasCowsay;
    enabled_manifest_has_cowsay = onManifestHasCowsay;
  };

  failed = lib.attrNames (lib.filterAttrs (_: v: v != true) checks);
in
assert lib.assertMsg (failed == [ ])
  "devshell-packages-module-eval failed checks: ${lib.concatStringsSep ", " failed}";
pkgs.runCommand "agentbox-devshell-packages-module-eval" { } ''
  {
    echo "agentbox devShellPackages module eval checks:"
    ${lib.concatStringsSep "\n" (map (n: "echo '  PASS - ${n}'") (lib.attrNames checks))}
  } > $out
''
