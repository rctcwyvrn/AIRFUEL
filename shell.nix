# Airfuel dev shell: `nix-shell` from the repo root.
#
# nixpkgs is pinned so godot_4 is exactly 4.7.2-stable — the same version the
# Dockerfile ships. Bump the pin and docker/Dockerfile's GODOT_VERSION
# together (a client/server mismatch can desync scene/rpc expectations).
{
  pkgs ? import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/a391f95d4557d685fd8e5dc0d4b1f9271aa2f342.tar.gz";
    sha256 = "0lh46fqspablqzvqk7lrsfbc7c902295mp6iwn8nv7gixawzgia0";
  }) { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    godot_4      # editor + runtime (4.7.2-stable)
    gdtoolkit_4  # gdformat / gdlint for GDScript
  ];
}
