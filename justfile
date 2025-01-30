

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

