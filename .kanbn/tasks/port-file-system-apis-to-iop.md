---
created: 2022-12-04T14:35:42.520Z
updated: 2023-04-09T17:29:56.077Z
assigned: ""
progress: 0
tags: []
completed: 2023-04-09T17:29:52.867Z
started: 2023-04-09T17:29:56.077Z
---

# Port file system APIs to IOP

port the following syscalls to the asynchronous api

## Sub-tasks

- [ ] `fn fs.delete(path_ptr: [*]const u8, path_len: usize) FileSystemError.Enum, 21);`
- [ ] `fn fs.mkdir(path_ptr: [*]const u8, path_len: usize) FileSystemError.Enum, 22);`
- [ ] `fn fs.rename(old_path_ptr: [*]const u8, old_path_len: usize, new_path_ptr: [*]const u8, new_path_len: usize) callconv(.C) FileSystemError.Enum, 23);`
- [ ] `fn fs.stat(path_ptr: [*]const u8, path_len: usize, *FileInfo) FileSystemError.Enum, 24);`
- [ ] `fn fs.openFile(path_ptr: [*]const u8, path_len: usize, FileAccess, FileMode, out: *FileHandle) FileOpenError.Enum, 25);`
- [ ] `fn fs.read(FileHandle, ptr: [*]u8, len: usize, out: *usize) FileReadError.Enum, 26);`
- [ ] `fn fs.write(FileHandle, ptr: [*]const u8, len: usize, out: *usize) FileWriteError.Enum, 27);`
- [ ] `fn fs.flush(FileHandle) FileWriteError.Enum, 29);`
- [ ] `fn fs.openDir(path_ptr: [*]const u8, path_len: usize, out: *DirectoryHandle) DirOpenError.Enum, 31);`
- [ ] `fn fs.nextFile(DirectoryHandle, *FileInfo, eof: *bool) DirNextError.Enum, 32);`
