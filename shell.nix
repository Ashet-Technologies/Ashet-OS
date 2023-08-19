{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.zig_0_11
    pkgs.qemu_full
    pkgs.qemu-utils
    pkgs.mtools
    pkgs.syslinux
  ];
}
