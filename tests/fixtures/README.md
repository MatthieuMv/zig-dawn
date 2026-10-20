# Original test assets

`orange.bmp` is a 58-byte, 1x1 24-bit BMP: BITMAPINFOHEADER and a BGR pixel (50, 100, 200)
with one byte of row padding. It contains no external image data.

`box.ttf` is a 952-byte TrueType fixture generated entirely from original rectangular outlines.
It maps space to a blank glyph and A/U+00E9 to the same box. The missing-glyph outline is also
a box. It is for predictable tests, not application typography. No third-party glyph assets
are included.

Regenerate with `python3 tests/fixtures/make_box_font.py` using FontTools 4.66.1. FontTools is
an optional fixture-authoring tool; ordinary builds/tests require neither Python nor FontTools.
The script fixes font timestamps; regeneration was checked to produce identical bytes.

SHA-256 for `box.ttf`:
`935dce0b76eb118003ada7c56f658924f694e01df4d2f33e7a065ed560193ddd`.

`tone.wav` is an original 556-byte PCM WAV: mono, 48,000 Hz, signed 16-bit little-endian.
Its 256 samples alternate between +8192 and -8192 every eight samples. The RIFF/WAVE header
has a 16-byte PCM fmt chunk and 512-byte data chunk. No external sound data is used. Duration
is about 5.33 ms; this is a deterministic mixing fixture, not a user-facing music asset.

SHA-256: `eee69f30d51c14bd10d1e892d34966a84999a128b85740d161908150e0809472`.
