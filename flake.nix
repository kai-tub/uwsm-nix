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
    formatter = eachSystem (system: pkgsFor.${system}.alejandra);
    checks = eachSystem (
      system: let
        pkgs = pkgsFor.${system};
        lib = pkgs.lib;
      in {
        pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            alejandra.enable = true;
            trim-trailing-whitespace.enable = true;
          };
        };
      }
    );
    packages = eachSystem (system: let
      pkgs = pkgsFor.${system};
      version = "0.17.0";
    in {
      default = pkgs.callPackage ./nix/uwsm.nix {
        inherit version;
        withHyprland = true;
      };
      uwsm-hyprland = pkgs.callPackage ./nix/uwsm.nix {
        inherit version;
        withHyprland = true;
      };
      uwsm-sway = pkgs.callPackage ./nix/uwsm.nix {
        inherit version;
        withSway = true;
      };
      uwsmTest = pkgs.nixosTest {
        name = "uwsmTest";
        testScript = ''
          start_all()

          # wait_for_unit cannot be used as it fails on 'in-active' state!
          node.wait_until_succeeds("systemctl --machine kai@ --user is-active env_checker.service", 60)
        '';
        nodes = {
          node = {
            config,
            pkgs,
            lib,
            ...
          }: let
            user = "kai";
            test-pkg = self.packages.${system}.uwsm-hyprland;
          in {
            imports = [
              inputs.home-manager.nixosModules.home-manager
              {
                boot.kernelPackages = pkgs.linuxPackages_latest;
                nixpkgs.hostPlatform = "x86_64-linux";
                users.users."${user}" = {
                  isNormalUser = true;
                  password = user;
                  uid = 1000;
                  extraGroups = ["networkmanager" "wheel"];
                };
                programs.hyprland.enable = true;
                services.dbus.implementation = "broker";
                # THIS should be externalized to a module!
                services.displayManager.sessionPackages = let
                  hyprland_uwsm-text = pkgs.writeText "hyprland_uwsm.desktop" ''
                    [Desktop Entry]
                    Name=Hyprland (with UWSM)
                    Comment=An intelligent dynamic tiling Wayland compositor managed by UWSM
                    Exec=${lib.getExe test-pkg} start -S -- hyprland.desktop
                    Type=Application
                  '';
                  hyprland_uwsm = pkgs.stdenvNoCC.mkDerivation {
                    pname = "hyprland_uwsm";
                    version = "1.0.0";
                    dontUnpack = true;
                    dontBuild = true;
                    installPhase = ''
                      mkdir -p $out/share/wayland-sessions
                      cp ${hyprland_uwsm-text} $out/share/wayland-sessions/hyprland_uwsm.desktop
                    '';
                    passthru.providedSessions = ["hyprland_uwsm"];
                  };
                in [hyprland_uwsm];

                services.displayManager.sddm = {
                  enable = true;
                  wayland = {enable = true;};
                  settings = {
                    Autologin = {
                      Session = "hyprland_uwsm";
                      User = user;
                    };
                  };
                };
                environment = {
                  systemPackages =
                    (with pkgs; [foot fuzzel dbus-broker])
                    ++ [
                      test-pkg
                    ];

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
                            "$mod, Q, exec, ${lib.getExe self.packages.${system}.default}/bin/uwsm app -- ${lib.getExe pkgs.xdg-terminal-exec}"
                          ];
                          exec-once = [
                            ''
                              ${
                                lib.getExe self.packages.${system}.default
                              } finalize ${lib.strings.escapeShellArgs dbus_environment_variables}
                            ''
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
                                  set -exu

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
