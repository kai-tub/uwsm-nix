{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/x86_64-linux";
    nix-filter.url = "github:numtide/nix-filter";
    devshell.url = "github:numtide/devshell";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      # url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    systems,
    devshell,
    ...
  } @ inputs: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
    pkgsFor = eachSystem (system: (nixpkgs.legacyPackages.${system}.extend devshell.overlays.default));
  in {
    nixosModules.uwsm = import ./nix/module.nix;
    nixosModules.default = self.nixosModules.uwsm;
    formatter = eachSystem (system: pkgsFor.${system}.nixfmt);
    checks = eachSystem (
      system: let
        pkgs = pkgsFor.${system};
        lib = pkgs.lib;
      in {
        pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt.enable = true;
            trim-trailing-whitespace.enable = true;
          };
        };
      }
    );
    packages = eachSystem (system: let
      pkgs = pkgsFor.${system};
    in {
      default = self.packages.${system}.uwsm-hyprland;
      uwsm-hyprland =
        pkgs.callPackage ./nix/uwsm.nix {wayland-compositors = [pkgs.hyprland];};

      uwsmTest = pkgs.nixosTest {
        name = "uwsmTest";
        testScript = ''
          start_all()

          # wait_for_unit cannot be used as it fails on 'in-active' state!
          node.wait_until_succeeds("systemctl --machine kai@ --user is-active env_checker.service", 60)
        '';
        nodes = {
          node = {
            pkgs,
            lib,
            ...
          }: let
            user = "kai";
          in {
            imports = [
              inputs.home-manager.nixosModules.home-manager
              self.nixosModules.uwsm
              {
                boot.kernelPackages = pkgs.linuxPackages_latest;
                nixpkgs.hostPlatform = "x86_64-linux";
                users.users."${user}" = {
                  isNormalUser = true;
                  password = user;
                  uid = 1000;
                  extraGroups = ["networkmanager" "wheel"];
                };
                programs.hyprland = {
                  enable = true;
                  # systemd.setPath.enable = true;
                };
                programs.sway.enable = true;
                programs.wayfire.enable = true;
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
                    # TODO: What happens on a conflict .desktop file?!
                    wayfire_uwsm = {
                      compositor_name = "Wayfire (UWSM)";
                      compositor_comment = "Wayfire managed by UWSM.";
                      package = pkgs.wayfire;
                    };
                  };
                };
                services.displayManager.sddm = {
                  enable = true; # HERE: <- Setting that to true enables the writing of the desktop files!
                  wayland = {enable = true;};
                  settings = {
                    Autologin = {
                      Session = "hyprland_uwsm";
                      User = user;
                    };
                  };
                };
                environment = {
                  systemPackages = with pkgs; [foot fuzzel dbus-broker];

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
                home-manager.extraSpecialArgs = {inherit user inputs pkgs;};

                home-manager.users.${user} = {
                  home.username = user;
                  home.homeDirectory = "/home/${user}";
                  imports = [
                    {
                      home.stateVersion = "24.11";
                      wayland.windowManager.hyprland = {
                        enable = true;
                        systemd.enable = false;
                        settings = let
                          dbus_environment_variables = [
                            "WAYLAND_DISPLAY"
                            "XDG_CURRENT_DESKTOP"
                            "XCURSOR_THEME"
                            "XCURSOR_SIZE"
                            "HYPRLAND_INSTANCE_SIGNATURE"
                          ];
                        in {
                          "$mod" = lib.mkForce "CTRL";
                          bind = [
                            # Select the default terminal application via xdg-terminal-exec
                            "$mod, Q, exec, ${lib.getExe self.packages.${system}.default} app -- ${lib.getExe pkgs.xdg-terminal-exec}"
                          ];
                          exec-once = [
                            "uwsm finalize"
                          ];
                        };
                      };
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
                            wrappedScript = lib.getExe (
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
                                  echo "$HYPRLAND_INSTANCE_SIGNATURE"
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
            ];
          };
        };
      };
    });
  };
}
