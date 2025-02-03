

build:
    zig-ashet build

build-vhc:
    rm -rf zig-out/arm-ashet-vhc
    zig-ashet build --summary none -Doptimize-apps=ReleaseSmall arm-ashet-vhc
    ./src/tools/exe-tool/zig-out/bin/ashet-exe dump zig-out/arm-ashet-vhc/apps/init.ashex -a > /tmp/init.ashex.txt
    ( \
        readelf --dynamic --section-headers --program-headers --wide --relocs --symbols --dyn-syms zig-out/arm-ashet-vhc/apps/init.elf ; \
        llvm-objdump -d zig-out/arm-ashet-vhc/apps/init.elf \
    ) > /tmp/dump.txt

run-vhc: build-vhc
    zig-ashet build --summary none -Dmachine=arm-ashet-vhc -Doptimize-apps=ReleaseSmall install run

debug-vhc: build-vhc
    zig-ashet build --summary none -Dmachine=arm-ashet-vhc -Doptimize-apps=ReleaseSmall install run -- -S ; stty sane

[working-directory: 'src/tools/exe-tool']
exe-tool:
    zig-ashet build

dump-libashet: \
    (dump-libashet-target "arm") \
    (dump-libashet-target "x86") \
    (dump-libashet-target "rv32")

[working-directory: 'src/userland/libs/libAshetOS']
dump-libashet-target target:
    zig-ashet build -Dtarget={{target}} install debug
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
    zig-ashet build -Dtarget={{target}} install

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
    zig build-exe -target x86-linux-musl -O ReleaseSmall -fno-strip -lc --name farcall farcall.S
    llvm-objdump -d ./farcall | grep -F '<main>' -A20
    gdb ./farcall -ex 'break main' -ex 'run'
