#!/usr/bin/env python3
"""Generates Resources/icon.png: a macOS-style rounded-square app icon (1024x1024).

macOS does not mask or pad app icons, so the artwork has to include its own rounded shape and
the standard transparent margin (824 px square inside the 1024 px canvas).
Requires Pillow:  pip3 install pillow
"""
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2                      # supersample factor
CANVAS = 1024 * S
BODY = 824 * S             # Apple icon grid
MARGIN = (CANVAS - BODY) // 2
RADIUS = int(BODY * 0.2237)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def main(out):
    # Body gradient, top (bright red) to bottom (deep red).
    top, bottom = (255, 92, 78), (190, 0, 28)
    grad = Image.new("RGB", (BODY, BODY))
    px = ImageDraw.Draw(grad)
    for y in range(BODY):
        px.line([(0, y), (BODY, y)], fill=lerp(top, bottom, y / (BODY - 1)))

    mask = Image.new("L", (BODY, BODY), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, BODY - 1, BODY - 1], RADIUS, fill=255)

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Soft drop shadow.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_mask = Image.new("L", (CANVAS, CANVAS), 0)
    shadow_mask.paste(mask, (MARGIN, MARGIN + 12 * S))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(14 * S))
    shadow.putalpha(shadow_mask.point(lambda v: int(v * 0.35)))
    icon = Image.alpha_composite(icon, shadow)

    body = Image.new("RGBA", (BODY, BODY))
    body.paste(grad)
    body.putalpha(mask)

    # Play triangle: rounded, white, centered on its centroid.
    tri = Image.new("L", (BODY, BODY), 0)
    d = ImageDraw.Draw(tri)
    h = int(BODY * 0.50)
    w = int(h * 0.866)
    cx, cy = BODY // 2, BODY // 2
    left = cx - w // 3
    pts = [(left, cy - h // 2), (left + w, cy), (left, cy + h // 2)]
    r = BODY * 0.035
    # Round the corners exactly: shrink the triangle toward its incenter by r, then draw the
    # shrunken triangle thickened by r (edges as lines, vertices as circles).
    import math
    def side(p, q): return math.hypot(p[0] - q[0], p[1] - q[1])
    a_, b_, c_ = side(pts[1], pts[2]), side(pts[0], pts[2]), side(pts[0], pts[1])
    perimeter = a_ + b_ + c_
    incenter = tuple((a_ * pts[0][i] + b_ * pts[1][i] + c_ * pts[2][i]) / perimeter for i in range(2))
    area = abs((pts[1][0] - pts[0][0]) * (pts[2][1] - pts[0][1]) - (pts[2][0] - pts[0][0]) * (pts[1][1] - pts[0][1])) / 2
    inradius = 2 * area / perimeter
    k = (inradius - r) / inradius
    inset = [(incenter[0] + (x - incenter[0]) * k, incenter[1] + (y - incenter[1]) * k) for x, y in pts]
    d.polygon(inset, fill=255)
    for i in range(3):
        d.line([inset[i], inset[(i + 1) % 3]], fill=255, width=int(r * 2))
    for x, y in inset:
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)

    glyph_shadow = tri.filter(ImageFilter.GaussianBlur(8 * S)).point(lambda v: int(v * 0.30))
    shadow_layer = Image.new("RGBA", (BODY, BODY), (80, 0, 10, 0))
    shadow_layer.putalpha(ImageChops.offset(glyph_shadow, 0, 6 * S))
    body = Image.alpha_composite(body, shadow_layer)

    glyph = Image.new("RGBA", (BODY, BODY), (255, 255, 255, 0))
    glyph.putalpha(tri)
    body = Image.alpha_composite(body, glyph)

    # Keep everything inside the rounded shape.
    final_alpha = ImageChops.multiply(body.getchannel("A"), mask)
    body.putalpha(final_alpha)

    icon.alpha_composite(body, (MARGIN, MARGIN))
    icon = icon.resize((1024, 1024), Image.LANCZOS)
    icon.save(out)
    print("wrote", out)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Resources/icon.png")
