# Airfuel dev shell: `nix-shell` from the repo root.
{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    godot_4      # editor + runtime (4.6.x)
    gdtoolkit_4  # gdformat / gdlint for GDScript
  ];

  shellHook = ''
    echo "Airfuel devshell — godot $(godot4 --version 2>/dev/null | head -1)"
    echo "  godot4 --path game --editor   # open the project"
    echo "  godot4 --path game            # run the prototype"
  '';
}
