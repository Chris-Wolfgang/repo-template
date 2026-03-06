#!/usr/bin/env python3
"""Print the raw TargetFramework(s) value from a .NET project file.

Usage: python3 get_tfm.py <project-file>

Exits 0 and prints the semicolon-separated value on stdout if found;
exits 1 if the project file cannot be parsed or the property is absent.
"""
import sys
import xml.etree.ElementTree as ET

if len(sys.argv) < 2:
    sys.exit(1)

try:
    tree = ET.parse(sys.argv[1])
except Exception:
    sys.exit(1)

root = tree.getroot()
# Extract XML namespace prefix, e.g. "{http://schemas.microsoft.com/developer/msbuild/2003}"
ns = (root.tag.split("}")[0] + "}") if root.tag.startswith("{") and "}" in root.tag else ""

for tag in [ns + "TargetFrameworks", ns + "TargetFramework"]:
    elem = root.find(".//" + tag)
    if elem is not None and elem.text:
        print(elem.text.strip())
        sys.exit(0)

sys.exit(1)
