
zig := "zig-0.14.1"

optimize_kernel := "false"
optimize_apps := "Debug"

build:
    {{zig}} build --prominent-compile-errors -freference-trace=10 --summary none -Doptimize-kernel={{optimize_kernel}} -Doptimize-apps={{optimize_apps}} rv32-qemu-virt
    {{zig}} build --prominent-compile-errors -freference-trace=10 --summary none -Doptimize-kernel={{optimize_kernel}} -Doptimize-apps={{optimize_apps}}

[working-directory: 'src/kernel']
build-kernel:
    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=arm-ashet-hc -Dno-emit-bin

    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=arm-ashet-hc
    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=arm-ashet-vhc
    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=arm-qemu-virt
    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=rv32-qemu-virt
    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=x86-pc-generic
    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=x86-hosted-linux
    {{zig}} build --prominent-compile-errors -freference-trace=10 -Dmachine=x86-hosted-windows

[working-directory: 'src/userland/apps/wiki']
build-wiki:
    zig-ashet build -Dtarget=rv32


build-tools:
    zig-ashet build tools 

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

[working-directory: 'src/tools/mkfont']
mkfont:
    {{zig}} build

test-mkfont: \
    (test-mkfont-face "mono-6") \
    (test-mkfont-face "mono-8") \
    (test-mkfont-face "sans-6") \
    (test-mkfont-face "sans")

[working-directory: 'src/tools/mkfont']
test-mkfont-face font: mkfont
    ./zig-out/bin/mkfont -o ./zig-out/{{font}}.font ../../../assets/fonts/{{font}}/{{font}}.font.json
    hexdump -C ./zig-out/{{font}}.font
    wc -c ./zig-out/{{font}}.font

[working-directory: 'src/tools/mkicon']
mkicon:
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
    {{zig}} build -Doptimize-kernel -Dmachine=arm-ashet-hc tools install 
    llvm-size zig-out/arm-ashet-hc/kernel.elf

    ./zig-out/bin/elfstack zig-out/arm-ashet-hc/kernel.elf > zig-out/arm-ashet-hc/kernel.elfstack.svg

    arm-none-eabi-objdump -dS zig-out/arm-ashet-hc/kernel.elf  > zig-out/arm-ashet-hc/kernel.S

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

rp2350-launch:  openocd-bootloader rp2350-flash 

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
    ./zig-out/bin/debug-filter \
        --elf kernel=zig-out/arm-ashet-hc/kernel.elf \
        --elf ntp-client.ashex=zig-out/arm-ashet-hc/apps/ntp-client.elf \
        picocom --quiet --baud 2000000 /dev/ashet.com1

qemu-gdb target:
    arm-none-eabi-gdb \
        --command "scripts/gdb" \
        zig-out/{{target}}/kernel.elf 

cmd_bootloader := "adapter speed 12000
    init
    reset halt
    rp2xxx rom_api_call RB 2
    resume
    exit"
openocd-bootloader:
    openocd -s tcl \
        -f interface/cmsis-dap.cfg \
        -f target/rp2350.cfg \
        -c '{{cmd_bootloader}}'
    sleep 0.5