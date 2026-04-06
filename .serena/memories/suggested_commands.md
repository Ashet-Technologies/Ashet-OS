Useful commands on this Linux workspace:

- `rg` / `rg --files` for search
- `ls`, `find`, `sed -n`, `git status`, `git diff`.
- Main build toolchain uses `zig-0.15.2`. Common project commands:
  - `zig-0.15.2 build`
  - `zig-0.15.2 build test`
- repo recipes from `justfile` such as:
  - `just build`
  - `just abi-test`
  - `just build-tools`
  - and machine-specific build/run targets
