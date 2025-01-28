const MemoryRange = struct {
    offset: u32,
    end: u32,
    name: []const u8,
};

pub const rom: MemoryRange = .{ .offset = 0x00000000, .end = 0x00ffffff, .name = "alias RP2350.xip0.alias @RP2350.xip0.flash" };
pub const xip0_flash: MemoryRange = .{ .offset = 0x10000000, .end = 0x10ffffff, .name = "RP2350.xip0.flash" };
pub const xip1_psram: MemoryRange = .{ .offset = 0x11000000, .end = 0x11ffffff, .name = "RP2350.xip1.psram" };
pub const sram: MemoryRange = .{ .offset = 0x20000000, .end = 0x20081fff, .name = "RP2350.sram" };
pub const uart0: MemoryRange = .{ .offset = 0x40070000, .end = 0x4007001f, .name = "serial" };
pub const uart1: MemoryRange = .{ .offset = 0x40078000, .end = 0x4007801f, .name = "serial" };
pub const spi0: MemoryRange = .{ .offset = 0x40080000, .end = 0x40080fff, .name = "pl022" };
pub const spi1: MemoryRange = .{ .offset = 0x40088000, .end = 0x40088fff, .name = "pl022" };
pub const virtio0: MemoryRange = .{ .offset = 0x60000000, .end = 0x600001ff, .name = "virtio-mmio" };
pub const virtio1: MemoryRange = .{ .offset = 0x60000200, .end = 0x600003ff, .name = "virtio-mmio" };
pub const virtio2: MemoryRange = .{ .offset = 0x60000400, .end = 0x600005ff, .name = "virtio-mmio" };
pub const virtio3: MemoryRange = .{ .offset = 0x60000600, .end = 0x600007ff, .name = "virtio-mmio" };
pub const virtio4: MemoryRange = .{ .offset = 0x60000800, .end = 0x600009ff, .name = "virtio-mmio" };
pub const virtio5: MemoryRange = .{ .offset = 0x60000a00, .end = 0x60000bff, .name = "virtio-mmio" };
pub const virtio6: MemoryRange = .{ .offset = 0x60000c00, .end = 0x60000dff, .name = "virtio-mmio" };
pub const virtio7: MemoryRange = .{ .offset = 0x60000e00, .end = 0x60000fff, .name = "virtio-mmio" };
pub const goldfish: MemoryRange = .{ .offset = 0x70100000, .end = 0x70100023, .name = "goldfish_rtc" };
pub const sifive_test: MemoryRange = .{ .offset = 0x70200000, .end = 0x70200fff, .name = "riscv.sifive.test" };
pub const nvic_default: MemoryRange = .{ .offset = 0xe0000000, .end = 0xe00fffff, .name = "nvic-default" };
pub const nvic_sysregs: MemoryRange = .{ .offset = 0xe000e000, .end = 0xe000efff, .name = "nvic_sysregs" };
pub const systick: MemoryRange = .{ .offset = 0xe000e010, .end = 0xe000e0ef, .name = "v7m_systick" };
pub const nvic_sysregs_ns: MemoryRange = .{ .offset = 0xe002e000, .end = 0xe002efff, .name = "nvic_sysregs_ns" };
pub const systick_ns: MemoryRange = .{ .offset = 0xe002e010, .end = 0xe002e0ef, .name = "v7m_systick_ns" };
