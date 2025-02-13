#!/usr/bin/env python3
import sys 
import re

data = sys.stdin.read()


pattern = re.compile(r"\s*(0x[A-Z0-9]{2})/0x00\s*")

sys.stdout.write(pattern.sub(lambda match: chr(int(match.group(1),16)), data))