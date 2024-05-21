{pkgs ? import <nixpkgs> {}}:
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
    pkgs.python311Packages.lark
    pkgs.python311Packages.dataclasses-json
  ];
  buildInputs = [
    pkgs.pkgsi686Linux.SDL2
  ];
}
