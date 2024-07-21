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
    homeManagerModules.default = self.homeManagerModules.uwsm;
    homeManagerModules.uwsm = import ./nix/homeModule.nix;
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

      uwsmHyprlandTest = pkgs.nixosTest {
        name = "uwsmHyprlandTest";
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
            sddm_session = "hyprland_uwsm";
          in {
            imports = [
              inputs.home-manager.nixosModules.home-manager
              self.nixosModules.uwsm
              (import ./nix/test_builder.nix {inherit pkgs user sddm_session;})
              {
                # Default
                programs.hyprland = {
                  enable = true;
                  # systemd.setPath.enable = true;
                };
                programs.uwsm = {
                  enable = true;
                  wayland_compositors = {
                    hyprland_uwsm = {
                      compositor_name = "Hyprland (UWSM)";
                      compositor_comment = "An intelligent dynamic tiling Wayland compositor managed by UWSM.";
                      package = pkgs.hyprland;
                    };
                  };
                };
                home-manager.users.${user} = {
                  imports = [
                    self.homeManagerModules.uwsm
                    {
                      programs.uwsm = {
                        enable = true;
                        managed_wayland_compositors = ["hyprland"];
                      };
                    }
                  ];
                };
              }
            ];
          };
        };
      };
      uwsmSwayTest = pkgs.nixosTest {
        name = "uwsmSwayTest";
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
            sddm_session = "sway_uwsm";
          in {
            imports = [
              inputs.home-manager.nixosModules.home-manager
              self.nixosModules.uwsm
              (import ./nix/test_builder.nix {inherit pkgs user sddm_session;})
              {
                programs.sway.enable = true;
                programs.uwsm = {
                  enable = true;
                  wayland_compositors = {
                    sway_uwsm = {
                      compositor_name = "Sway (UWSM)";
                      compositor_comment = "Sway by UWSM.";
                      package = pkgs.sway;
                    };
                  };
                };
                home-manager.users.${user} = {
                  imports = [
                    self.homeManagerModules.uwsm
                    {
                      programs.uwsm = {
                        enable = true;
                        managed_wayland_compositors = ["sway"];
                      };
                    }
                  ];
                };
              }
            ];
          };
        };
      };
      uwsmWayfireTest = pkgs.nixosTest {
        name = "uwsmWayfireTest";
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
            sddm_session = "wayfire_uwsm";
          in {
            imports = [
              inputs.home-manager.nixosModules.home-manager
              self.nixosModules.uwsm
              (import ./nix/test_builder.nix {inherit pkgs user sddm_session;})
              {
                programs.wayfire.enable = true;
                programs.uwsm = {
                  enable = true;
                  wayland_compositors = {
                    # TODO: What happens on a conflict .desktop file?!
                    wayfire_uwsm = {
                      compositor_name = "Wayfire (UWSM)";
                      compositor_comment = "Wayfire managed by UWSM.";
                      package = pkgs.wayfire;
                    };
                  };
                };
                home-manager.users.${user} = {
                  imports = [
                    self.homeManagerModules.uwsm
                    {
                      programs.uwsm = {
                        enable = true;
                        managed_wayland_compositors = ["wayfire"];
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
