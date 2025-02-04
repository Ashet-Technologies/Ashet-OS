#!/usr/bin/env python3

import sys


with open(sys.argv[1], "rb") as fp1, open(sys.argv[2], "rb") as fp2:

    bin1: bytes = fp1.read()
    bin2: bytes = fp2.read()

    # assert len(bin1) == len(bin2), f"{len(bin1)} != {len(bin2)}"

    print(hex(len(bin1)))

    size = min( len(bin1),  len(bin2))
    chunksize = 16 

    write = sys.stdout.write

    for i in range(0, size - 1, chunksize):

        width = min(chunksize, size - i)
        
        ch1 = bin1[i:i+width]
        ch2 = bin2[i:i+width]

        diff = [ a != b for a,b in zip(ch1, ch2)]

        write(f"0x{i:08X}: ")

        for val, changed in zip(ch1, diff):

            color = "97;41" if changed else "0"
            write(f" \x1b[{color}m{val:02X}\x1b[0m")

        write("  ")

        for val, changed in zip(ch2, diff):
            color = "97;41" if changed else "0"
            write(f" \x1b[{color}m{val:02X}\x1b[0m")

        write("\x1b[0m\n")

        # print(ch1.hex(), ch2.hex())
