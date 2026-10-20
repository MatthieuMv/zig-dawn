#!/usr/bin/env python3
"""Regenerate the pinned C-macro reference: python3 tools/coverage/pixel_macros.py > src/core/fixtures/pixel-formats.tsv."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

include = subprocess.check_output(['pkg-config', '--variable=includedir', 'sdl3'], text=True).strip()
header = (Path(include) / 'SDL3/SDL_pixels.h').read_text()
body = header.split('typedef enum SDL_PixelFormat\n{')[1].split('} SDL_PixelFormat;')[0]
names = list(dict.fromkeys(re.findall(r'SDL_PIXELFORMAT_\w+(?=\s*=)', body)))
values = ',\n'.join(names + ['0xdeadbeefu', '0x10000000u', '1u'])
macros = ['FOURCC', 'INDEXED', 'PACKED', 'ARRAY', 'FLOAT', '10BIT', 'ALPHA']
flags = ' | '.join(f'((unsigned)SDL_ISPIXELFORMAT_{macro}(format) << {i})'
                   for i, macro in enumerate(macros))
source = '''#include <SDL3/SDL.h>
#include <stdio.h>
#if SDL_VERSION != 3004018
#error This fixture requires pinned SDL 3.4.18 headers
#endif
int main(void) {
 const unsigned formats[] = {VALUES};
 for (unsigned i = 0; i < sizeof(formats)/sizeof(formats[0]); ++i) {
  unsigned format = formats[i];
  printf("%u\\t%u\\t%u\\t%u\\n", format, (unsigned)SDL_BITSPERPIXEL(format),
         (unsigned)SDL_BYTESPERPIXEL(format), FLAGS);
 }
 return 0;
}
'''.replace('VALUES', values).replace('FLAGS', flags)
with tempfile.TemporaryDirectory(prefix='zig-sdl3-pixel-macros-') as directory:
    root = Path(directory)
    (root / 'reference.c').write_text(source)
    cflags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', 'sdl3'], text=True))
    subprocess.run(shlex.split(os.environ.get('CC', 'cc')) + cflags +
                   [str(root / 'reference.c'), '-o', str(root / 'reference')], check=True)
    print(subprocess.check_output([str(root / 'reference')], text=True), end='')
