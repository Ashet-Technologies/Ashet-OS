from stat import S_IEXEC
from argparse import ArgumentParser
from pathlib import Path 
from enum import StrEnum 

class HostOs(StrEnum):
    freestanding = "freestanding"
    ananas = "ananas"
    cloudabi = "cloudabi"
    dragonfly = "dragonfly"
    freebsd = "freebsd"
    fuchsia = "fuchsia"
    ios = "ios"
    kfreebsd = "kfreebsd"
    linux = "linux"
    lv2 = "lv2"
    macos = "macos"
    netbsd = "netbsd"
    openbsd = "openbsd"
    solaris = "solaris"
    uefi = "uefi"
    windows = "windows"
    zos = "zos"
    haiku = "haiku"
    minix = "minix"
    rtems = "rtems"
    nacl = "nacl"
    aix = "aix"
    cuda = "cuda"
    nvcl = "nvcl"
    amdhsa = "amdhsa"
    ps4 = "ps4"
    ps5 = "ps5"
    elfiamcu = "elfiamcu"
    tvos = "tvos"
    watchos = "watchos"
    driverkit = "driverkit"
    visionos = "visionos"
    mesa3d = "mesa3d"
    contiki = "contiki"
    amdpal = "amdpal"
    hermit = "hermit"
    hurd = "hurd"
    wasi = "wasi"
    emscripten = "emscripten"
    shadermodel = "shadermodel"
    liteos = "liteos"
    serenity = "serenity"
    opencl = "opencl"
    glsl450 = "glsl450"
    vulkan = "vulkan"
    plan9 = "plan9"
    illumos = "illumos"
    other = "other"

def main():

    cli_parser = ArgumentParser()
    cli_parser.add_argument(
        "--interpreter",
        type=Path,
        required=True,
    )
    cli_parser.add_argument(
        "--script",
        type=Path,
        required=True,
    )
    cli_parser.add_argument(
        "--output",
        type=Path,
        required=True,
    )
    cli_parser.add_argument(
        "--host",
        type=HostOs,
        required=True,
    )

    cli = cli_parser.parse_args()

    interpreter: Path = cli.interpreter
    python_script: Path = cli.script
    output: Path = cli.output
    host: HostOs = cli.host

    script_code: str

    if host == HostOs.windows:
        assert False, "Not implemented yet. Create a batch script here!"
    else:

        script_code = f"""#!/bin/sh
"{interpreter}" "{python_script}" "$@"
"""

    output.write_text(script_code, encoding='utf-8')

    if host != HostOs.windows:
        stat = output.stat()
        output.chmod( stat.st_mode | S_IEXEC)
    

if __name__ == "__main__":
    main()