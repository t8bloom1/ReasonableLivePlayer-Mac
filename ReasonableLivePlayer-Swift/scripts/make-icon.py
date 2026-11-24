#!/usr/bin/env python3
"""Generates Resources/icon.png (1024x1024) in the original app's colors.

Pure red (#FF0000) with a black play triangle, using the same triangle proportions as the
original icon. The artwork is placed on the standard macOS icon grid: macOS does not mask or
pad app icons, so the rounded square and the transparent margin (824 px body inside the 1024 px
canvas) are part of the image.

Requires Pillow:  pip3 install pillow
"""
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2                      # supersample factor
CANVAS = 1024 * S
BODY = 824 * S
MARGIN = (CANVAS - BODY) // 2
RADIUS = int(BODY * 0.2237)

RED = (255, 0, 0)
BLACK = (0, 0, 0)

def main(out):
    mask = Image.new("L", (BODY, BODY), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, BODY - 1, BODY - 1], RADIUS, fill=255)

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Soft drop shadow, as on other macOS icons.
    shadow_mask = Image.new("L", (CANVAS, CANVAS), 0)
    shadow_mask.paste(mask, (MARGIN, MARGIN + 12 * S))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(14 * S)).point(lambda v: int(v * 0.35))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.putalpha(shadow_mask)
    icon = Image.alpha_composite(icon, shadow)

    body = Image.new("RGBA", (BODY, BODY), RED + (255,))

    # Triangle with the proportions of the original 1024 px icon:
    # (322,195) (802,515) (322,835), as fractions of the square.
    pts = [(0.3145 * BODY, 0.1904 * BODY),
           (0.7832 * BODY, 0.5029 * BODY),
           (0.3145 * BODY, 0.8154 * BODY)]
    tri = Image.new("L", (BODY, BODY), 0)
    ImageDraw.Draw(tri).polygon(pts, fill=255)
    glyph = Image.new("RGBA", (BODY, BODY), BLACK + (0,))
    glyph.putalpha(tri)
    body = Image.alpha_composite(body, glyph)

    body.putalpha(ImageChops.multiply(body.getchannel("A"), mask))
    icon.alpha_composite(body, (MARGIN, MARGIN))
    icon.resize((1024, 1024), Image.LANCZOS).save(out)
    print("wrote", out)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Resources/icon.png")
