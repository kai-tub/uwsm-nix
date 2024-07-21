# [Universal Wayland Session Manager](https://github.com/Vladimir-csp/uwsm) Flake

## ToDo

- [x] Add homeManager module that automatically sets `uwsm finalize`
  - [ ] Raise a warning if the compositor home-manager modules have systemd options enabled
- [ ] Add tests for the other compositors
  - [ ] Include booting via `uwsm select` and `uwsm start`
  - [X] Booting via sddm and desktop entry file
  - [ ] Booting via `uwsm start select` (? maybe ?)
  - [ ] Booting one compositor, logging out, checking that logging out was successfull (this should be done for all actually) and that the other one can be booted as well
- [ ] Auto-enable `program.<compositor>` for supported ones
- [ ] Update README

There a fundamental flaw in the design.
The actual wayland packages are usually wrapped with other extensions.
See [wayfire](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/programs/wayland/wayfire.nix)
for example.

The actual packages are added to `services.displayManager.sessionPackages`.
But since I am adding the new desktop entries to `sessionPackages` as well, I cannot
combine all of them there.

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
  # Do not forget to enable them on a NixOS level via `program.hyprland.enable = true`
  # Please do not forget to configure each compositor to call `uwsm finalize`
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

This flake also provides a tiny [home-manager nix module](https://github.com/nix-community/home-manager)
that will configure the given wayland compositors to call `uwsm finalize` during start-up.

<details>
  <summary>Home-Manager Internals</summary>

  For `Hyprland` and `Sway` it simply sets `wayland.windowManager.hyprland.settings.exec-once`
  and `wayland.windowManager.sway.config.startup` respectively.

  For `Wayfire` it writes an [autostart](https://github.com/WayfireWM/wayfire/wiki/Configuration#autostart)
  section that executes the `uwsm finalize` command at the top of the file.

  I would recommend to simply check out the `homeModule.nix` file to better understand the details.
</details>

### Tested Compositors

- [Hyprland](https://github.com/hyprwm/Hyprland)
- [Sway](https://swaywm.org/)
- [Wayfire](https://wayfire.org/)


