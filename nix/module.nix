# According to uwsm documentation:
# > It should not launch a desktop entry, only an executable.
# So I should NOT call the `hyprland.desktop` file but the
# activated hyprland package.
# https://github.com/Vladimir-csp/uwsm/issues/35
# Should default to config.programs.hyprland.package
# -> No! uwsm does NOT want to start if one provides a full path!
# Setting `programs.hyprland.systemd.setPath.enable = true` fixes
# the issue, as it updates the default environment of the systemd user units
# to include the PATHs of the given user. I do _not_ like this approach as
# it may lead to people carelessly writing user units without providing the full
# path to the binary, which goes against the NixOS principle.
# For example, what if I have multiple Hyprland versions installed and want to test them?
# I would like to define the exact package on a module level.
# Overwrites the current PATH with `env_pre` where only the systemd_vars are kept around
# So either, I update the systemd user environment and load the PATH somehow,
# or I ensure that uwsm has the PATHs available.
#
# TODO: Remember to set an option to run `uwsm finalize` !
# could be an attribute set where the user defines
# <name>, which will become the <name>.desktop name
# Name, Comment (for desktop entry)
# Compositor-Package -> The main binary could be extracted from getExe
# which would then be used in `Exec` of desktop entry
# And the package itself would be added to the list of supported desktop entries
# -> Would this work for multiple different versions of the same DE ?
# Not with the same uwsm package. No wait, if the package ONLY contains a SINGLE
# DE, as it may be overwritten inside of these calls, then it SHOULD be possible
# to test out multiple versions!
# The only oddity would be that multiple versions of uwsm are added to the PATH
# and that the first uwsm in the PATH might not contain the PATH to the compositor
# BUT after booting, the path to the wayland compositor shouldn't be necessary anymore.
# So even if this is a bit ugly, it should work just fine.
#
# But how do I handle it when somebody wants to use uwsm select?
# does it still correctly load the desktop entry as is?
{
  config,
  lib,
  pkgs,
  ...
}: let
  name = "uwsm";
  cfg = config.programs.${name};
  mk_uwsm_desktop_entry = opts: let
    # HERE: Yes, it looks like disabling the wayland-compositor option has NO
    # effect on the output! I am quite convinced
    # that at least for `uwsm start select` the only important thing is that the
    # package is available globally. Hmm. Maybe only the desktop ID entry is relevant...
    # No, at least not for SDDM. There I do need the PATH to boot and auto-boot
    # Ok, so starting it with `uwsm start sway` does not work, as it is again missing in the PATH
    # which is what I initially expected
    # No wait. It does work when the specific `_uwsm` file is loaded.
    # So maybe it does actually start the correct binary
    # I really cannot decipher the code...
    # A possible solution would be to join all packages together for the "main"
    # uwsm executable. Then that one should work in all instances.
    # The specialized uwsm desktop entries can be left the way they are.
    # If there are multiple versions of the same compositor, then my approach
    # should still work
    # -> Just let it be. There will be nobody that would use this feature.
    # It is a rabbit hole. As not only a different version of a compositor needs
    # to be installed but potentially also different portals, meta-packages etc.
    new_pkg = cfg.package.override {wayland-compositors = opts.packages;};
    # new_pkg = cfg.package.override {};
  in (pkgs.writeTextFile {
    name = lib.traceVal "${opts.name}";
    text = let
      uwsm_pkg = lib.getExe new_pkg;
      # cannot use full path as uwsm doesn't allow it!
      # and also not a desktop entry
      binary_name = opts.package.meta.mainProgram;
    in
      lib.traceVal ''
        [Desktop Entry]
        Name=${opts.entry_name}
        Comment=${opts.comment}
        Exec=${uwsm_pkg} start -S -- ${binary_name}
        Type=Application
      '';
    destination = "/share/wayland-sessions/${opts.name}.desktop";
    derivationArgs = {
      passthru.providedSessions = ["${opts.name}"];
    };
  });
in {
  options.programs.${name} = {
    enable = lib.mkEnableOption name;
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./uwsm.nix {};
      defaultText = lib.literalExpression "pkgs.uwsm";
      description = "The package to use for uwsm.";
    };
    use_dbus_broker = lib.mkOption {
      default = true;
      example = "false";
      description = ''
        It is highly recommended to use [dbus-broker](https://github.com/bus1/dbus-broker)
        as the D-Bus daemon implementation as it reuses the systemd activation environment.
      '';
    };
    wayland_compositors = lib.mkOption {
      description = ''
        Configuration for UWSM-managed Wayland Compositors.
      '';
      type = lib.types.attrsOf (lib.types.submodule ({...}: {
        options = {
          # name,
          # Name, Comment (for desktop entry)
          # Compositor-Package -> The main binary could be extracted from getExe
          # which would then be used in `Exec` of desktop entry
          compositor_name = lib.mkOption {
            type = lib.types.str;
            description = "The full name of the desktop entry file.";
            example = "Hyprland (with UWSM)";
          };
          compositor_comment = lib.mkOption {
            type = lib.types.str;
            description = "The comment field of the desktop entry file.";
            example = "An intelligent dynamic tiling Wayland compositor managed by UWSM.";
          };
          package = lib.mkOption {
            type = lib.types.package;
            description = "The wayland-compositor that will be called by UWSM.";
          };
        };
      }));
    };
  };
  config = let
    # example =
    #   mk_uwsm_desktop_entry
    #   {
    #     name = "hyprland_uwsm";
    #     entry_name = "Hyprland (with UWSM)";
    #     comment = "An intelligent dynamic tiling Wayland compositor managed by UWSM.";
    #     package = pkgs.hyprland;
    #   };
    get_compositor_packages = attrs: lib.mapAttrsToList (_: value: value.package) attrs;
  in
    lib.mkIf cfg.enable {
      # services.displayManager.sessionPackages = [example];

      # If this isn't enabled, then the `providedSessions` aren't evaluated!
      # and the data-dir isn't set either!
      # This is implied in `sddm.enable = true` and was the reason why I didn't
      # see an issue in my 'graphical' tests...
      services.displayManager.enable = true;

      # TODO: Do the tests pass even if this is disabled?
      services.dbus = lib.mkIf cfg.use_dbus_broker {
        implementation = "broker";
      };
      # services.dbus.implementation = lib.mkDefault "broker";
      environment.systemPackages = let
      in [
        # Need to call the package to ensure that I can pass in the
        # options from the module
        # TODO: Check if this includes the other binaries as well!
        # (pkgs.callPackage ./uwsm.nix {wayland-compositors = get_compositor_packages cfg.wayland_compositors;})
        (pkgs.callPackage ./uwsm.nix {wayland-compositors = get_compositor_packages cfg.wayland_compositors;})
      ];
      services.displayManager.sessionPackages =
        lib.mapAttrsToList (
          name: value:
            mk_uwsm_desktop_entry {
              name = name;
              entry_name = value.compositor_name;
              comment = value.compositor_comment;
              package = value.package;
              packages = get_compositor_packages cfg.wayland_compositors;
            }
        )
        cfg.wayland_compositors;
    };
}
