#!/usr/bin/env bash

find zig-out -name "*.elf" | xargs llvm-size