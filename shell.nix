# Airfuel dev shell: `nix-shell` from the repo root.
{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    godot_4      # editor + runtime (4.6.x)
    gdtoolkit_4  # gdformat / gdlint for GDScript
  ];
}
