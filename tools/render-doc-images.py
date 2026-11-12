#!/usr/bin/env python3
"""Renderiza componentes reais do app com dados sintéticos, sem consultar os CLIs."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
output = root / ".build" / "doc-images"
output.mkdir(parents=True, exist_ok=True)
sources = sorted(path for path in (root / "Sources" / "UsageBar").rglob("*.swift")
                 if path.name != "UsageBarApp.swift")
binary = output / "render-doc-images"
subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                str(root / "tools" / "RenderDocImages.swift"), "-o", str(binary)], check=True)
subprocess.run([str(binary), str(root / "docs")], check=True)
