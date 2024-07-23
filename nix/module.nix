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
# path to the binary, which goes against the NixOS principle
# -> BUT uwsm does activate the user-environment bus and sets PATH, so maybe this isn't
# really an issue?
#
# Currently this is my "best" solution
# Pro: Clean, easy to follow, does not generate one package for each
# desktop entry that uses `uwsm`.
# Con: It 'taints' the default user session manager (but maybe uwsm overwrites it either way)
# and would be overwritten if somebody re-defines this variable (TODO: Check if this is true!)
# + there is no easy way to maintain multiple version of the same desktop environment.
# TODO: Maybe see hyprland nix discussions about this intermediate solution
# some contexts:
# - https://github.com/NixOS/nixpkgs/pull/320737
# - https://github.com/hyprwm/Hyprland/pull/6640
#
# For example, what if I have multiple Hyprland versions installed and want to test them?
# I would like to define the exact package on a module level.
# Overwrites the current PATH with `env_pre` where only the systemd_vars are kept around
# So either, I update the systemd user environment and load the PATH somehow,
# or I ensure that uwsm has the PATHs available.
# -> Only solution would be to overwrite the desktop environment to include the version number
# in the binary name and to make sure that it also sets the `sessionPackages`
# -> But then tools like `hyprctl` and others like `xwayland` also need to be carefully set + linked...
# -> Just let it be. There will be nobody that would use this feature.
# It is a rabbit hole. As not only a different version of a compositor needs
# to be installed but potentially also different portals, meta-packages etc.
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  name = "uwsm";
  cfg = config.programs.${name};
  mk_uwsm_desktop_entry = opts: let
  in (pkgs.writeTextFile {
    name = lib.traceVal "${opts.name}";
    text = let
      uwsm_pkg = cfg.package;
      # cannot use full path as uwsm doesn't allow it!
      # and also not a desktop entry
    in
      lib.traceVal ''
        [Desktop Entry]
        Name=${opts.compositor_pretty_name}
        Comment=${opts.compositor_comment}
        Exec=${uwsm_pkg} start -S -- ${opts.compositor_bin_name}
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
          compositor_pretty_name = lib.mkOption {
            type = lib.types.str;
            description = "The full name of the desktop entry file.";
            example = "Hyprland (with UWSM)";
          };
          compositor_comment = lib.mkOption {
            type = lib.types.str;
            description = "The comment field of the desktop entry file.";
            example = "An intelligent dynamic tiling Wayland compositor managed by UWSM.";
          };
          compositor_bin_name = lib.mkOption {
            type = lib.types.str;
            description = ''
              The wayland-compositor binary that will be called by UWSM.
              Important: Do NOT provide a package or full path!
              It should just be the name of the binary.
            '';
            example = "Hyprland";
          };
        };
      }));
    };
  };
  config = let
    # get_compositor_packages = attrs: lib.mapAttrsToList (_: value: value.package) attrs;
  in
    lib.mkIf cfg.enable {
      # REQUIRED by wayfire: until https://github.com/NixOS/nixpkgs/pull/322312 is merged
      # otherwise `programs.wayfire.enable = true` should suffice.
      security.polkit.enable = true;

      # If this isn't enabled, then the `providedSessions` aren't evaluated!
      # and the data-dir isn't set either!
      # This is implied in `sddm.enable = true` and was the reason why I didn't
      # see an issue in my 'graphical' tests...
      services.displayManager.enable = true;
      systemd.user.extraConfig = ''
        DefaultEnvironment="PATH=${lib.makeBinPath (
          config.services.displayManager.sessionPackages
        )}"
      '';

      # TODO: Do the tests pass even if this is disabled?
      services.dbus = lib.mkIf cfg.use_dbus_broker {
        implementation = "broker";
      };
      environment.systemPackages = let
      in [
        # Need to call the package to ensure that I can pass in the
        # options from the module
        # TODO: Check if this includes the other binaries as well!
        (pkgs.callPackage ./uwsm.nix {})
      ];
      # https://github.com/NixOS/nixpkgs/blob/0c53b6b8c2a3e46c68e04417e247bba660689c9d/nixos/modules/services/display-managers/default.nix#L188C5-L188C40
      # Here, I have realized that it will probably not work with _injecting_ the
      # path of the compositor to uwsm.
      # The issue is that the compositor packaes that are actually used are also
      # _dynamic_ and the _real_ version is stored in `sessionPackages` but
      # to add another package to `sessionPackage` that depends on another sessionPackage
      # starts a recursion
      # maybe somehow `lib.mkIf` could help
      # But at this point I switched the implementation to the `systemd.user` environment
      # solution
      services.displayManager.sessionPackages =
        lib.mapAttrsToList (
          name: value:
            mk_uwsm_desktop_entry {
              name = name;
              compositor_pretty_name = value.compositor_pretty_name;
              compositor_comment = value.compositor_comment;
              compositor_bin_name = value.compositor_bin_name;
              # package = value.package;
              # packages = get_compositor_packages cfg.wayland_compositors;
            }
        )
        cfg.wayland_compositors;
    };
}
