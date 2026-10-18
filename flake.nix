# SPDX-FileCopyrightText: 2024-2026 Jonas I. Liechti <j-i-l@t4d.ch>
#
# SPDX-License-Identifier: CC-BY-NC-4.0
{
  description = "contain - Sandboxed AI coding agent in a rootful Podman container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in {

    # -- NixOS module --
    nixosModules.default = import ./nix/module.nix;

    # -- Packages (the wrapped helper scripts) --
    packages = forAllSystems (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.callPackage ./nix/scripts.nix {};
      }
    );

    # -- Dev shell --
    devShells = forAllSystems (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          name = "contain-dev";
          packages = with pkgs; [
            bash
            jq
            podman
            inotify-tools
            shellcheck
          ];
        };
      }
    );
  };
}
