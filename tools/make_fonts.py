"""Generate BMFont (.fnt + .png) resources for Connect IQ from TTF files.

Run: python3 tools/make_fonts.py   (needs Pillow; put the Barlow Condensed TTFs from
https://github.com/google/fonts/tree/main/ofl/barlowcondensed in ./fonts or set PILOTZULU_FONTS)
Glyphs are white-on-black greyscale (opaque). Connect IQ ignores the PNG alpha channel,
so anti-aliasing must live in the RGB values; it then tints them with dc.setColor().
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

import os
FD = Path(os.environ.get("PILOTZULU_FONTS", Path(__file__).resolve().parent.parent / "fonts"))
OUT = Path(__file__).resolve().parent.parent / "resources/fonts"
OUT.mkdir(parents=True, exist_ok=True)

DIGITS = "0123456789:"
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
FONTS = [
    # id,          ttf,                          px,  chars
    ("BigTime",   "BarlowCondensed-Light.ttf",    150, DIGITS),
    ("ZuluMain",  "BarlowCondensed-SemiBold.ttf",  48, DIGITS + "Z"),
    ("ZuluSec",   "BarlowCondensed-SemiBold.ttf",  30, DIGITS),
    ("Label",     "BarlowCondensed-Medium.ttf",    20, DIGITS + UPPER + " ,%-"),
    ("Date",      "BarlowCondensed-SemiBold.ttf",  22, DIGITS + UPPER + " "),
    ("Home",      "BarlowCondensed-Bold.ttf",      25, DIGITS + UPPER + " "),
    ("Row",       "BarlowCondensed-SemiBold.ttf",  25, DIGITS + "BK ,%-"),
]

def build(fid, ttf, px, chars):
    font = ImageFont.truetype(str(FD / ttf), px)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    glyphs = []
    for ch in chars:
        x0, y0, x1, y1 = font.getbbox(ch, anchor="ls")
        w, h = max(1, x1 - x0), max(1, y1 - y0)
        glyphs.append((ch, x0, y0, w, h, round(font.getlength(ch))))
    pad = 2
    sheet_w = 512 if px < 100 else 1024
    x = y = row_h = 0
    places = []
    for g in glyphs:
        _, _, _, w, h, _ = g
        if x + w + pad > sheet_w:
            x = 0; y += row_h + pad; row_h = 0
        places.append((x, y)); x += w + pad; row_h = max(row_h, h)
    sheet_h = y + row_h + pad
    img = Image.new("RGB", (sheet_w, sheet_h), (0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = [
        f'info face="{fid}" size={px} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing={pad},{pad}',
        f"common lineHeight={line_h} base={ascent} scaleW={sheet_w} scaleH={sheet_h} pages=1 packed=0",
        f'page id=0 file="{fid}.png"',
        f"chars count={len(glyphs)}",
    ]
    for (ch, x0, y0, w, h, adv), (px_, py_) in zip(glyphs, places):
        if ch != " ":
            d.text((px_ - x0, py_ - y0), ch, font=font, fill=(255, 255, 255), anchor="ls")
        lines.append(f"char id={ord(ch)} x={px_} y={py_} width={w} height={h} "
                     f"xoffset={x0} yoffset={ascent + y0} xadvance={adv} page=0 chnl=15")
    img.save(OUT / f"{fid}.png")
    (OUT / f"{fid}.fnt").write_text("\n".join(lines) + "\n")
    return sheet_w, sheet_h

xml = ["<fonts>"]
for fid, ttf, px, chars in FONTS:
    w, h = build(fid, ttf, px, chars)
    xml.append(f'    <font id="{fid}" filename="{fid}.fnt" antialias="true"/>')
    print(f"{fid}: {w}x{h}")
xml.append("</fonts>")
(OUT / "fonts.xml").write_text("\n".join(xml) + "\n")
