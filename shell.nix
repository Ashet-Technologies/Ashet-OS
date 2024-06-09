{pkgs ? import <nixpkgs> {}}: let
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
in
  pkgs.mkShell {
    nativeBuildInputs = [
      pkgs.zig_0_11
      pkgs.qemu
      #    pkgs.qemu-utils
      pkgs.mtools
      pkgs.syslinux
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
    buildInputs = [
      pkgs.pkgsi686Linux.SDL2
    ];
  }
