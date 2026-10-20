"""Regenerate the original test font with FontTools 4.66.1 (not needed to build/test).

No external font data: .notdef, A, and U+00E9 use a rectangular outline; space is blank.
This deliberately lacks typography features and is only a deterministic rasterization fixture.
"""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

font = FontBuilder(1000, isTTF=True)
order = [".notdef", "space", "box"]
font.setupGlyphOrder(order)
font.setupCharacterMap({32: "space", 65: "box", 233: "box"})
glyphs = {}
for name in order:
    pen = TTGlyphPen(None)
    if name != "space":
        pen.moveTo((100, 0))
        pen.lineTo((100, 700))
        pen.lineTo((500, 700))
        pen.lineTo((500, 0))
        pen.closePath()
    glyphs[name] = pen.glyph()
font.setupGlyf(glyphs)
font.setupHorizontalMetrics({name: (600, 100 if name != "space" else 0) for name in order})
font.setupHorizontalHeader(ascent=800, descent=-200)
font.setupNameTable({"familyName": "Zig SDL Box Fixture", "styleName": "Regular",
                     "uniqueFontIdentifier": "zig-sdl3-box-v1",
                     "fullName": "Zig SDL Box Fixture Regular", "psName": "ZigSDLBoxFixture"})
font.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
font.setupPost()
font.setupMaxp()
font.font.recalcTimestamp = False
font.font["head"].created = font.font["head"].modified = 2082844800
font.save(Path(__file__).with_name("box.ttf"))
