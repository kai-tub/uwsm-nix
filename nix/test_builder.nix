# FUTURE: Add additional options that should be checked!
# FUTURE: Rename to "node_base"
# Could also put the tests here to avoid splitting everything up into two
# places.
{
  pkgs,
  user,
  sddm_session,
  ...
}: {
  boot.kernelPackages = pkgs.linuxPackages_latest;
  nixpkgs.hostPlatform = "x86_64-linux";
  users.users."${user}" = {
    isNormalUser = true;
    password = user;
    uid = 1000;
    extraGroups = ["networkmanager" "wheel"];
  };
  services.displayManager.sddm = {
    enable = true; # HERE: <- Setting that to true enables the writing of the desktop files!
    wayland = {enable = true;};
    settings = {
      Autologin = {
        Session = sddm_session;
        User = user;
      };
    };
  };
  environment = {
    variables = {
      # Seems to work without any issues for me!
      # ok, calling glxinfo does report that there is an error with the
      # zink renderer but it feels like it is hardware accellerated
      "WLR_RENDERER" = "pixman";
      "WLR_RENDERER_ALLOW_SOFTWARE" = "1";
    };
  };
  virtualisation.qemu.options = ["-vga none -device virtio-gpu-pci"];
  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {inherit user pkgs;};
  home-manager.users.${user} = {
    imports = [
      {
        home.username = user;
        home.homeDirectory = "/home/${user}";
        home.stateVersion = "24.11";
        # This should set the `uwsm finalize` !
        # FUTURE: Separate this into a debugging environment!
        # wayland.windowManager.hyprland = {
        #   enable = true;
        #   systemd.enable = false;
        #   settings = let
        #     # dbus_environment_variables = [
        #     #   "WAYLAND_DISPLAY"
        #     #   "XDG_CURRENT_DESKTOP"
        #     #   "XCURSOR_THEME"
        #     #   "XCURSOR_SIZE"
        #     #   "HYPRLAND_INSTANCE_SIGNATURE"
        #     # ];
        #   in {
        #     "$mod" = lib.mkForce "CTRL";
        #     bind = [
        #       # Select the default terminal application via xdg-terminal-exec
        #       "$mod, Q, exec, ${lib.getExe self.packages.${system}.default} app -- ${lib.getExe pkgs.xdg-terminal-exec}"
        #     ];
        #   };
        # };
        systemd.user.services.env_checker = {
          Unit = {
            After = ["graphical-session.target"];
            PartOf = ["graphical-session.target"];
            Description = "Checker";
          };
          Install.WantedBy = ["graphical-session.target"];
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = let
              wrappedScript = pkgs.lib.getExe (
                pkgs.writeShellApplication {
                  name = "env-checker";
                  # echo environment variables that should be accessible if not error!
                  # FUTURE: Add a test that checks whether or not hyprland environment variables set
                  # via env NIXOS_OZONE_WL,1 work even if the env lines come _after_ the exec-once lines!
                  # echo "$NIXOS_OZONE_WL"
                  text = ''
                    set -eux

                    echo "$DISPLAY"
                    echo "$WAYLAND_DISPLAY"
                    # echo "$HYPRLAND_INSTANCE_SIGNATURE"
                    # echo "$SWAYSOCK"
                  '';
                }
              );
            in "${wrappedScript}";
          };
        };
      }
    ];
  };
}
