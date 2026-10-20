#!/bin/sh
# Offline maintainer tool: Zig, POSIX shell/awk/sort, tar, find, and sha256sum.
# Usage: sh tools/coverage/header_audit.sh ARCHIVE_DIRECTORY [OUTPUT_DIRECTORY] [--check]
set -eu
if [ "$(zig version)" != 0.17.0 ]; then
    printf 'Header audit requires Zig 0.17.0\n' >&2
    exit 1
fi
archives=${1:?Supply a directory containing the four locked release archives}
output=${2:-zig-out/header-audit}
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
mkdir -p "$output"
output=$(cd "$output" && pwd)
tab=$(printf '\t')
tail -n +2 upstream.lock.tsv | while IFS="$tab" read -r library version url hash; do
    archive="$archives/$library-$version.tar.gz"
    printf '%s  %s\n' "$hash" "$archive" | sha256sum -c -
    tar -xzf "$archive" -C "$task_tmp"
done

# Use a response file so include directories containing spaces remain single arguments.
: > "$task_tmp/includes.rsp"
tail -n +2 upstream.lock.tsv | while IFS="$tab" read -r library version url hash; do
    printf '"-I%s/%s-%s/include"\n' "$task_tmp" "$library" "$version"
done > "$task_tmp/includes.rsp"

# -E avoids a Zig 0.17 cc-driver object-output error with -fsyntax-only + -ast-dump.
# The Clang action override still produces the AST; extraction below checks known anchors.
zig cc -target x86_64-linux-gnu -E -Xclang -ast-dump \
    @"$task_tmp/includes.rsp" tools/coverage/audit.h \
    > "$output/native.ast.txt"
awk '
    /FunctionDecl|TypedefDecl|EnumDecl|EnumConstantDecl|RecordDecl|VarDecl/ {
        kind = ""
        for (i = 1; i <= NF; i++) {
            if ($i ~ /(FunctionDecl|TypedefDecl|EnumDecl|EnumConstantDecl|RecordDecl|VarDecl)$/) {
                kind = $i
                sub(/^[|` -]*/, "", kind)
            }
            if ($i ~ /^(SDLK?_|IMG_|MIX_|TTF_)[A-Za-z0-9_]+$/) print $i "\t" kind
        }
    }
' "$output/native.ast.txt" | LC_ALL=C sort -u > "$output/declarations.tsv"
grep -F 'SDL_GetVersion' "$output/declarations.tsv" > /dev/null
grep -F 'TTF_CreateText' "$output/declarations.tsv" > /dev/null
zig cc -target x86_64-linux-gnu -E -dM @"$task_tmp/includes.rsp" tools/coverage/audit.h \
    > "$task_tmp/macros.txt"
LC_ALL=C sort "$task_tmp/macros.txt" > "$output/native.macros.txt"
awk '$1 == "#define" && $2 ~ /^(SDLK?_|IMG_|MIX_|TTF_)/ {
    name = $2; sub(/\(.*/, "", name); print name "\tmacro"
}' "$output/native.macros.txt" | LC_ALL=C sort -u > "$output/macros.tsv"

# Hash and scan every shipped header, including uncompiled platform/test/GL headers.
# Candidate names include comment references: this is an intentional conservative superset.
(cd "$task_tmp" && find . -path '*/include/*' -name '*.h' -type f | LC_ALL=C sort) \
    > "$output/headers.list"
: > "$output/header-sha256.tsv"
: > "$output/conditional-directives.tsv"
: > "$output/candidates.tsv"
while IFS= read -r header; do
    (cd "$task_tmp" && sha256sum "$header") >> "$output/header-sha256.tsv"
    awk -v path="$header" '
        /^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|else|endif)([ \t]|$)/ {
            print path "\t" FNR "\t" $0
        }
    ' "$task_tmp/$header" >> "$output/conditional-directives.tsv"
    awk -v path="$header" '{
        gsub(/[^A-Za-z0-9_]/, " ")
        for (i = 1; i <= NF; i++)
            if ($i ~ /^(SDLK?_|IMG_|MIX_|TTF_)[A-Za-z0-9_]+$/) print $i "\t" path
    }' "$task_tmp/$header" >> "$output/candidates.tsv"
done < "$output/headers.list"
LC_ALL=C sort -u "$output/candidates.tsv" > "$task_tmp/candidates.sorted"
mv "$task_tmp/candidates.sorted" "$output/candidates.tsv"
if [ "${3:-}" = --check ]; then
    for report in declarations.tsv macros.tsv header-sha256.tsv; do
        if ! cmp -s "tools/coverage/baseline/$report" "$output/$report"; then
            printf 'Upstream audit drift: %s (review before replacing baseline)\n' "$report" >&2
            exit 1
        fi
    done
fi
# Compare independent declarations/macros against the current translated inventory when supplied.
# Absence is reported, not silently classified as intentionally raw-only.
if [ -f zig-out/coverage/symbols.tsv ]; then
    cut -f1 "$output/declarations.tsv" "$output/macros.tsv" | LC_ALL=C sort -u \
        > "$task_tmp/expected.names"
    tail -n +2 zig-out/coverage/symbols.tsv | cut -f1 | LC_ALL=C sort -u \
        > "$task_tmp/translated.names"
    LC_ALL=C comm -23 "$task_tmp/expected.names" "$task_tmp/translated.names" \
        > "$output/not-translated.txt"
fi
printf 'Audit written to %s\n' "$output"
