#!/usr/bin/env python3

import sys
import math

if len(sys.argv) < 2:
    print("Usage: ./scripts/format-title.py <title>")
    sys.exit(1)

title = " ".join(sys.argv[1:])
half_len = len(title) // 2

indent = 4
style = "/"

if style == "*":
    width = 120
    stars_len = width - indent - 4
    first_stars = stars_len // 2 - math.ceil(half_len)
    second_stars = first_stars if len(title) % 2 == 0 else first_stars - 1

    header = f"{' ' * indent}/{'*' * first_stars} {title} {'*' * second_stars}/"
else:
    width = 100
    spaces_len = width - indent - 6
    first_spaces = spaces_len // 2 - math.ceil(half_len)
    second_spaces = first_spaces if len(title) % 2 == 0 else first_spaces - 1
    lines = [
        f"{' ' * indent}{'/' * (width - indent)}",
        f"{' ' * indent}//{' ' * first_spaces} {title} {' ' * second_spaces}//",
        f"{' ' * indent}{'/' * (width - indent)}",
    ]
    header = "\n".join(lines)

print(header)
