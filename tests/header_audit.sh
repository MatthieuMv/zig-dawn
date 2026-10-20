#!/bin/sh
# Verify drift rejection without modifying the real baseline or release archives.
set -eu
archives=${1:?Supply the directory containing locked release archives}
archives=$(cd "$archives" && pwd)
repository=$(pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
mkdir -p "$task_tmp/tools/coverage" "$task_tmp/archives"
cp upstream.lock.tsv "$task_tmp/"
cp tools/coverage/audit.h "$task_tmp/tools/coverage/"
cp -R tools/coverage/baseline "$task_tmp/tools/coverage/"
printf 'SDL_DeliberateDrift\tFunctionDecl\n' \
    >> "$task_tmp/tools/coverage/baseline/declarations.tsv"
if (cd "$task_tmp" && sh "$repository/tools/coverage/header_audit.sh" \
    "$archives" output --check) > "$task_tmp/drift.log" 2>&1; then
    printf 'Expected baseline drift rejection\n' >&2
    exit 1
fi
grep -F 'Upstream audit drift: declarations.tsv' "$task_tmp/drift.log"

# A corrupt first archive must fail before extraction or compiler execution.
printf 'not a release archive\n' > "$task_tmp/archives/SDL3-3.4.18.tar.gz"
if (cd "$task_tmp" && sh "$repository/tools/coverage/header_audit.sh" \
    "$task_tmp/archives" output) > "$task_tmp/hash.log" 2>&1; then
    printf 'Expected archive checksum rejection\n' >&2
    exit 1
fi
grep -F 'FAILED' "$task_tmp/hash.log"
