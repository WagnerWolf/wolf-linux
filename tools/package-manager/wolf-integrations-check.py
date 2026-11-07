#!/usr/bin/env python3
"""Diagnóstico somente leitura das integrações Wolf."""
import sys
from pathlib import Path
system_module = Path('/usr/local/lib/wolf-linux/package-manager')
if (system_module/'wolfpkg/integrations.py').is_file():
    sys.path.insert(0, str(system_module))
from wolfpkg.integrations import format_report
print(format_report())
