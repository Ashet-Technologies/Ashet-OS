{
  description = "AshetOS, a homebrew operating system";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    let
      overlays = [
        # Other overlays
        (final: prev: { zigpkgs = inputs.zig.packages.${prev.system}; })
      ];

      # Our supported systems are the same supported systems as the Zig binaries
      systems = builtins.attrNames inputs.zig.packages;
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs { inherit overlays system; };
      in
      rec {
        formatter = pkgs.nixfmt-rfc-style;

        packages = {
          default = pkgs.stdenv.mkDerivation {
            name = "ashet-os";
            src = ./.;
            nativeBuildInputs = [
              pkgs.zigpkgs."0.14.0"

              pkgs.qemu
              pkgs.llvmPackages_17.bintools
              pkgs.clang-tools

              pkgs.gdb
              pkgs.pkg-config
              pkgs.python311
              pkgs.graphviz
            ];

            buildInputs = [ nixpkgs.legacyPackages.i686-linux.SDL2 ];

            configurePhase = "";
            buildPhase = "";
            installPhase = "";
          };

          zig-master = pkgs.stdenv.mkDerivation {
            name = "ashet-os";
            src = ./.;
            nativeBuildInputs = [
              pkgs.zigpkgs.master

              pkgs.qemu
              pkgs.llvmPackages_17.bintools
              pkgs.clang-tools

              pkgs.gdb
              pkgs.pkg-config
              pkgs.python311
              pkgs.graphviz
            ];

            buildInputs = [ nixpkgs.legacyPackages.i686-linux.SDL2 ];

            configurePhase = "";
            buildPhase = "";
            installPhase = "";
          };
        };
      }
    );
}
