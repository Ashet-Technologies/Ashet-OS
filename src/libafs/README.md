# Ashet File System

## Features

- Simple
- Address up to 8 ZiB storage
- Files and Directories
- Hierarchical
- 64 byte file names

## Structure

The file system is a hierarchical file system organized in files (blobs of data) and directories (list of files and dirs).

It assumes blocks of size 512 byte.

Each file system starts with a root config block that stores meta data about the file system, then a block allocation table,
and then the directory and file data.

### Root Block

The root block is organized as follows:

```rs
struct RootBlock {
  magic_identification_number: [32]u8 = .{
    0x2c, 0xcd, 0xbe, 0xe2, 0xca, 0xd9, 0x99, 0xa7, 0x65, 0xe7, 0x57, 0x31, 0x6b, 0x1c, 0xe1, 0x2b,
    0xb5, 0xac, 0x9d, 0x13, 0x76, 0xa4, 0x54, 0x69, 0xfc, 0x57, 0x29, 0xa8, 0xc9, 0x3b, 0xef, 0x62,
  },
  version: u32 = 1, // must be 1
  size: u64 align(4), // number of managed blocks

  padding: [468]u8, // fill up to 512
}
```

The root block is located at block number 0.

### Allocation Table

After the root block, the allocation table follows. This table is `root.size / 4096` blocks large and
stores a bitmap with each bit corresponding to a block. If the bit is set, the block is allocated.

Bits are counted LSB to MSB, so the bit and offset can be computed as such:

```rs
fn convert(query_block_id: u32) BlockInfo {
  return BlockInfo {
    .block_offset = 1 + query_block_id / 4096,
    .byte_offset  = (query_block_id % 4096) / 8,
    .bit_offset   = (query_block_id % 8),
  };
}
```

This table is used to allocate blocks for everything that is dynamic. The first two bits are always set
as they mark the root block and at least a single allocation table to be used.

### Data

After the allocation table, the root directory block is located. This block is a object block for a directory node.

Each object block encodes either a file or a directory (stored as external means)

```rs
struct ObjectBlock {
  size: u64,          // size of this object in bytes. for directories, this means the directory contains `size/sizeof(Entry)` elements.
  create_time: i128 align(4),  // stores the date when this object was created, unix timestamp in nano seconds
  modify_time: i128 align(4),  // stores the date when this object was last modified, unix timestamp in nano seconds
  flags: u32,         // type-dependent bit field (file: bit 0 = read only; directory: none; all other bits are reserved=0)
  refs: [116]u32,     // pointer to a type-dependent data block (FileDataBlock, DirectoryDataBlock)
  next: u32,          // link to a RefListBlock to continue the refs listing. 0 is "end of chain"
}

struct RefListBlock {
  refs: [127]u32,     // pointers to data blocks to list the entries
  next: u32,          // pointer to the next RefListBlock or 0
}

struct FileDataBlock {
  opaque: [512]u8,    // arbitrary file content, has no filesystem-defined meaning.
}

struct DirectoryDataBlock {
  entries: [4]Entry,  // entries in a directory block fill up to 512 byte.
}

struct Entry {
  name: [120]u8,      // zero-padded file name
  type: u32,          // the kind of this entry. 0 = directory, 1 = file, all other values are illegal
  ref: u32,           // link to the associated ObjectBlock. if 0, the entry is deleted. this allows a panic recovery for accidentially deleted files.
}
```

Each directory block can contain up to 252 files. If there are more files in a directory, the `next` field
links to another directory block that contains pointers to the next 252 files. The `size` field for all
directory blocks in a directory are the same.

The `refs` field has pointers to directory data blocks. Each data block contains two entries of a directory.
