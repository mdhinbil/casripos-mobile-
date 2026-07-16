"""Generate Casri POS launcher icon + presplash PNGs.

Rasterises the same POS-terminal glyph used in icon.svg (navy rounded square,
blue terminal body, white display, keypad dots with one cyan, cyan base bar)
into the PNGs buildozer needs.

Run: python generate_assets.py
Output: assets/icon.png (512x512), assets/presplash.png (1080x1920 navy)
"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
os.makedirs(OUT, exist_ok=True)

NAVY = (10, 22, 40, 255)     # #0a1628
BLUE = (26, 110, 245, 255)   # #1a6ef5
CYAN = (0, 184, 217, 255)    # #00b8d9
WHITE = (255, 255, 255, 255)
BG = WHITE                   # icon background (was NAVY — user wanted it changed)
BORDER = (224, 230, 240, 255)  # subtle light-grey edge so a white icon isn't borderless

SS = 4  # super-sample for crisp anti-aliased edges


def rrect(d, box, radius, fill):
    d.rounded_rectangle(box, radius=radius, fill=fill)


# ── Launcher icon: 512×512, drawn at 4× then downsampled ──
W = 512 * SS
icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(icon)


def s(v):
    return int(v * SS)


# Rounded-square background (white) + subtle light-grey rim so it isn't edgeless
rrect(d, (0, 0, W, W), s(96), BG)
d.rounded_rectangle((s(2), s(2), W - s(2), W - s(2)), radius=s(94),
                    outline=BORDER, width=s(3))
# Terminal body (blue)
rrect(d, (s(96), s(128), s(416), s(368)), s(24), BLUE)
# Display (white)
rrect(d, (s(128), s(160), s(384), s(224)), s(8), WHITE)
# Keypad dots — one cyan, rest white
for cx, col in ((160, WHITE), (220, WHITE), (280, CYAN), (340, WHITE)):
    d.ellipse((s(cx - 20), s(280 - 20), s(cx + 20), s(280 + 20)), fill=col)
# Cyan base bar
rrect(d, (s(96), s(384), s(416), s(416)), s(8), CYAN)

icon = icon.resize((512, 512), Image.LANCZOS)
icon.save(os.path.join(OUT, "icon.png"), "PNG")
print("Wrote", os.path.join(OUT, "icon.png"))

# ── Presplash: flat navy (matches Kivy Window.clearcolor) so no branded splash ──
Image.new("RGBA", (1080, 1920), NAVY).save(
    os.path.join(OUT, "presplash.png"), "PNG")
print("Wrote", os.path.join(OUT, "presplash.png"))
