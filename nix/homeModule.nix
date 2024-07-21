{
  config,
  lib,
  pkgs,
  ...
}: let
  name = "uwsm";
  cfg = config.programs.${name};
in {
  options.programs.${name} = {
    enable = lib.mkEnableOption name;
    # not even sure if I should add this
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./uwsm.nix {};
      defaultText = lib.literalExpression "pkgs.uwsm";
      description = "The package to use for uwsm.";
    };
    # could be an attribute set with one of the three entries as names
    # and that could have an extra enable and allow for custom environment
    # variables listing.
    managed_wayland_compositors = lib.mkOption {
      description = ''
        List of UWSM managed Wayland Compositors.
        Will ensure that `uwsm finalize` is called right as the first
        command after the wayland compositor has started.
        In Hyprland terms, it will be the first `exec-once` call.
        For more information regarding `uwsm finalize` see:
        https://github.com/Vladimir-csp/uwsm?tab=readme-ov-file#2-service-startup-notification-and-vars-set-by-compositor

        Note: For now only the environment variables that are defined in the _plugins_ are exported.
      '';
      # list of enum
      type = lib.types.listOf (lib.types.enum ["hyprland" "sway" "wayfire"]);
      default = [];
    };
  };
  config = let
  in
    lib.mkIf cfg.enable {
      # warnings =
      #   if config.services.foo.bar
      #   then [ ''You have enabled the bar feature of the foo service.
      #            This is known to cause some specific problems in certain situations.
      #            '' ]
      #   else [];
      #
      wayland.windowManager = {
        hyprland = lib.mkIf (lib.any (x: x == "hyprland") cfg.managed_wayland_compositors) {
          enable = true;
          settings = {
            exec-once = lib.mkBefore [
              "uwsm finalize"
            ];
          };
        };

        sway = lib.mkIf (lib.any (x: x == "sway") cfg.managed_wayland_compositors) {
          enable = lib.mkDefault true;
          config.startup = [
            {
              command = "uwsm finalize";
              always = false; # I believe that this is correct? Maybe logging off & on to test?
            }
          ];
        };
      };
      xdg.configFile = lib.mkIf (lib.any (x: x == "wayfire") cfg.managed_wayland_compositors) {
        # assumes that this is configured via home-manager `xdg.configFile`
        # could trigger a warning if this is enabled to let the user know what is happening
        "wayfire.ini".text = lib.mkBefore ''
          [autostart]
          uwsm_finalize = uwsm finalize
        '';
      };

      # should this include the wrapped version?
      home.packages = [cfg.package];
    };
}
