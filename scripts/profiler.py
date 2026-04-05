#!/usr/bin/env python

from openocd import Session
from time import monotonic_ns, sleep

# Connect to a running OpenOCD instance
with Session.connect_sync() as ocd:
    start = monotonic_ns()
    end = start + 10_000_000_000
    while monotonic_ns() < end :
        pc =  ocd.memory.read_u32(0x2002E134, 1)[0]
        print(f"{(monotonic_ns() - start) // 1000} {pc:#x} {pc-0x11249000:#x}")
        sleep(0.0011)