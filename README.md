# [Universal Wayland Session Manager](https://github.com/Vladimir-csp/uwsm) Flake

## Installation

The project's repository provides a [NixOS](https://nixos.org/) module, making it a breeze to install
and configure:

```nix
inputs = {
  # ...your inputs
  uwsm = "github:kai-tub/uwsm-nix";
};
outputs = {
  # ...your outputs
}:
# skipping until your main config:
  imports = [
    # ... your imports
    inputs.uwsm.nixosModules.default
  ];
  # simply enable it to install it!
  # it will add a custom `desktop` entry
  # SDDM will show a new entry for each managed compositor entry 
  # like: `Hyprland (with UWSM)`
  # Please do not forget to configure each compositor to call `uwsm finalize`
  # and to enable them via `program.hyprland.enable = true`
  # See home-manager for configuring these files!
  # But note that there is no need to enable the `systemd` options as
  # these are now covered by `uwsm`
  programs.uwsm = {
    enable = true;
    wayland_compositors = {
      sway_uwsm = {
        compositor_name = "Sway (UWSM)";
        compositor_comment = "Sway by UWSM.";
        package = pkgs.sway;
      };
      hyprland_uwsm = {
        compositor_name = "Hyprland (UWSM)";
        compositor_comment = "An intelligent dynamic tiling Wayland compositor managed by UWSM.";
        package = pkgs.hyprland;
      };
      wayfire_uwsm = {
        compositor_name = "Wayfire (UWSM)";
        compositor_comment = "Wayfire managed by UWSM.";
        package = pkgs.wayfire;
      };
    };
  };
```

## Features

This flake utilizes NixOS tests to _guarantee_ that `uwsm` can successfully boot
with the latest Wayland compositors.

Either via `uwsm` from the `tty` and by directly booting via the generated desktop entry file.

### Tested Compositors

- [Hyprland](https://github.com/hyprwm/Hyprland)
- [Sway]()
- [Wayfire]()


