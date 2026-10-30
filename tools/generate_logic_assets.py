#!/usr/bin/env python3
"""Create deterministic technical game icons from the user's inline visual references.

These authored SVGs recreate the shown chip/category style. They are not the
original inline attachment bytes (those images were not available as files).
The lever and spawn buttons are new art matching the earlier supplied palette.
Requires Inkscape only when regenerating; PNGs are committed for normal play.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures"


def svg(width, height, content):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{content}</svg>'


def text(label, x, y, size=10, color="white", weight="normal"):
    return f'<text x="{x}" y="{y}" text-anchor="middle" font-family="Arial,sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}">{label}</text>'


def gate(label):
    pins = ''.join(f'<path d="M5 {y}H17M47 {y}H59" stroke="#9b602b" stroke-width="2"/><path d="M7 {y-1}H16M49 {y-1}H56" stroke="#da9947" stroke-width="1"/>' for y in [10, 16, 22])
    return pins + '<rect x="15" y="6" width="34" height="23" fill="#444"/><path d="M15 6H49V29H15Z" fill="none" stroke="#8c8c8c" stroke-width="2"/><path d="M17 8H47V26H17Z" fill="#101010"/><path d="M17 26H47" stroke="#aaa" stroke-width="2"/>' + text(label, 32, 21, 12, "#eee")


def cpu():
    c = '<rect x="3" y="3" width="90" height="66" fill="#15530d" stroke="#72891a" stroke-width="2"/>'
    for x in range(9, 91, 5):
        c += f'<path d="M{x} 5V13M{x} 59V67" stroke="#969c36" stroke-width="1"/>'
    for y in range(12, 64, 5):
        c += f'<path d="M5 {y}H13M83 {y}H91" stroke="#b1a143" stroke-width="1"/>'
    c += '<g fill="none" stroke="#b1ba64" stroke-width="1"><path d="M18 9H48V22H26V54H12V34H23V15H65V59H34V45H84"/><path d="M16 17H11V57H30V27H56V62H79V18H51V9H87V52H70"/><path d="M18 22H40V38H21V64H48V48H61V29H83"/></g>'
    c += '<g fill="#b8b8b8" stroke="#646464" stroke-width="2"><rect x="31" y="18" width="30" height="22"/><rect x="58" y="44" width="25" height="22"/><rect x="72" y="13" width="13" height="19"/></g>'
    c += '<g stroke="#ccc" stroke-width="1">'
    for x in range(34,60,4):
        c += f'<path d="M{x} 14V18M{x} 40V44"/>'
    c += '</g>' + text('LINE',46,32,6,'#444') + text('CPU',70,59,9,'#444') + text('12',78,25,6,'#444')
    c += '<rect x="12" y="43" width="31" height="13" fill="#193715" stroke="#a6a886"/>' + text('LANE',27,52,8,'#deded2')
    c += '<g fill="#434343" stroke="#999"><rect x="12" y="61" width="7" height="9"/><rect x="22" y="61" width="7" height="9"/></g>'
    c += '<circle cx="11" cy="11" r="4" fill="none" stroke="#ddd"/>'
    return c


def lever():
    return '<rect x="6" y="31" width="48" height="24" rx="2" fill="#555" stroke="#a4a4a4" stroke-width="2"/><rect x="12" y="36" width="36" height="13" fill="#202020"/><circle cx="30" cy="42" r="9" fill="#999" stroke="#ccc" stroke-width="2"/><path d="M30 42L43 14" stroke="#292929" stroke-width="8"/><path d="M29 39L40 15" stroke="#c4c4c4" stroke-width="4"/><circle cx="44" cy="12" r="8" fill="#8c2929" stroke="#c16464" stroke-width="2"/><path d="M3 39H9M51 39H59M3 47H9M51 47H59" stroke="#ae7439" stroke-width="2"/>'


def category(content):
    return '<rect x="4" y="4" width="92" height="92" rx="8" fill="#242424" stroke="#242424" stroke-width="4"/><rect x="7" y="7" width="86" height="86" rx="7" fill="#363636" stroke="#515151" stroke-width="3"/>' + content


def write(name, width, height, content):
    OUT.mkdir(parents=True, exist_ok=True)
    source = OUT / (name + '.svg')
    target = OUT / (name + '.png')
    source.write_text(svg(width,height,content))
    subprocess.run(['inkscape', str(source), '--export-type=png', '--export-area-page', '--export-filename='+str(target)], check=True, stdout=subprocess.DEVNULL)
    print(target.relative_to(ROOT))


def main():
    icons = {}
    for name,label in [('and_gate','AND'),('not_gate','NOT'),('or_gate','OR'),('xor_gate','XOR')]:
        icons[name] = (64,32,gate(label),label)
    icons['cpu'] = (96,72,cpu(),'CPU')
    icons['lever'] = (64,64,lever(),'Lever')
    for name,(w,h,body,label) in icons.items():
        write(name,w,h,body)
        scale = min(42/w,35/h)
        x=(56-w*scale)/2
        y=4+(35-h*scale)/2
        button='<rect width="56" height="54" fill="#181818"/>' + f'<g transform="translate({x},{y}) scale({scale})">{body}</g>' + text(label,28,49,9)
        write(name+'_spawn',56,54,button)
    write('gates_category',100,100,category('<path d="M27 72V59C27 24 73 24 73 59V72M27 57H73M50 22V35" fill="none" stroke="#eee" stroke-width="3"/>' + text('GATES',50,53,11,'#eee','bold')))
    write('objects_category',100,100,category('<rect x="17" y="16" width="66" height="69" rx="3" fill="none" stroke="#eee" stroke-width="4"/><path d="M20 19L80 82M80 19L20 82" stroke="#eee" stroke-width="4"/>'))
    write('electronics_category',100,100,category('<path d="M31 17H68Q82 17 82 32V62H35V69H80V72Q80 83 67 83H33Q19 83 19 69V31Q19 17 31 17Z" fill="#eee"/><path d="M64 33H73V45H64Z" fill="#363636"/>'))

if __name__ == '__main__':
    main()
