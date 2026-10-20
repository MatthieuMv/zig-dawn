#!/bin/sh
# Linux maintainer integration checks. Run from the repository root.
set -eu
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
mkdir -p "$task_tmp/empty" "$task_tmp/missing-lib/lib"
ln -s /usr/include "$task_tmp/missing-lib/include"

expect_failure() {
    pattern=$1
    shift
    if "$@" > "$task_tmp/failure.log" 2>&1; then
        cat "$task_tmp/failure.log"
        printf 'Expected failure: %s\n' "$pattern" >&2
        exit 1
    fi
    if ! grep -F "$pattern" "$task_tmp/failure.log" > /dev/null; then
        cat "$task_tmp/failure.log"
        exit 1
    fi
    printf 'PASS rejection: %s\n' "$pattern"
}

expect_failure 'package not found: sdl3' env \
    PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR="$task_tmp/empty" \
    zig build check --cache-dir "$task_tmp/cache-missing"
expect_failure 'libSDL3.so' zig build check \
    -Dsdl-provider=external -Dsdl-prefix="$task_tmp/missing-lib"

# Synthetic headers intentionally stop at preprocessing; no fake native ABI is executed.
for entry in 'SDL3 SDL SDL.h 3004017' 'SDL3_image SDL_IMAGE SDL_image.h 3004007' \
    'SDL3_mixer SDL_MIXER SDL_mixer.h 3002003' 'SDL3_ttf SDL_TTF SDL_ttf.h 3002001'; do
    set -- $entry
    library=$1 macro=$2 header=$3 old_version=$4
    fixture="$task_tmp/$library"
    mkdir -p "$fixture/include/$library"
    ln -s /usr/lib "$fixture/lib"
    for directory in SDL3 SDL3_image SDL3_mixer SDL3_ttf; do
        if [ "$directory" != "$library" ]; then
            ln -s "/usr/include/$directory" "$fixture/include/$directory"
        fi
    done
    printf '#define %s_MAJOR_VERSION 3\n#define %s_VERSION %s\n' \
        "$macro" "$macro" "$old_version" > "$fixture/include/$library/$header"
    expect_failure "zig-sdl3 requires $library headers" zig build check \
        -Dsdl-provider=external -Dsdl-prefix="$fixture" -Dimage=true -Dmixer=true -Dttf=true
done

# A newer encoded version with the wrong major is also rejected.
printf '#define SDL_MAJOR_VERSION 4\n#define SDL_VERSION 4000000\n' \
    > "$task_tmp/SDL3/include/SDL3/SDL.h"
expect_failure 'major version 3' zig build check \
    -Dsdl-provider=external -Dsdl-prefix="$task_tmp/SDL3"
