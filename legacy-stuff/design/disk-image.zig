const std = @import("std");

pub const Disk = struct {
    path: []const u8,
    format: Contents,
};

pub const Contents = union(enum) {
    uninitialized,

    mbr: MbrTable,
    gpt: GptTable,

    fat32: FileSystem,
    ext4: FileSystem,
    adf: FileSystem,

    data: std.Build.LazyPath,

    binary: *std.Build.CompileStep,
};

pub const MbrTable = struct {
    partitions: [4]?*const MbrPartition,
};

pub const MbrPartition = struct {
    offset: u64,
    size: u64,

    bootable: bool,
    type: MbrPartitionType,

    data: Contents,
};

/// https://en.wikipedia.org/wiki/Partition_type
pub const MbrPartitionType = enum(u8) {
    empty = 0x00,

    fat12 = 0x01,
    ntfs = 0x07,

    fat32_chs = 0x0B,
    fat32_lba = 0x0C,

    fat16_lba = 0x0E,

    linux_swap = 0x82,
    linux_fs = 0x83,
    linux_lvm = 0x8E,

    _,
};

pub const Guid = [16]u8;

pub const GptTable = struct {
    disk_id: Guid,

    partitions: []const *GptPartition,
};

pub const GptPartition = struct {
    type: Guid,
    part_id: Guid,

    offset: u64,
    size: u64,

    name: [36]u16,

    attributes: Attributes,

    data: Contents,

    pub const Attributes = struct {
        system: bool,
        efi_hidden: bool,
        legacy: bool,
        read_only: bool,
        hidden: bool,
        no_automount: bool,
    };
};

/// https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs
pub const GptPartitionType = struct {
    pub const unused: Guid = .{};
    pub const microsoft_basic_data: Guid = .{};
    pub const microsoft_reserved: Guid = .{};
    pub const windows_recovery: Guid = .{};
    pub const plan9: Guid = .{};
    pub const linux_swap: Guid = .{};
    pub const linux_fs: Guid = .{};
    pub const linux_reserved: Guid = .{};
    pub const linux_lvm: Guid = .{};
};

pub const FileSystem = struct {
    const Entry = union(enum) {
        empty_dir: []const u8,
        copy_dir: struct {
            source: std.Build.LazyPath,
            destination: []const u8,
        },
        copy_file: struct {
            source: std.Build.LazyPath,
            destination: []const u8,
        },
    };

    entries: []const u8,
};
