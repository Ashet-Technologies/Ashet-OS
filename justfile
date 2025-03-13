
# for 0.13, we need zig-ashet, which is the fork
# for 0.14, we need at least 0.14.0-dev.3213+53216d2f2
zig := "zig-0.14.0"

optimize_kernel := "false"
optimize_apps := "Debug"

build:
    {{zig}} build --summary none -Doptimize-kernel={{optimize_kernel}} -Doptimize-apps={{optimize_apps}}

[working-directory: 'src/kernel']
build-kernel:
    {{zig}} build -Dmachine=arm-ashet-hc
    {{zig}} build -Dmachine=arm-ashet-vhc
    {{zig}} build -Dmachine=arm-qemu-virt
    {{zig}} build -Dmachine=rv32-qemu-virt
    {{zig}} build -Dmachine=x86-pc-bios
    {{zig}} build -Dmachine=x86-hosted-linux

build-vhc:
    rm -rf zig-out/arm-ashet-vhc
    {{zig}} build --summary none -Doptimize-apps=ReleaseSmall arm-ashet-vhc
    ./src/tools/exe-tool/zig-out/bin/ashet-exe dump zig-out/arm-ashet-vhc/apps/init.ashex -a > /tmp/init.ashex.txt
    ( \
        readelf --dynamic --section-headers --program-headers --wide --relocs --symbols --dyn-syms zig-out/arm-ashet-vhc/apps/init.elf ; \
        llvm-objdump -d zig-out/arm-ashet-vhc/apps/init.elf \
    ) > /tmp/dump.txt

run-vhc: build-vhc
    {{zig}} build --summary none -Dmachine=arm-ashet-vhc -Doptimize-apps=ReleaseSmall install run

debug-vhc: build-vhc
    {{zig}} build --summary none -Dmachine=arm-ashet-vhc -Doptimize-apps=ReleaseSmall install run -- -S ; stty sane

[working-directory: 'src/tools/exe-tool']
exe-tool:
    {{zig}} build

dump-libashet: \
    (dump-libashet-target "arm") \
    (dump-libashet-target "x86") \
    (dump-libashet-target "rv32")

[working-directory: 'src/userland/libs/libAshetOS']
dump-libashet-target target:
    {{zig}} build -Dtarget={{target}} install debug
    llvm-readelf --dynamic \
        --section-headers \
        --program-headers \
        --wide \
        --relocs \
        --symbols \
        --dyn-syms \
        --hex-dump=.ashet.patch \
        --hex-dump=.ashet.strings \
        --string-dump=.ashet.strings \
        zig-out/bin/libAshetOS.{{target}} \
        > /tmp/libashet.{{target}}.txt
    llvm-objdump -d \
        --wide \
        zig-out/bin/libAshetOS.{{target}} \
        >> /tmp/libashet.{{target}}.txt

dump-init: \
    (dump-init-target "arm") \
    (dump-init-target "x86") \
    (dump-init-target "rv32")

[working-directory: 'src/userland/apps/init']
dump-init-target target: (dump-libashet-target target) exe-tool
    {{zig}} build -Dtarget={{target}} install

    llvm-readelf --dynamic \
        --section-headers \
        --program-headers \
        --wide \
        --relocs \
        --symbols \
        --dyn-syms \
        --hex-dump=.ashet.patch \
        --hex-dump=.ashet.strings \
        --string-dump=.ashet.strings \
        zig-out/bin/init \
        > /tmp/init.elf.{{target}}.txt
    llvm-objdump -d \
        --wide \
        zig-out/bin/init \
        >> /tmp/init.elf.{{target}}.txt
    
    ../../../tools/exe-tool/zig-out/bin/ashet-exe dump \
        --all \
        zig-out/apps/init.ashex  \
        > /tmp/init.ashex.{{target}}.txt
    
    @printf "\n  %s output:\n  |- %s\n  '- %s\n\n" \
        "{{target}}" \
        "/tmp/init.elf.{{target}}.txt" \
        "/tmp/init.ashex.{{target}}.txt"

[working-directory: 'research/x86-farcall']
farcall:
    {{zig}} build-exe -target x86-linux-musl -O ReleaseSmall -fno-strip -lc --name farcall farcall.S
    llvm-objdump -d ./farcall | grep -F '<main>' -A20
    gdb ./farcall --quiet --command ./gdbscript



rp2350-build:
    {{zig}} build -Doptimize-kernel arm-ashet-hc
    llvm-size zig-out/arm-ashet-hc/kernel.elf
    arm-none-eabi-objdump -dS zig-out/arm-ashet-hc/kernel.elf  > /tmp/arm-ashet-hc.S

    # convert kernel image to UF2 file, family=rp2350_arm_s, offset=0M
    picotool uf2 convert \
        --family 0xe48bff59 \
        --offset 0x10000000 \
        zig-out/arm-ashet-hc/kernel.elf \
        zig-out/arm-ashet-hc/kernel.uf2 \
        --verbose

    # convert disk image to UF2 file, family=data, offset=8M
    picotool uf2 convert \
        --family 0xe48bff58 \
        --offset 0x10800000 \
        zig-out/arm-ashet-hc/disk.img -t bin \
        zig-out/arm-ashet-hc/disk.uf2 \
        --verbose

rp2350-flash: rp2350-build
    picotool load \
        --family 0xe48bff59 \
        --update \
        --verify \
        --execute \
        zig-out/arm-ashet-hc/kernel.uf2

rp2350-upload-fs: rp2350-build
    picotool load \
        --update \
        --verify \
        zig-out/arm-ashet-hc/disk.uf2

rp2350-load: rp2350-build
    openocd -s tcl \
        -f interface/cmsis-dap.cfg \
        -f target/rp2350.cfg \
        -c 'adapter speed 5000' \
        -c "program zig-out/arm-ashet-hc/kernel.elf verify reset exit"

rp2350-openocd:
    openocd -s tcl \
        -f interface/cmsis-dap.cfg \
        -f target/rp2350.cfg \
        -c 'adapter speed 5000'

rp2350-gdb:
    gdb \
        --command "scripts/gdb-rp2350" \
        zig-out/arm-ashet-hc/kernel.elf 

rp2350-monitor:
    picocom --baud 115200 --quiet /dev/ttyUSB0

qemu-gdb target:
    gdb \
        --command "scripts/gdb" \
        zig-out/{{target}}/kernel.elf 