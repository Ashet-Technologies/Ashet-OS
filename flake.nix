{
  description = "AshetOS, a homebrew operating system";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      # Other overlays
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
      })
    ];

    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system;};
      in let
        caseconverter =
          pkgs.python311Packages.buildPythonPackage
          rec {
            pname = "case-converter";
            version = "1.1.0";
            format = "setuptools";

            src = pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-LtP8bj/6jWAfmjH/y8j70Z6utIZxp5qO8WOUZygkUQ4=";
            };

            # postPatch = ''
            #   # don't test bash builtins
            #   rm testing/test_argcomplete.py
            # '';

            buildInputs = [
              pkgs.python311Packages.pytest
            ];

            nativeBuildInputs = [
              pkgs.python311Packages.setuptools-scm
            ];

            # propagatedBuildInputs = [
            #   #
            # ];
          };
      in rec {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "ashet-os";
          src = ./.;
          nativeBuildInputs = [
            pkgs.zigpkgs."0.13.0"

            pkgs.qemu
            pkgs.mtools

            pkgs.gdb
            pkgs.pkg-config
            pkgs.python311

            # prebundled python packages:
            pkgs.python311Packages.lark
            pkgs.python311Packages.jinja2
            pkgs.python311Packages.dataclasses-json

            # pypi packages:
            caseconverter
          ];

          configurePhase = "";

          buildPhase = ''
            zig build
          '';

          installPhase = ''
            mv zig-out $out
          '';
        };
      }
    );
}
