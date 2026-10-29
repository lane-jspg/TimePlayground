#!/usr/bin/env python3
"""Rasterize the original SVG artwork without relying on Godot SVG text support.

Requires Inkscape on PATH. PNGs are checked in so Godot needs no extra tools.
Run from any directory: python3 tools/prepare_assets.py
"""
from pathlib import Path
import math
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets' / 'source'
OUTPUT = ROOT / 'assets' / 'textures'
SCALES = {
    'logo': 3,
    'play_button': 3,
    'exit_button': 3,
    'spawn_object_menu': 2,
    'wheel_spawn': 2,
    'soda_spawn': 2,
    'box_spawn': 2,
}

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for source in sorted(SOURCE.glob('*.svg')):
        svg = ET.parse(source).getroot()
        scale = SCALES.get(source.stem, 1)
        width = math.ceil(float(svg.attrib['width']) * scale)
        height = math.ceil(float(svg.attrib['height']) * scale)
        output = OUTPUT / (source.stem + '.png')
        # Archivo is named in the supplied SVGs but not embedded. Give renderers
        # a metric-compatible fallback instead of an arbitrary system default.
        # Keep uploaded sources byte-for-byte intact.
        text = source.read_text().replace('font-family=\"Archivo\"', 'font-family=\"Archivo,Arial,sans-serif\"')
        with tempfile.TemporaryDirectory(prefix='timeplayground-art-') as directory:
            rendered_source = Path(directory) / source.name
            rendered_source.write_text(text)
            subprocess.run([
                'inkscape', str(rendered_source), '--export-type=png',
                '--export-area-page', '--export-width=' + str(width),
                '--export-height=' + str(height), '--export-filename=' + str(output),
            ], check=True)
        print(f'{output.relative_to(ROOT)}: {width}x{height}')

if __name__ == '__main__':
    main()
