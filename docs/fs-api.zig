// New API (Zig Style):

// A file or directory on Ashet OS can be named with any legal UTF-8 sequence
// that does not contain `/` and `:`. It is recommended to only create file names
// that are actually typeable on the operating system tho.
//
// There are some special file names:
// - `.` is the "current directory" selector and does not add to the path.
// - `..` is the "parent directory" selector and navigates up in the directory hierarchy if possible.
// - Any sequence of upper case ASCII letters and digits (`A-Z`, `0-9`) that ends with `:` is a file system name. This name specifies
//   the root directory of a certain file system.
//
// Paths are either a relative or absolute addressing of a file system entity.
// Paths are composed of a sequence of names, each name separated by `/`.
// A file system name is only legal as the first element of a path sequence, making the path an absolute path.
//
// There is a limit on how long a file/directory name can be, but there's no limit on how long a total
// path can be.
//
// Here are some examples for valid paths:
// - `example.txt`
// - `docs/wiki.txt`
// - `SYS:/apps/editor/code`
// - `USB0:/foo/../bar` (which is equivalent to `USB0:/bar`)
//
// The filesystem that is used to boot the OS from has an alias `SYS:` that is always a legal way to address this file system.

// GROUP: Types

/// The maximum number of bytes in a file system identifier name.
/// This is chosen to be a power of two, and long enough to accommodate
/// typical file system names:
/// - `SYS`
/// - `USB0`
/// - `USB10`
/// - `PF0`
/// - `CF7`
pub const max_fs_name_len = 8;

/// The maximum number of bytes in a file system type name.
/// Chosen to be a power of two, and long enough to accomodate typical names:
/// - `FAT16`
/// - `FAT32`
/// - `exFAT`
/// - `NTFS`
/// - `ReiserFS`
/// - `ISO 9660`
/// - `btrfs`
/// - `AFFS`
pub const max_fs_type_len = 16;

/// The maximum number of bytes in a file name.
/// This is chosen to be a power of two, and reasonably long.
/// As some programs use sha256 checksums and 64 bytes are enough to store
/// a hex-encoded 256 bit sequence:
/// - `114ac2caf8fefad1116dbfb1bd68429f68e9e088b577c9b3f5a3ff0fe77ec886`
/// This should also enough for most reasonable file names in the wild.
pub const max_file_name_len = 64;

/// Unix timestamp in milliseconds
pub const DateTime = i64;

pub const FileSystemId = enum(u32) {
    /// This is the file system which the os has bootet from.
    system = 0,

    /// the filesystem isn't valid.
    invalid = ~@as(u32, 0),

    /// All other ids are unique file systems.
    _,
};

pub const FileHandle = enum(u32) { invalid, _ };
pub const DirectoryHandle = enum(u32) { invalid, _ };

pub const FileSystemInfo = extern struct {
    id: FileSystemId, // system-unique id of this file system
    flags: Flags, // binary infos about the file system
    name: [max_fs_name_len]u8, // user addressable file system identifier ("USB0", ...)
    filesystem: [max_fs_type_len]u8, // string identifier of a file system driver ("FAT32", ...)

    pub const Flags = packed struct(u16) {
        system: bool, // is the system boot disk
        removable: bool, // the file system can be removed by the user
        read_only: bool, // the file system is mounted as read-only
        reserved: u13 = 0,
    };
};

pub const FileInfo = extern struct {
    name: [max_file_name_len]u8,
    size: u64,
    attributes: FileAttributes,
    creation_date: DateTime,
    modified_date: DateTime,
};

pub const FileAttributes = packed struct(16) {
    directory: bool,
    read_only: bool,
    hidden: bool,
    reserved: u13 = 0,
};

pub const FileAccess = enum(u8) {
    read_only = 0,
    write_only = 1,
    read_write = 2,
};

pub const FileMode = enum(u8) {
    open_existing = 0, // opens file when it exists on disk
    open_always = 1, // creates file when it does not exist, or opens the file without truncation.
    create_new = 2, // creates file when there is no file with that name
    create_always = 3, // creates file when it does not exist, or opens the file and truncates it to zero length
};

// GROUP: top level

/// Flushes all open files to disk.
fn @"fs.Sync"() struct {};

// GROUP: file systems

/// Finds a file system by name
fn @"fs.FindFilesystem"(name: []const u8) struct { id: FileSystemId };

/// Gets information about a file system.
/// Also returns a `next` id that can be used to iterate over all filesystems.
/// The `system` filesystem is guaranteed to be the first one.
fn @"fs.GetFilesystemInfo"(fs: FileSystemId) struct { info: FileSystemInfo, next: FileSystemId };

// GROUP: dir handling

/// opens a directory on a filesystem
fn @"fs.dir.OpenDrive"(fs: FileSystemId, path: []const u8) struct { dir: DirectoryHandle };

/// opens a directory relative to the given dir handle.
fn @"fs.dir.OpenDir"(dir: DirectoryHandle, path: []const u8) struct { dir: DirectoryHandle };

/// closes the directory handle
fn @"fs.dir.Close"(dir: DirectoryHandle) struct {};

// GROUP: iteration

/// resets the directory iterator to the starting point
fn @"fs.dir.Reset"(dir: DirectoryHandle) struct {};

/// returns the info for the current file or "eof", and advances the iterator to the next entry if possible
fn @"fs.dir.Next"(dir: DirectoryHandle) struct { eof: bool, info: FileInfo };

// GROUP: creation/destruction

/// deletes a file or directory by the given path.
fn @"fs.dir.Delete"(dir: DirectoryHandle, path: []const u8, recurse: bool) struct {};

/// creates a new directory relative to dir. If `path` contains subdirectories, all
/// directories are created.
fn @"fs.dir.MkDir"(dir: DirectoryHandle, path: []const u8) struct { DirectoryHandle };

/// returns the type of the file/dir at path, also adds size and modification dates
fn @"fs.dir.Info"(dir: DirectoryHandle, path: []const u8) struct { info: FileInfo };

/// renames a file inside the same file system.
/// NOTE: This is a cheap operation and does not require the copying of data.
fn @"fs.dir.NearMove"(src_dir: DirectoryHandle, src_path: []const u8, new_name: []const u8) struct {};

// GROUP: modification

/// moves a file or directory between two unrelated directories. Can also move between different file systems.
/// NOTE: This syscall might copy the data.
fn @"fs.dir.FarMove"(src_dir: DirectoryHandle, src_path: []const u8, dst_dir: DirectoryHandle, new_path: []const u8) struct {};

/// copies a file or directory between two unrelated directories. Can also move between different file systems.
fn @"fs.dir.Copy"(src_dir: DirectoryHandle, src_path: []const u8, dst_dir: DirectoryHandle, new_path: []const u8) struct {};

// // GROUP: file handling

/// opens a file from the given directory.
fn @"fs.dir.OpenFile"(dir: DirectoryHandle, path: []const u8, access: FileAccess, mode: FileMode) struct { DirectoryHandle };

/// closes the handle and flushes the file.
fn @"fs.file.Close"(file: FileHandle) struct {};

/// makes sure this file is safely stored to mass storage device
fn @"fs.file.Flush"(file: FileHandle) struct {};

/// directly reads data from a given offset into the file. no streaming API to the kernel
fn @"fs.file.Read"(file: FileHandle, offset: u64, buffer: []u8) struct { count: usize };

/// directly writes data to a given offset into the file. no streaming API to the kernel
fn @"fs.file.Write"(file: FileHandle, offset: u64, buffer: []const u8) struct { count: usize };

/// allows us to get the current size of the file, modification dates, and so on
fn @"fs.file.Info"(file: FileHandle) struct { FileInfo };

/// Resizes the file to the given length in bytes. Can be also used to truncate a file to zero length.
fn @"fs.file.Resize"(file: FileHandle, length: u64) struct {};
