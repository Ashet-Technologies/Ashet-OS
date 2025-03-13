#!/usr/bin/env python3

import re 
from dataclasses import dataclass

sizes = ["relsafe", "unoptimized"]

versions = ["0.13.0", "0.14.0-dev.3367", "0.14.0"]

baseline = "0.13.0"

@dataclass
class DataPoint:
    text: int
    data: int 
    bss: int

    @property
    def total(self) -> int:
        return self.text + self.data + self.bss
    
    @property
    def ram(self) -> int:
        return self.data + self.bss

def parse_dataset(path: str) -> dict[str, DataPoint]:
    files = dict()
    with open(path, "r", encoding='utf-8') as fp:

        assert next(fp) is not None 

        for line in fp:
            line = line.strip()
            if line == "":
                continue
            text, data, bss, dec, hex, filename = (*re.split(r"\s+", line),)

            assert filename not in files 

            files[filename] = DataPoint(
                text = int(text),
                data = int(data),
                bss = int(bss),
            )

    return files 

for optimize_mode in sizes:

    sets = dict()

    for version in versions:

        sets[version] = parse_dataset(f".vscode/sizes/{version}/{optimize_mode}.txt")
    
    all_keys = set(
        key 
        for vers in sets.values()
        for key in vers.keys()
    )

    key_width = max(len(k) for k in all_keys)

    print("Optimize Mode:", optimize_mode)
    print("File".ljust(key_width), *(f"| {v}".ljust(23) for v in versions)  )

    for key in sorted(all_keys, key=lambda n: sets[baseline][n].text, reverse=True):

        base_size = sets[baseline][key].text

        cols = list()
        for version in versions:
            abssize = sets[version][key].text
            relsize = abssize / base_size
            delta = f"+{abssize-base_size}" if abssize >= base_size else f"-{base_size-abssize}"
            if version == baseline:
                delta = str(abssize)
            cols.append(f"| {100*relsize:9.2f}% ({delta})".ljust(23))

        print(key.ljust(key_width), *cols)