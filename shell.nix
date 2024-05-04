{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.zig_0_11
    pkgs.qemu
    pkgs.qemu-utils
    pkgs.mtools
    pkgs.syslinux
    # pkgs.llvmPackages_16.bintools
    pkgs.gdb
    pkgs.pkg-config
    # pkgs.gcc-arm-embedded
  ];
  buildInputs = [
    pkgs.SDL2
  ];
}
