#!/usr/bin/env python3

import json
import re
import sys
import subprocess

from dataclasses import dataclass

BIT_PATTERN = re.compile(
    r"^\[(?:(?P<single>\d+)|(?P<high>\d+)\:(?P<low>\d+))\]$"
)

JSON_DATA = sys.stdin.read()
# r"""
# {"rows":[{"cells":["Bits","Name","Type","Function"]},{"cells":["[31:16]","Write: VECTKEYSTAT\n\nRead: VECTKEY","RW","Register key:\n\nReads as 0xFA05\n\nOn writes, write 0x5FA to VECTKEY, otherwise the write is ignored."]},{"cells":["[15]","ENDIANNESS","RO","Data endianness bit is implementation defined:\n\n0 = Little-endian\n\n1 = Big-endian."]},{"cells":["[14:11]","-","-","Reserved"]},{"cells":["[10:8]","PRIGROUP","R/W","Interrupt priority grouping field is implementation defined. This field determines the split of group priority from subpriority, see Binary point."]},{"cells":["[7:3]","-","-","Reserved."]},{"cells":["[2]","SYSRESETREQ","WO","System reset request bit is implementation defined:\n\n0 = no system reset request\n\n1 = asserts a signal to the outer system that requests a reset.\n\nThis is intended to force a large system reset of all major components except for debug.\n\nThis bit reads as 0.\n\nSee you vendor documentation for more information about the use of this signal in your implementation."]},{"cells":["[1]","VECTCLRACTIVE","WO","Reserved for Debug use. This bit reads as 0. When writing to the register you must write 0 to this bit, otherwise behavior is Unpredictable."]},{"cells":["[0]","VECTRESET","WO","Reserved for Debug use. This bit reads as 0. When writing to the register you must write 0 to this bit, otherwise behavior is Unpredictable."]}]}
# """.strip()

subprocess.run(["clear"])

json_data = json.loads(JSON_DATA)

rows = json_data["rows"]

header_row = rows[0]["cells"]
data_rows = rows[1:]

BITS_OFFSET = header_row.index("Bits")
NAME_OFFSET = header_row.index("Name")
FUNCTION_OFFSET = header_row.index("Function")

try:
    TYPE_OFFSET = header_row.index("Type")
except ValueError:
    TYPE_OFFSET = None

@dataclass(kw_only=True)
class Field:
    offset: int
    bitsize: int
    name: int
    access_type: str
    description: int

fields: list[Field] = list()

reserved_count :int = 0

for row in data_rows:
    try:
        cells = row["cells"]

        if len(cells) == 1:
            continue 

        low_bit: int
        high_bit: int

        match = BIT_PATTERN.match(cells[BITS_OFFSET])
        if match.group("high") is not None:
            # bit range
            low_bit = int(match.group("low"))
            high_bit = int(match.group("high"))
        else:
            low_bit = int(match.group("single"))
            high_bit = low_bit

        name: str = cells[NAME_OFFSET]
        if name == "-":
            name = f"_reserved{reserved_count}"
            reserved_count += 1

        access_type: bool = cells[TYPE_OFFSET].upper() if TYPE_OFFSET is not None else "RW"
        description: str = cells[FUNCTION_OFFSET]

        # print(high_bit, low_bit,repr( name), access_type,repr( description))

        fields.append(Field(
            offset=low_bit,
            bitsize=high_bit - low_bit + 1,
            name = name,
            description = description,
            access_type=access_type,
        ))
    except:
        print(row)
        raise 

fields.sort(key=lambda fld: fld.offset)

for i in range(len(fields) - 1):
    assert fields[i + 1].offset == fields[i].offset + fields[i].bitsize, f"{fields[i].offset}/{fields[i].bitsize} =/=> {fields[i+1].offset}/{fields[i+1].bitsize}"

total_size = fields[-1].offset + fields[-1].bitsize 

assert total_size in [ 32, 16, 8], f"{total_size}"



stream = sys.stdout
for field in fields:

    for line in  field.description.splitlines():
        if line.strip() == "":
            continue 
        stream.write("/// " + line.rstrip() + "\n")

    stream.write(f"{field.name}: u{field.bitsize}, // [")
    if field.bitsize > 1:
        stream.write(f"{field.offset + field.bitsize - 1}:{field.offset}")
    else:
        stream.write(f"{field.offset}")
    stream.write(f"], {field.access_type}\n")
    stream.write("\n")
