
zig := "zig-0.14.1"

optimize_kernel := "false"
optimize_apps := "Debug"

default_params := "--prominent-compile-errors -freference-trace=10"

DEBUG_PORT := "/dev/waveshare-BCD6EEABCD.0"

build:
    {{zig}} build {{default_params}} --summary none -Doptimize-kernel={{optimize_kernel}} -Doptimize-apps={{optimize_apps}} rv32-qemu-virt
    {{zig}} build {{default_params}} --summary none -Doptimize-kernel={{optimize_kernel}} -Doptimize-apps={{optimize_apps}}

[working-directory: 'src/kernel']
build-kernel:
    {{zig}} build {{default_params}} -Dmachine=arm-ashet-hc -Dno-emit-bin

    {{zig}} build {{default_params}} -Dmachine=arm-ashet-hc
    {{zig}} build {{default_params}} -Dmachine=arm-ashet-vhc
    {{zig}} build {{default_params}} -Dmachine=arm-qemu-virt
    {{zig}} build {{default_params}} -Dmachine=rv32-qemu-virt
    {{zig}} build {{default_params}} -Dmachine=x86-pc-generic
    {{zig}} build {{default_params}} -Dmachine=x86-hosted-linux
    {{zig}} build {{default_params}} -Dmachine=x86-hosted-windows

[working-directory: 'src/userland/apps/wiki']
build-wiki:
    {{zig}} build -Dtarget=rv32

[working-directory: 'src/abi']
abi-test:
    {{zig}} build test

[working-directory: 'src/tools/debug-filter']
debug-filter:
    echo "building..."
    {{zig}} build install test
    
    echo "testing..."
    ./zig-out/bin/debug-filter --elf main=../../../zig-out/bin/sermon echo 'main:0x0106da60'
    ./zig-out/bin/debug-filter --elf main=../../../zig-out/bin/sermon echo 'main:0x01071a90'
    ./zig-out/bin/debug-filter --elf main=../../../zig-out/bin/elfstack echo 'main:0x0112f550'
    ./zig-out/bin/debug-filter --elf i2c=../../../zig-out/arm-ashet-hc/apps/i2c-scan.elf echo 'i2c:0x0002013d' # definition.io.i2c.open
    ./zig-out/bin/debug-filter --elf i2c=../../../zig-out/arm-ashet-hc/apps/i2c-scan.elf echo 'i2c:0x00049bb8' # std.options
    ./zig-out/bin/debug-filter --elf i2c=../../../zig-out/arm-ashet-hc/apps/i2c-scan.elf echo 'i2c:0x0004e754' # builtin.target
    ./zig-out/bin/debug-filter --elf i2c=../../../zig-out/arm-ashet-hc/apps/i2c-scan.elf echo 'i2c:0x0004ea93' # builtin.target
    ./zig-out/bin/debug-filter \
        --elf one=../../../zig-out/bin/sermon \
        --elf two=../../../zig-out/bin/elfstack \
        echo -e 'one:0x0106da60' '\n' 'two:0x0112f550'
    ./zig-out/bin/debug-filter \
        --elf one=../../../zig-out/bin/sermon \
        --elf two=../../../zig-out/bin/elfstack \
        --elf i2c=../../../zig-out/arm-ashet-hc/apps/i2c-scan.elf \
        echo -e 'one:0x0106da60' '\n' 'two:0x0112f550' '\n' 'i2c:0x0002013d' '\n' 'i2c:0x00049bb8'

build-tools:
    {{zig}} build {{default_params}} tools 

build-vhc:
    rm -rf zig-out/arm-ashet-vhc
    {{zig}} build {{default_params}} --summary none -Doptimize-apps=ReleaseSmall arm-ashet-vhc
    ./src/tools/exe-tool/zig-out/bin/ashet-exe dump zig-out/arm-ashet-vhc/apps/init.ashex -a > /tmp/init.ashex.txt
    ( \
        readelf --dynamic --section-headers --program-headers --wide --relocs --symbols --dyn-syms zig-out/arm-ashet-vhc/apps/init.elf ; \
        llvm-objdump -d zig-out/arm-ashet-vhc/apps/init.elf \
    ) > /tmp/dump.txt

run-vhc: build-vhc
    {{zig}} build {{default_params}} --summary none -Dmachine=arm-ashet-vhc -Doptimize-apps=ReleaseSmall install run

debug-vhc: build-vhc
    {{zig}} build {{default_params}} --summary none -Dmachine=arm-ashet-vhc -Doptimize-apps=ReleaseSmall install run -- -S ; stty sane

[working-directory: 'src/tools/exe-tool']
exe-tool:
    {{zig}} build {{default_params}}

[working-directory: 'src/tools/mkfont']
mkfont:
    {{zig}} build {{default_params}}

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
    {{zig}} build {{default_params}}

dump-libashet: \
    (dump-libashet-target "arm") \
    (dump-libashet-target "x86") \
    (dump-libashet-target "rv32")

[working-directory: 'src/userland/libs/libAshetOS']
dump-libashet-target target:
    {{zig}} build {{default_params}} -Dtarget={{target}} install debug
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
    {{zig}} build {{default_params}} -Dtarget={{target}} install

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

[working-directory: 'src/tools/mkexp']
mkexp:
    {{zig}} build {{default_params}}
    ./zig-out/bin/mkexp render-md
    ./zig-out/bin/mkexp encode examples/quad-ps2.json | hexdump -C



rp2350-build:
    {{zig}} build {{default_params}} -Doptimize-kernel -Dmachine=arm-ashet-hc tools install 
    llvm-size zig-out/arm-ashet-hc/kernel.elf

    ./zig-out/bin/elfstack zig-out/arm-ashet-hc/kernel.elf > zig-out/arm-ashet-hc/kernel.elfstack.svg

    arm-none-eabi-objdump -phdS zig-out/arm-ashet-hc/kernel.elf  > zig-out/arm-ashet-hc/kernel.S

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
    arm-none-eabi-gdb \
        --batch \
        --command scripts/gdb-flash-rp2350 \
        zig-out/arm-ashet-hc/kernel.elf
# openocd -s tcl \
#     -f interface/cmsis-dap.cfg \
#     -f target/rp2350.cfg \
#     -c 'adapter speed 5000' \
#     -c "program zig-out/arm-ashet-hc/kernel.elf verify reset exit"

rp2350-openocd:
    openocd -s tcl \
        -f interface/cmsis-dap.cfg \
        -f target/rp2350.cfg \
        -c 'adapter speed 12000'


rp2350-reset:
    openocd -s tcl \
        -f interface/cmsis-dap.cfg \
        -f target/rp2350.cfg \
        -c 'adapter speed 5000' \
        -c 'init' \
        -c 'reset halt' \
        -c 'reset run' \
        -c 'exit'

rp2350-gdb:
    arm-none-eabi-gdb \
        -ex 'set pagination off' \
        --command "scripts/gdb-rp2350" \
        zig-out/arm-ashet-hc/kernel.elf 

rp2350-monitor:
    ./zig-out/bin/debug-filter \
        --elf kernel=zig-out/arm-ashet-hc/kernel.elf \
        --elf ntp-client.ashex=zig-out/arm-ashet-hc/apps/ntp-client.elf \
        --elf i2c-scan.ashex=zig-out/arm-ashet-hc/apps/i2c-scan.elf \
        ./zig-out/bin/sermon --baud 2000000 {{DEBUG_PORT}}

# arm-none-eabi-gdb \
qemu-gdb target:
    riscv32-elf-gdb \
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

