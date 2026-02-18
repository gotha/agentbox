# Shared test utilities and helpers for agentbox tests
{ pkgs, self }:

{
  # Create a mock project directory as a derivation
  mkMockProject = { marker ? "flake.nix", extraFiles ? {} }:
    pkgs.runCommand "mock-project" {} ''
      mkdir -p $out/src
      echo '{ description = "Mock project"; inputs = {}; outputs = { self }: {}; }' > $out/${marker}
      echo '# Mock Project' > $out/README.md
      echo 'console.log("hello")' > $out/src/index.js
      ${builtins.concatStringsSep "\n" (
        pkgs.lib.mapAttrsToList (path: content: ''
          mkdir -p $out/$(dirname ${path})
          echo '${content}' > $out/${path}
        '') extraFiles
      )}
    '';

  # Create a mock config directory for hostShares tests
  mkMockConfig = { files ? {} }:
    pkgs.runCommand "mock-config" {} ''
      mkdir -p $out
      ${builtins.concatStringsSep "\n" (
        pkgs.lib.mapAttrsToList (path: content: ''
          mkdir -p $out/$(dirname ${path})
          echo '${content}' > $out/${path}
        '') files
      )}
    '';

  # Common test script helpers (Python snippets for testScript)
  helpers = {
    # Wait for a systemd service to complete successfully
    waitForService = service: ''
      machine.wait_for_unit("${service}.service")
    '';

    # Assert a path exists
    assertPathExists = path: ''
      machine.succeed("test -e ${path}")
    '';

    # Assert a path is a directory
    assertPathIsDirectory = path: ''
      machine.succeed("test -d ${path}")
    '';

    # Assert a path is a file
    assertPathIsFile = path: ''
      machine.succeed("test -f ${path}")
    '';

    # Assert file contains content
    assertFileContains = { path, content }: ''
      machine.succeed("grep -q '${content}' ${path}")
    '';

    # Assert user can write to path
    assertUserCanWrite = { user, path }: ''
      machine.succeed("sudo -u ${user} touch ${path}/.write-test")
      machine.succeed("rm ${path}/.write-test")
    '';

    # Assert a command exists
    assertCommandExists = cmd: ''
      machine.succeed("which ${cmd}")
    '';

    # Assert systemd service is active
    assertServiceActive = service: ''
      machine.succeed("systemctl is-active ${service}.service")
    '';

    # Assert systemd service failed or doesn't exist
    assertServiceNotActive = service: ''
      machine.succeed("! systemctl is-active ${service}.service")
    '';

    # Get service logs for debugging
    getServiceLogs = service: ''
      print(machine.succeed("journalctl -u ${service}.service --no-pager || true"))
    '';
  };
}

